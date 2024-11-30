echom "hi"
" if has('nvim')
" lua << EOF
" local lspconfig = require('lspconfig')
" local root_pattern = require('lspconfig.util').root_pattern
" lspconfig.rust_analyzer.setup {
"   settings = {
"     ['rust-analyzer'] = {
"               check = {
"           overrideCommand = { "bazel", "build", "--@rules_rust//:error_format=json", "//rust-code/..." },
"           enabled = true
"         },
"       },
"   },
"   -- root_dir = root_pattern("rust-project.json")
" }
" EOF
" endif
