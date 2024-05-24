load(":dl.bzl", "dl")

def _node_lib(ctx):
    version = ctx.attr.version
    arch = ctx.attr.arch
    sha256 = ctx.attr.sha256
    filename = "node-"+version+"-"+arch+".tar.xz"
    out = ctx.actions.declare_file(filename)
    url = "https://nodejs.org/dist/"+arch+"/"+filename
    dl(ctx, url, filename, out, sha256)
    return [DefaultInfo(files = depset([out]))]


def node_lib(name, version, sha256):
    arch = select({
        ":linux-x86_64": "linux-x64",
        ":macos-arm64": "darwin-arm64",
        ":macos-x86_64": "darwin-x64",
    })
    node_lib_internal(
      name = name,
      version = version,
      arch = arch,
      sha256 = sha256,
    )

node_lib_internal = rule(
    implementation = _node_lib,
    attrs = {
        "version": attr.string(mandatory = True, default = "v16.16.0"),
        "arch": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
    },
)

cpus = ['x86_64', 'arm64']
oses = ['linux', 'macos']
def node_platforms():
    [[native.config_setting(
        name = os + "-" + cpu,
        constraint_values = [
            "@platforms//cpu:" + cpu,
            "@platforms//os:" + os,
        ],
    ) for cpu in cpus] for os in oses]

