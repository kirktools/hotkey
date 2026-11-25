.DEFAULT_GOAL := help
CONFIG ?= debug
BUMP ?= patch
export CONFIG BUMP
.PHONY: help dev test check build package release-dry-run release translation-plugin signing-prepare signing-ci
help:
	@printf '%s\n' 'make dev | test | check | build [CONFIG=release] | package' 'make release-dry-run [BUMP=patch|minor|major]' 'make release [BUMP=patch|minor|major]' 'make translation-plugin [CONFIG=release]' 'make site | site-check | site-preview'
dev:
	@./scripts/run.sh
test:
	@./scripts/test.sh
check:
	@./scripts/check.sh
build:
	@./scripts/build.sh "$(CONFIG)"
translation-plugin:
	@./scripts/build-translation-plugin.sh "$(CONFIG)"
package:
	@./scripts/package.sh
release-dry-run:
	@python3 scripts/release.py --dry-run
release:
	@python3 scripts/release.py
signing-prepare:
	@python3 scripts/release-signing.py prepare
signing-ci:
	@python3 scripts/release-signing.py upload

.PHONY: site site-check site-preview
site:
	@python3 scripts/site.py build
site-check:
	@python3 scripts/site.py check
site-preview:
	@python3 scripts/site.py preview
