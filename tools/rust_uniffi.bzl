load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_android//android:rules.bzl", "android_library")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("@rules_rust//rust:defs.bzl", "rust_shared_library")

def rust_uniffi_bindgen(name, srcs, **kwargs):
    native.genrule(
        name = name + "-cargo",
        outs = [
            name + "/Cargo.toml",
        ],
        cmd = """
echo "creating: $@"
cat > $@ << 'EOF'
# @generated just for the name attribute
[package]
name = "%s"
version = "0.1.0"
edition = "2024"

[lib]
path = "fake.rs"
EOF
""" % name,
    )
    dirname_provider(
        name = name + "-cargo-dirname",
        path = ":%s-cargo" % name,
    )

    rust_shared_library(
        name = name + "-lib",
        srcs = srcs,
        compile_data = [":%s-cargo" % name],
        rustc_env = {
            "CARGO_MANIFEST_DIR": "$(DIRNAME)",
        },
        deps = ["@crates//:uniffi"],
        toolchains = [":%s-cargo-dirname" % name],
    )

    native.genrule(
        name = name,
        srcs = [":%s-lib" % name],
        outs = [
            name + ".swift",
            name + "FFI.h",
            name + "FFI.modulemap",
            "uniffi/%s/%s.kt" % (name, name),
        ],
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
        hdrs = [
            ":%sFFI.h" % name,
        ],
        module_name = name + "FFI",
        deps = [
            ":%s-lib" % name,
        ],
    )

    swift_library(
        name = name + "-swift",
        srcs = [":%s.swift" % name],
        module_name = name,
        deps = [":%s-objc" % name],
    )

    android_library(
        name = name + "-lib-android",
        exports = [":%s-lib" % name],
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
        srcs = ["uniffi/%s/%s.kt" % (name, name)],
        deps = select({
            "@platforms//os:android": ["@maven_compose_android//:net_java_dev_jna_jna"] + [
                ":%s-lib-android" % name,
            ],
            "//conditions:default": ["@maven_compose//:net_java_dev_jna_jna"],
        }),
        resources = select({
            "@platforms//os:android": [],
            "//conditions:default": ["%s-lib-macos" % name],
        }),
        resource_strip_prefix = native.package_name(),
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
