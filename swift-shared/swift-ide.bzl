load("@rules_xcodeproj//xcodeproj:defs.bzl", "top_level_target", "xcodeproj")
load("@sourcekit_bazel_bsp//rules:setup_sourcekit_bsp.bzl", "setup_sourcekit_bsp")

def ide(xcode_project_name, targets, xcode_targets = None):
    if xcode_targets == None:
        xcode_targets = targets

    top_level_targets = [top_level_target(
        target,
        target_environments = [
            "device",
            "simulator",
        ],
    ) for target in xcode_targets]

    # for using XCode. Regenerate whenever BUILD graph changes
    # bazel run //path:xcodeproj && xed path/name.xcodeproj
    xcodeproj(
        name = "xcodeproj",
        project_name = xcode_project_name,
        tags = ["manual"],
        top_level_targets = top_level_targets,
    )

    # to use with VSCode + Swift extension
    # bazel run //path:setup-bsp
    # Debug with:
    # $ log stream --process sourcekit-bazel-bsp --debug --style compact
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
