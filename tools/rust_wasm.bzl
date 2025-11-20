load("@rules_rust//rust:defs.bzl", "rust_shared_library")

def rust_wasm_bindgen(name, srcs, **kwargs):
    rust_shared_library(
        name = name + "-wasm",
        srcs = ["lib-wasm.rs"],
        platform = "@rules_rust//rust/platform:wasm",
        deps = [
            "@crates//:wasm-bindgen",
        ],
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
            "$(location //tools:wasm-bindgen)" $(SRCS) --out-dir $(@D) --web --out-name %s
            # ls -alh $(@D)
            """ % name,
        tools = ["//tools:wasm-bindgen"],
    )
