# Botch v0.1.0 benchmarks

Measured on 2026-09-26 with `scripts/benchmark.sh` against the released build installed at
`/Applications/Botch.app` (0.1.0, ad-hoc signed, arm64, built by CI from tag v0.1.0; its
executable is byte-identical to the one inside the published `Botch.zip`).

Repeat the run with a synthetic Chrome directory (never a real profile):

```sh
BOTCH_MOCK_CHROME_OUT=/tmp/mock-chrome make test
BOTCH_MOCK_CHROME=/tmp/mock-chrome scripts/benchmark.sh
```

## machine

| item | value | command |
|---|---|---|
| cpu | Apple M4 Pro (Mac16,7) | `sysctl -n machdep.cpu.brand_string`, `sysctl -n hw.model` |
| memory | 24 GB | `sysctl -n hw.memsize` |
| macos | 27.0 (26A428) | `sw_vers` |
| load average during the run | about 65 to 90 (other unrelated Rust and Swift builds were running) | `sysctl -n vm.loadavg` |

## sizes

| item | value | command |
|---|---|---|
| app bundle | 2.0 MB (2032 KB on disk) | `du -sh`, `du -sk /Applications/Botch.app` |
| executable | 1,854,992 bytes, arm64 only | `stat -f %z`, `lipo -archs` |
| executable segments | __TEXT 671,744 bytes, __DATA 49,152 bytes | `size` |
| resources | 208 KB (AppIcon.icns) | `du -sh Contents/Resources` |
| bundled frameworks | none (no Contents/Frameworks) | `ls Contents/Frameworks` |
| linked system frameworks | 11: AppKit, CFNetwork, ColorSync, CoreFoundation, CoreGraphics, CryptoKit, Foundation, Security, ServiceManagement, SwiftUI, WebKit | `otool -L` |
| linked swift runtime dylibs | 17 from /usr/lib/swift | `otool -L` |
| Botch.zip (release asset) | 666,902 bytes (0.64 MB) | `gh release download v0.1.0`, `stat -f %z` |
| Botch.dmg (release asset) | 1,056,639 bytes (1.01 MB) | `gh release download v0.1.0`, `stat -f %z` |
| Google Chrome 153.0.8010.53 | 2.1 GB | `du -sh "/Applications/Google Chrome.app"` |
| Safari 27.0 | 35 MB (WebKit itself lives in the shared system cache) | `du -sh /System/Cryptexes/App/System/Applications/Safari.app` |

No other browsers were installed on this machine.

## memory

Footprint is `footprint <pid>` (the "Footprint:" value, what Activity Monitor shows as Memory).
RSS is `ps -o rss= -p <pid>`. The script was run twice (runs started 00:32 and 00:38); both are
shown. Helpers are the WebKit XPC processes that appeared after Botch launched (see caveats).

| state | process | footprint run 1 (MB) | footprint run 2 (MB) | rss run 2 (MB) |
|---|---|---|---|---|
| idle collapsed, one saved tab, browser never opened | Botch | 18 | 18 | 61 |
| | helpers | none | none | none |
| | **total** | **18** | **18** | **61** |
| browser open on example.com | Botch | 34 | 33 | 99 |
| | GPU | 11 | 12 | 30 |
| | WebContent | 10 | 12 | 32 |
| | Networking | 5.7 | 5.7 | 18 |
| | **total** | **60.7** | **62.7** | **179** |
| browser open with five tabs | Botch | 37 | 37 | 111 |
| | 7 helpers (GPU, Networking, 5 WebContent) | 153.5 | 155 | 210 |
| | **total** | **190.5** | **192** | **321** |
| collapsed after five tabs, tabs kept alive | Botch | 37 | not measured | |
| | 7 helpers | 159 | not measured | |
| | **total** | **196** | not measured | |

Five tab set: example.com, en.wikipedia.org/wiki/Notch, developer.mozilla.org/en-US/,
www.wikipedia.org, news.ycombinator.com. Each state was measured 15 to 45 s after launch.

The idle footprint is 18 MB with `onboarded` already set in the mock defaults, so no window is
shown. An earlier ad hoc measurement read 33 MB idle; the likely cause is the onboarding window
being open in that launch, but a launch with onboarding shown was not repeated to confirm it.

## cpu

