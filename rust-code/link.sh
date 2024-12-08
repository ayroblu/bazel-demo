#!/bin/zsh
cd $(git root)
bazel build -c opt //rust-code/editor-tools/js-function-style
bazel build -c opt //rust-code/editor-tools/lang-move
bazel build -c opt //rust-code/bazel-args:all
rsync .bazel/bin/rust-code/editor-tools/js-function-style/js-function-style ~/bin/
rsync .bazel/bin/rust-code/editor-tools/lang-move/lang-move ~/bin/
rsync .bazel/bin/rust-code/bazel-args/ibazel-args ~/bin/
rsync .bazel/bin/rust-code/bazel-args/bazel-args ~/bin/
cd -
