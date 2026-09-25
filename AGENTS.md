# Botch

A menu bar app whose only feature is a tabbed WebKit browser that lives in the notch, signed in
with a Google Chrome profile. SwiftPM package, macOS 14+, Swift 6 toolchain in Swift 5 mode.

## Layout

- `Sources/BotchKit/Browser`: Chrome profile, cookie and local storage readers, the browser store,
  tabs, web delegate and the SwiftUI browser chrome.
- `Sources/BotchKit/Notch`: notch panel, geometry, hover gate, controller and content view.
- `Sources/BotchKit/App`: settings, onboarding and settings window, menu bar app delegate.
- `Sources/Botch`: executable entry point.
- `Tests/BotchTests`: Swift Testing suites with synthetic Chrome fixtures and a local HTTP server.
- `desktop/`: the Linux and Windows edition, Tauri 2 with the CLI pinned in `package.json` and
  run through `bunx tauri`. `src-tauri/src` holds the Rust shell (`shell.rs` window, tabs and
  tray; `chrome.rs`, `cookies.rs`, `crypto.rs` profile and cookie import; `address.rs`,
  `session.rs`), `ui/` is plain HTML, CSS and JS with no bundler. Each tab is a child webview
  (Tauri `unstable` feature). Tests use synthetic databases and keys only.

## Commands

- `make build`, `make test`, `make lint`, `make format`
- `make app` builds, ad-hoc signs and packages `dist/Botch.app`, `Botch.zip` and `Botch.dmg`
- `make icon` regenerates `Resources/AppIcon.icns` from `scripts/icon.swift`
- `make desktop-lint`, `make desktop-test`, `make desktop-build` for `desktop/`; the
  `Desktop` workflow runs them on Ubuntu and Windows, and `release.yml` uploads the `.deb`,
  `.AppImage`, `.msi` and setup `.exe` to the tag's release after the macOS job creates it

Building needs Xcode; the Makefile picks `/Applications/Xcode*.app` when `xcode-select` points
at the command line tools.

## Rules

- No comments in code. Names and structure carry the meaning.
- `swift format lint --strict` must pass; run `make format` before committing.
- Never read the real Chrome profile in tests. Use `SyntheticChrome` from the fixtures.
- Keep the feature set as is: no extra notch widgets, no extensions, no main window.
- Screenshots and evidence use mock data only. `BOTCH_SNAPSHOT_DIR=docs make test` renders
  `docs/botch.png` from the real notch panel with mock pages. For a live run with mock data,
  export a synthetic profile with `BOTCH_MOCK_CHROME_OUT=/tmp/mock-chrome make test`, then start
  `dist/Botch.app/Contents/MacOS/Botch` with `BOTCH_MOCK_CHROME=/tmp/mock-chrome` and
  optionally `BOTCH_MOCK_OPEN=<seconds>` to open the notch on launch and collapse it later.

## CI checks

`make ci` runs every check below on macOS after `bun install --frozen-lockfile`; `make ci-tools`
installs the missing binaries with Homebrew. GitHub Actions runs the same targets: `policy` on
Ubuntu, `links` on `main` pushes and weekly, `swift` on macOS. Each check has its own target so
a focused change can run one of them.

- `ci-comments`: no comments in any code or config file (Swift, Rust, JS/TS, CSS, JSON, YAML,
  HTML, TOML, shell, Makefile). Only functional directives survive: shebangs,
  `// swift-tools-version`, `// swiftlint:`, `// swift-format-`, `biome-ignore`, `@ts-*`,
  `eslint-*`, `/*! */` license blocks, `# shellcheck`, and the `# vX.Y.Z` marker after a SHA pin.
- `ci-emdash`: no em-dash character in any tracked text file. `ci-commits` applies the same rule
  to commit messages on the branch.
- `ci-attribution`: no AI attribution in files, commit messages or branch names (no
  `Co-Authored-By` trailers, no vendor or tool names, no `ai/` or similar branch prefixes).
- `ci-secrets`: gitleaks over the history plus a pattern scan for private keys, vendor tokens
  and high-entropy assignments.
- `ci-hygiene`: no trailing whitespace, LF endings with one final newline, no files over 1 MB
  except the app icon and `docs/*.png`, executable bit only on `install.sh` and `scripts/*.sh`,
  no duplicate JSON keys, `shellcheck -S style` and `bash -n` on every shell script, the README
  install one-liner and `install.sh` download URL, and `ci-plist` (`plutil -lint` plus
  `LSUIElement` and `NSAllowsArbitraryLoadsInWebContent` set to true).
- `ci-yaml`, `ci-markdown`, `ci-links`: `yamllint --strict`, `markdownlint-cli2` and `lychee`
  with the configs at the repository root.
- `ci-workflows`: `actionlint`, `zizmor --persona=pedantic --min-severity=medium` and
  `scripts/check-workflows.mjs`, which requires every `uses:` to be pinned to a 40-character SHA
  with a version comment, `permissions` and `timeout-minutes` on every job, and
  `persist-credentials: false` on every checkout.
- `ci-scripts`: `bun test scripts`, one test file per checker.
- `ci-swift`: `swift format lint --strict`, `swift build` and `swift test`.
