SELECTED_DEV_DIR := $(shell xcode-select -p 2>/dev/null)
ifneq ($(wildcard $(SELECTED_DEV_DIR)/usr/bin/xcodebuild),)
  DEVELOPER_DIR := $(SELECTED_DEV_DIR)
else
  DEVELOPER_DIR := $(firstword $(wildcard /Applications/Xcode*.app/Contents/Developer))
endif
export DEVELOPER_DIR

SWIFT_FILES := Sources Tests Package.swift
SHELL_FILES := install.sh $(wildcard scripts/*.sh)
WORKFLOWS := $(wildcard .github/workflows/*.yml)
BASE ?= $(shell git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null)
HEAD ?= HEAD
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)

.PHONY: build test lint format app icon clean desktop-build desktop-test desktop-lint
.PHONY: ci ci-tools ci-comments ci-emdash ci-attribution ci-commits ci-secrets ci-gitleaks
.PHONY: ci-hygiene ci-plist ci-yaml ci-markdown ci-links ci-workflows ci-scripts ci-swift

build:
	swift build

test:
	swift test

lint:
	swift format lint --strict --recursive $(SWIFT_FILES)

format:
	swift format --in-place --recursive $(SWIFT_FILES)

app:
	scripts/bundle.sh

icon:
	swift scripts/icon.swift AppIcon.iconset
	iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
	rm -rf AppIcon.iconset

clean:
	rm -rf .build dist

desktop-build:
	cd desktop && bun install --frozen-lockfile && bunx tauri build

desktop-test:
	cd desktop/src-tauri && cargo test --locked

desktop-lint:
	cd desktop/src-tauri && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings

ci:
	bun install --frozen-lockfile
	$(MAKE) ci-comments ci-emdash ci-attribution ci-commits ci-secrets ci-hygiene ci-yaml ci-markdown ci-links ci-workflows ci-scripts ci-swift

ci-tools:
	brew install yamllint lychee gitleaks actionlint zizmor shellcheck || true
	bun install --frozen-lockfile

ci-comments:
	bun scripts/check-comments.mjs

ci-emdash:
	bun scripts/check-emdash.mjs

ci-attribution:
	bun scripts/check-attribution.mjs

ci-commits:
	@test -n "$(BASE)" || { echo "no merge base with main; pass BASE=<sha>" >&2; exit 1; }
	bun scripts/check-emdash.mjs --commits "$(BASE)..$(HEAD)"
	bun scripts/check-attribution.mjs --commits "$(BASE)..$(HEAD)" --branch "$(BRANCH)"

ci-secrets: ci-gitleaks
	bun scripts/check-secrets.mjs

ci-gitleaks:
	@command -v gitleaks >/dev/null || { echo "gitleaks missing: run make ci-tools" >&2; exit 1; }
	gitleaks git --no-banner --redact --log-opts="HEAD" .

ci-hygiene:
	@command -v shellcheck >/dev/null || { echo "shellcheck missing: run make ci-tools" >&2; exit 1; }
	bun scripts/check-hygiene.mjs
	shellcheck -S style $(SHELL_FILES)
	for f in $(SHELL_FILES); do bash -n "$$f"; done
	grep -q 'curl -fsSL https://raw.githubusercontent.com/pulkitxm/botch/main/install.sh | bash' README.md
	grep -q '^url="https://github.com/pulkitxm/botch/releases/latest/download/Botch.zip"$$' install.sh
	@if command -v plutil >/dev/null; then $(MAKE) ci-plist; else echo "plutil unavailable, Info.plist lint runs in the macOS job"; fi

ci-plist:
	plutil -lint Resources/Info.plist
	plutil -extract LSUIElement raw Resources/Info.plist | grep -qx true
	plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoadsInWebContent raw Resources/Info.plist | grep -qx true

ci-yaml:
	@command -v yamllint >/dev/null || { echo "yamllint missing: run make ci-tools" >&2; exit 1; }
	yamllint --strict .

ci-markdown:
	bunx markdownlint-cli2

ci-links:
	@command -v lychee >/dev/null || { echo "lychee missing: run make ci-tools" >&2; exit 1; }
	lychee --config lychee.toml './**/*.md'

ci-workflows:
	@command -v actionlint >/dev/null || { echo "actionlint missing: run make ci-tools" >&2; exit 1; }
	@command -v zizmor >/dev/null || { echo "zizmor missing: run make ci-tools" >&2; exit 1; }
	actionlint .github/workflows/*.yml
	zizmor --persona=pedantic --min-severity=medium --format=plain $(WORKFLOWS)
	bun scripts/check-workflows.mjs $(WORKFLOWS)

ci-scripts:
	bun test scripts

ci-swift: lint build test
