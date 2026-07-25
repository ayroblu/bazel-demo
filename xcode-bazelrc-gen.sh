#!/bin/bash

# https://github.com/bazelbuild/rules_apple/blob/master/doc/common_info.md#xcode-version-selection-and-invalidation
# bazel_real="$BAZEL_REAL"
bazelrc_lines=()

if [[ $OSTYPE == darwin* ]]; then
  xcode_path=$(xcode-select -p)
  xcode_version=$(xcodebuild -version | tail -1 | cut -d " " -f3)
  xcode_build_number=$(/usr/bin/xcodebuild -version 2>/dev/null | tail -1 | cut -d " " -f3)

  # bazelrc_lines+=("startup --host_jvm_args=-Xdock:name=$xcode_path")
  bazelrc_lines+=("build --xcode_version=$xcode_version")
  bazelrc_lines+=("build --repo_env=XCODE_VERSION=$xcode_version")
  # bazelrc_lines+=("build --repo_env=DEVELOPER_DIR=$xcode_path")

  # Manage xcode versions with:
  # print current version
  # xcode-select -p
  # pick xcode version
  # sudo xcode-select -s /Applications/Xcode16.2.app/Contents/Developer
fi

printf '%s\n' "${bazelrc_lines[@]}" > xcode.bazelrc
