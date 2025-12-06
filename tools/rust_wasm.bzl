load("@rules_rust//rust:defs.bzl", "rust_shared_library")

def rust_wasm_bindgen(name, srcs, is_debug = False, **kwargs):
    rust_shared_library(
        name = name + "-wasm",
        srcs = srcs,
        platform = "@rules_rust//rust/platform:wasm",
        rustc_flags = ["-g"] if is_debug else [],
        deps = [
            "@crates//:wasm-bindgen",
        ],
        **kwargs
    )

    native.genrule(
        name = name,
        srcs = [":%s-wasm" % name],
        outs = [
            name + "_bg.wasm",
            name + "_bg.wasm.d.ts",
            name + ".d.ts",
            name + ".js",
        ],
        cmd = """
            "$(location //tools:wasm-bindgen)" $(SRCS) --out-dir $(@D) --keep-debug --target nodejs --out-name %s
            # echo '{"type": "module"}' > $(@D)/package.json
            # ls -alh $(@D)
            """ % name,
        tools = ["//tools:wasm-bindgen"],
    )
