#!/bin/zsh
cd $(git root)
bazel build -c opt\
  //rust-code/editor-tools/js-function-style\
  //rust-code/editor-tools/ternary-condition\
  //rust-code/editor-tools/lang-move\
  //rust-code/bazel-args:all\
  //rust-code/terraform-targets
rsync .bazel/bin/rust-code/editor-tools/js-function-style/js-function-style ~/bin/
rsync .bazel/bin/rust-code/editor-tools/ternary-condition/ternary-condition ~/bin/
rsync .bazel/bin/rust-code/editor-tools/lang-move/lang-move ~/bin/
rsync .bazel/bin/rust-code/bazel-args/ibazel-args ~/bin/
rsync .bazel/bin/rust-code/bazel-args/bazel-args ~/bin/
rsync .bazel/bin/rust-code/terraform-targets/terraform-targets ~/bin/
cd rust-code
./setup-rust-analyzer
