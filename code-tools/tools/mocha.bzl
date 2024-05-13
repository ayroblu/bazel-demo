"Wrapper around mocha_test"
load("@code-tools-npm//code-tools:mocha/package_json.bzl", "bin")

def mocha_test(name, deps, chdir, **kwargs):
    bin.mocha_test(
        name = name,
        args = [],
        chdir = chdir,
        data = deps + [
            "//code-tools:node_modules/mocha",
        ],
        **kwargs
    )
