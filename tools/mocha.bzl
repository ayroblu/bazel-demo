"Wrapper around mocha_test"

load("@npm//:mocha/package_json.bzl", "bin")

def mocha_test(name, deps, chdir, **kwargs):
    bin.mocha_test(
        name = name,
        args = [],
        chdir = chdir,
        data = deps + [
            "//:node_modules/mocha",
        ],
        **kwargs
    )
