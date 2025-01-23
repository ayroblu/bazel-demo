Rust Code
=========

### Getting started

Rust analyzer, while handles the language server part of rust, including definitions for all packages, requires setup with bazel everytime a dependency is added.

Run: `./setup-rust-analyzer`

### Layout

Rust has a really nicer way of managing dependencies with bazel, basically all build targets are importable modules, so you can import it directly with `extern_crate`.
