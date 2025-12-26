load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_android//android:rules.bzl", "android_library")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_shared_library")

def rust_uniffi_bindgen(name, srcs, deps = [], module_name = None, extra_module_names = [], proc_macro_deps = [], **kwargs):
    module_name = module_name or name
    under_module_name = module_name.replace("-", "_")

    _uniffi_cargo(name, module_name)

    rust_library(
        name = name + "-lib",
        srcs = srcs,
        compile_data = [":%s-cargo" % name],
        rustc_env = {
            "CARGO_MANIFEST_DIR": "$(DIRNAME)",
        },
        deps = ["@crates//:uniffi"] + deps,
        proc_macro_deps = [
            "@crates//:async-trait",
        ] + proc_macro_deps,
        toolchains = [":%s-cargo-dirname" % name],
        **kwargs
    )

    rust_shared_library(
        name = name + "-shared-lib",
        srcs = srcs,
        compile_data = [":%s-cargo" % name],
        rustc_env = {
            "CARGO_MANIFEST_DIR": "$(DIRNAME)",
        },
        deps = ["@crates//:uniffi"] + deps,
        proc_macro_deps = [
            "@crates//:async-trait",
        ] + proc_macro_deps,
        toolchains = [":%s-cargo-dirname" % name],
        **kwargs
    )

    native.genrule(
        name = name,
        srcs = [":%s-shared-lib" % name],
        outs = _uniffi_outs([under_module_name] + extra_module_names),
        cmd = """
            # echo "--------- Processing $(SRCS)"
            # Consider adding --config uniffi.toml
            "$(location //tools:uniffi-bindgen)" generate --library $(SRCS) --language swift --language kotlin --no-format --out-dir "$(@D)"
            # tree "$(@D)"
            # echo "---------"
            """,
        tools = ["//tools:uniffi-bindgen"],
    )

    native.objc_library(
        name = name + "-objc",
        hdrs = [":%sFFI.h" % (under_module_name)],
        module_name = under_module_name + "FFI",
        deps = [
            ":%s-lib" % name,
        ],
    )

    # swift doesn't bundle a shared.so lib and so we can require each library independently
    # for extra_name in extra_module_names:
    #     native.objc_library(
    #         name = name + "-" + extra_name + "-objc",
    #         hdrs = [":%sFFI.h" % (extra_name)],
    #         module_name = extra_name + "FFI",
    #         deps = [
    #             ":%s-lib" % name,
    #         ],
    #     )
    # extra_deps = [":%s-%s-objc" % (name, extra_name) for extra_name in extra_module_names]
    # swift_library(
    #     name = name + "-swift",
    #     srcs = _uniffi_swift_srcs([under_module_name] + extra_module_names),
    #     module_name = under_module_name,
    #     deps = [":%s-objc" % name] + extra_deps,
    # )
    swift_library(
        name = name + "-swift",
        srcs = [":%s.swift" % under_module_name],
        module_name = under_module_name,
        deps = [":%s-objc" % name],
    )

    android_library(
        name = name + "-lib-android",
        exports = [":%s-shared-lib" % name],
    )

    native.genrule(
        name = name + "-lib-macos",
        srcs = [":%s-lib" % name],
        outs = ["darwin-aarch64/lib%s_lib.dylib" % name],
        cmd = "mkdir -p $$(dirname $@) && cp $(SRCS) $@",
        tags = ["manual"],
    )

    kt_android_library(
        name = name + "-kotlin",
        srcs = _uniffi_kt_srcs([under_module_name] + extra_module_names),
        deps = select({
            "@platforms//os:android": ["@maven_compose_android//:net_java_dev_jna_jna"] + [
                ":%s-lib-android" % name,
            ],
            "//conditions:default": ["@maven_compose//:net_java_dev_jna_jna"],
        }) + [
            "@maven_compose//:org_jetbrains_kotlinx_kotlinx_coroutines_android",
        ],
        resources = select({
            "@platforms//os:android": [],
            "//conditions:default": ["%s-lib-macos" % name],
        }),
        resource_strip_prefix = native.package_name(),
    )

def _uniffi_outs(names):
    return [
        item
        for name in names
        for item in [
            name + ".swift",
            name + "FFI.h",
            name + "FFI.modulemap",
            "uniffi/%s/%s.kt" % (name, name),
        ]
    ]

# def _uniffi_swift_srcs(names):
#     return [
#         item
#         for name in names
#         for item in [":%s.swift" % under_module_name]
#     ]

def _uniffi_kt_srcs(names):
    return [
        item
        for name in names
        for item in [
            "uniffi/%s/%s.kt" % (name, name),
        ]
    ]

def _uniffi_cargo(name, module_name = None):
    """
    This is somewhat temporary, but necessary due to uniffi depending on Cargo.toml being present.
    Ideally in a future version of uniffi, we can remove this
    """
    native.genrule(
        name = name + "-cargo",
        outs = [
            name + "/Cargo.toml",
        ],
        cmd = """
# echo "creating: $@"
cat > $@ << 'EOF'
# @generated just for the name attribute
[package]
name = "%s"
version = "0.1.0"
edition = "2024"

[lib]
path = "fake.rs"
EOF
""" % (module_name or name),
    )

    dirname_provider(
        name = name + "-cargo-dirname",
        path = ":%s-cargo" % name,
    )

def _dirname_provider_impl(ctx):
    value = _dirname(ctx.expand_location("$(location %s)" % ctx.attr.path.label.name, targets = [ctx.attr.path]))

    return [
        platform_common.TemplateVariableInfo({
            "DIRNAME": value,
        }),
    ]

dirname_provider = rule(
    implementation = _dirname_provider_impl,
    attrs = {
        "path": attr.label(mandatory = True),
    },
)

def _dirname(path):
    """Returns the directory part of a path (like os.path.dirname)."""
    parts = path.rsplit("/", 1)
    if len(parts) == 1:
        return "."  # No '/' in path
    dir_part = parts[0]
    return "." if dir_part == "" else dir_part
