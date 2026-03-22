load("@rules_xcodeproj//xcodeproj:defs.bzl", "xcodeproj")
load("@sourcekit_bazel_bsp//rules:setup_sourcekit_bsp.bzl", "setup_sourcekit_bsp")

def ide(project_name, targets):
    # for using XCode.
    xcodeproj(
        name = "xcodeproj",
        project_name = project_name,
        tags = ["manual"],
        top_level_targets = targets,
    )

    # to use with VSCode + Swift extension
    setup_sourcekit_bsp(
        name = "setup-bsp",
        bazel_wrapper = "bazelisk",
        compile_top_level = True,
        tags = ["manual"],
        files_to_watch = [
            "**/*.swift",
            "**/*.m",
            "**/*.h",
        ],
        index_flags = [
            "config=index_build",
        ],
        targets = targets,
    )
