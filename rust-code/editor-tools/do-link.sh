#!/bin/zsh
cd $(git root)
bazel build -c opt //rust-code/editor-tools/js-function-style
rsync .bazel/bin/rust-code/editor-tools/js-function-style/js-function-style ~/bin/
cd -
