# Example from
# https://tech.davis-hansson.com/p/make/
# Also consider reference at: http://www.gnu.org/software/make/manual/

## Initial setup
SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eux -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

ifeq ($(origin .RECIPEPREFIX), undefined)
  $(error This Make does not support .RECIPEPREFIX. Please use GNU Make 4.0 or later)
endif
.RECIPEPREFIX = >

## ------------------------- Main part of the build file
AppName := vimkeys
AppTargetName := 'vimkeys (macOS)'
Configuration := Debug

# Default - top level rule is what gets ran when you run just `make`
build: DerivedData/${AppName}/Build/Products/${Configuration}/${AppName}.app
.PHONY: build

# Safari refuses to persistently load web extensions from ad-hoc-signed apps,
# and vimkeys has no provisioning profile for bazel to infer an identity from,
# so sign explicitly with the local Apple Development certificate.
bazel-register:
> identity=$$(security find-identity -v -p codesigning | grep -v CSSMERR | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
> bazel run "--@build_bazel_rules_apple//apple/build_settings:signing_certificate_name=$$identity" //vimkeys:register
.PHONY: bazel-register

js: Shared\ (Extension)/Resources/content.js Shared\ (Extension)/Resources/background.js
.PHONY: js

# ------------------

Shared\ (Extension)/Resources/content.js: $(shell rg --files src)
> npx esbuild ./src/content.js --bundle --outfile="$@"

Shared\ (Extension)/Resources/background.js: $(shell rg --files src)
> npx esbuild ./src/background.js --bundle --outfile="$@"

DerivedData/${AppName}/Build/Products/${Configuration}/${AppName}.app: $(shell rg --files 'Shared (App)' 'Shared (Extension)' 'iOS (App)' 'iOS (Extension)' 'macOS (App)' 'macOS (Extension)' '${AppName}.xcodeproj' | sed 's: :\\ :g') dist/content.js
> xcodebuild -scheme ${AppTargetName} -target ${AppTargetName} -configuration ${Configuration} -destination 'arch=arm64,platform=macOS' build
