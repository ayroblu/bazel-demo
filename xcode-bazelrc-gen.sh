#!/bin/bash

# https://github.com/bazelbuild/rules_apple/blob/master/doc/common_info.md#xcode-version-selection-and-invalidation
# bazel_real="$BAZEL_REAL"
bazelrc_lines=()

infer_codesigning_identity() {
  local preferred_identity=""
  local fallback_identity=""
  local line identity

  while IFS= read -r line; do
    [[ $line == *'"'* ]] || continue
    [[ $line == *CSSMERR* ]] && continue

    identity=${line#*\"}
    identity=${identity%%\"*}

    if [[ -z $fallback_identity && $identity != "Local Self-Signed" ]]; then
      fallback_identity=$identity
    fi

    if [[ $identity == Apple\ Development:* ]]; then
      preferred_identity=$identity
      break
    fi
  done < <(security find-identity -v -p codesigning 2>/dev/null)

  printf '%s\n' "${preferred_identity:-$fallback_identity}"
}

if [[ $OSTYPE == darwin* ]]; then
  xcode_path=$(xcode-select -p)
  xcode_version=$(xcodebuild -version | tail -1 | cut -d " " -f3)
  xcode_build_number=$(/usr/bin/xcodebuild -version 2>/dev/null | tail -1 | cut -d " " -f3)

  # bazelrc_lines+=("startup --host_jvm_args=-Xdock:name=$xcode_path")
  bazelrc_lines+=("build --xcode_version=$xcode_version")
  bazelrc_lines+=("build --repo_env=XCODE_VERSION=$xcode_version")
  # bazelrc_lines+=("build --repo_env=DEVELOPER_DIR=$xcode_path")

  signing_certificate_name=$(infer_codesigning_identity)
  if [[ -n $signing_certificate_name ]]; then
    bazelrc_lines+=("build --@build_bazel_rules_apple//apple/build_settings:signing_certificate_name=\"$signing_certificate_name\"")
  fi

  # Manage xcode versions with:
  # print current version
  # xcode-select -p
  # pick xcode version
  # sudo xcode-select -s /Applications/Xcode16.2.app/Contents/Developer
fi

printf '%s\n' "${bazelrc_lines[@]}" > xcode.bazelrc
