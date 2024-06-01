Rust Code
=========

### Getting started

Rust analyzer, while handles the language server part of rust, including definitions for all packages, requires setup with bazel everytime a dependency in Cargo.toml is changed.

Run: `./rust-analyzer`

This will also run `cargo generate-lockfile`, so that your Cargo.lock is up to date, which is a prerequisite for correct usage of rust-analyzer

### Cargo

We use Cargo.toml for dependency management only. This is mainly because it's more expressive, you can better specify patches for libraries for example.

### Layout

Rust has a really nicer way of managing dependencies with bazel, basically all build targets are importable modules, so you can import it directly with `extern_crate`.
