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

## Commands

- `make build`, `make test`, `make lint`, `make format`
- `make app` builds, ad-hoc signs and packages `dist/Botch.app`, `Botch.zip` and `Botch.dmg`
- `make icon` regenerates `Resources/AppIcon.icns` from `scripts/icon.swift`

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
