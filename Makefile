.DEFAULT_GOAL := help
CONFIG ?= debug
BUMP ?= patch
export CONFIG BUMP
.PHONY: help dev test check build package release-dry-run release
help:
	@printf '%s\n' 'make dev | test | check | build [CONFIG=release] | package' 'make release-dry-run [BUMP=patch|minor|major]' 'make release [BUMP=patch|minor|major]'
dev:
	@./scripts/run.sh
test:
	@./scripts/test.sh
check:
	@./scripts/check.sh
build:
	@./scripts/build.sh "$(CONFIG)"
package:
	@./scripts/package.sh
release-dry-run:
	@python3 scripts/release.py --dry-run
release:
	@python3 scripts/release.py
