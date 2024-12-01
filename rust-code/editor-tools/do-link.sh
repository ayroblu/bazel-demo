#!/bin/zsh
cd $(git root)
bazel build -c opt //rust-code/editor-tools/js-function-style
bazel build -c opt //rust-code/editor-tools/lang-move
rsync .bazel/bin/rust-code/editor-tools/js-function-style/js-function-style ~/bin/
rsync .bazel/bin/rust-code/editor-tools/lang-move/lang-move ~/bin/
cd -