Each value is the second sample of `top -l 2 -s <window> -stats pid,cpu,command -pid ...`, the
average over the window where 100 means one core fully busy.

| state | window | Botch | WebContent | GPU | Networking | total run 1 | total run 2 |
|---|---|---|---|---|---|---|---|
| idle collapsed | 60 s | 0.1 | | | | 0.6 | 0.1 |
| open and idle on example.com | 30 s | 0.1 | 0.0 | 0.0 | 0.0 | 0.3 | 0.1 |
| page scrolling continuously | 30 s | 1.7 | 1.3 | 0.2 | 0.0 | 0.5 (not verified) | 3.2 |
| collapsed after five tabs | 60 s | not measured | | | | | |

Per-process columns are from run 2. The scrolling page is a local 400 paragraph page that scrolls
itself by 6 px every 16 ms. In run 2 the page was confirmed to be served (HTTP 200 from the local
server, the session file pointed at it, and the new WebContent process was busy). Run 1 did not
check this and its much lower number suggests the page had not loaded or was not rendering, so use
run 2. An earlier independent measurement read Botch 1.0% and WebContent 0.7%.

The 60 s CPU window for "collapsed after five tabs" and run 2 of its memory were not measured:
both runs were stopped before that phase finished because the benchmark opens the notch on screen
and was interrupting other work on the machine.

## startup

Launch time is the time from spawning `Contents/MacOS/Botch` until CGWindowListCopyWindowInfo
lists a window owned by the new pid at window level 33 (statusBar + 8, the collapsed notch
panel), polled every 2 ms. The mock profile has one saved tab and the browser is not opened.

| run | launch to notch panel (ms) |
|---|---|
| warm 1 | 194 |
| warm 2 | 174 |
| warm 3 | 185 |
| warm 4 | 161 |
| warm 5 | 143 |
| warm min | 143 |
| warm median | 174 |
| first launch of a fresh copy of the app | 549 |

"Warm" runs relaunch the installed app back to back. The fresh copy row is the first launch of
`Botch.app` copied to a new directory, which includes the signature check macOS does on the first
run from a new path; a true cold start after a reboot was not measured.

## open latency

Measured in-process by `Tests/BotchTests/NotchOpenTimingTests.swift`
(`BOTCH_TIMING=1 swift test --filter NotchOpenTimingTests`) with a mock profile and a page that
is already loaded in the selected tab. "attached" is the time from `NotchController.openBrowser()`
until the web view is inside the panel window; "painted" is until `WKWebView.takeSnapshot`
first returns an image. Real use adds the 100 ms hover dwell (`NotchController.openDwell`)
before `openBrowser()` runs.

Not measured for this release. The test opens a real notch panel on screen and could not be run
while the machine was in use. Run it with:

```sh
BOTCH_TIMING=1 swift test --filter NotchOpenTimingTests
```

It prints per-run "attached" and "painted" times plus min, median and max over 5 runs. The hover
dwell before any open is fixed at 100 ms (`NotchController.openDwell`).

## caveats

- Mock profile: the synthetic Chrome directory has two profiles with a handful of cookies and one
  localStorage entry. A real profile with thousands of cookies takes longer to import on attach;
  that import is not part of any number here.
- Concurrent load: other builds ran on this machine during the run (load average 65 to 90).
  Per-process CPU and memory of Botch are unaffected by that; wall clock numbers (startup, open
  latency) are, if anything, pessimistic.
- WebKit helpers (`com.apple.WebKit.WebContent`, `.Networking`, `.GPU`) are system XPC services
  launched by launchd for Botch, so `ps` reports launchd as their parent. They were attributed by
  diffing the WebKit process list before and after launching Botch, and by checking that they
  started after Botch and exited when Botch quit. They are separate processes and are listed
  separately from the Botch process itself.
- Memory is reported as physical footprint (`footprint <pid>`, the "Footprint:" header) and as
  resident set size (`ps -o rss`). Footprint is what Activity Monitor calls Memory; RSS also
  counts shared pages of system frameworks and is always larger.
- CPU is the second sample of `top -l 2 -s <window>`, so each value is the average over the
  window on a single core basis (100 means one core busy).
- Ad-hoc signed release build; no notarization.
- Network pages (example.com, wikipedia, mdn, hacker news) were loaded live, so the five tab
  numbers depend on those pages on that day.
