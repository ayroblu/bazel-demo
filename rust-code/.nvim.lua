local lspconfig = require('lspconfig')
lspconfig.rust_analyzer.setup {
  settings = {
    ['rust-analyzer'] = {
      check = {
        overrideCommand = { "bazel", "--output_base=/tmp/bazel/rust", "build", "--@rules_rust//rust/settings:error_format=json", "//rust-code/..." },
        enabled = true
      },
    },
  },
}
