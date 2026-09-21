# Re-Capture GUI review — 2026-09-21

## Scope and design contract

Update the macOS settings interface and menu bar entry, keeping the existing
processing controller, storage, security-scoped folder access, deployment target,
and privacy boundaries. Baseline: `09c2f26`; working tree was clean.

Use three standard settings panes: General for automatic processing and setup,
Folders for source/destination access, and Output for transfer/naming/conversion.
Use grouped SwiftUI forms, semantic fonts/colors, standard controls and a persistent
status area. Preserve the most recently selected pane. Offer a smaller initial
window with scrollable forms and enough space for Japanese localization.

Make the original-file consequences of Move/Copy visible. Existing-file processing
has a separate confirmation with a cancel action. Filename validation combines a
symbol with explanatory text, and example names use synthetic app/window data.
Folder pickers attach to the settings window and use descriptive accessibility
labels. No custom motion or appearance overrides are introduced.

The standard Settings scene and menu bar workflow remain. This is a scoped
HIG-alignment change, not a certification or an App Store submission.

## Platform and sources

- Minimum OS: macOS 26.0, unchanged (`project.yml`).
- Build toolchain: Xcode 27.0 (27A266a).
- Runtime: macOS 27.0 (26A428).
- [Apple releases](https://developer.apple.com/news/releases/) retrieved 2026-09-21:
  macOS 27.0 / Xcode 27 released September 14; macOS 27.2 beta listed September 16.
  The public runtime is the one tested; a prerelease SDK/runtime is not required.

| ID | Class | Source and scoped decision | Retrieved |
| --- | --- | --- | --- |
| S1 | APPLE-HIG | [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), macOS: group related settings in panes, indicate the active pane, restore the last pane, and provide Command-Comma. These are design recommendations, not SDK requirements. | 2026-09-21 |
| S2 | APPLE-HIG | [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), best practices: native menu commands, keyboard input, comfortable density. Settings-specific guidance takes precedence over general full-screen recommendations. | 2026-09-21 |
| S3 | APPLE-HIG | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), vision/mobility: prefer system colors, supplement color with other cues, name controls, and support keyboard use. | 2026-09-21 |
| S4 | APPLE-SDK | [Grouped FormStyle](https://developer.apple.com/documentation/swiftui/formstyle/grouped): grouped rows with leading labels and trailing controls; available since macOS 13. | 2026-09-21 |

HIG text retrieved from Apple's live DocC endpoint via the skill's reader because
the HTML pages exposed only a JavaScript shell. API Markdown was retrieved from
Apple's documentation endpoint. No HIG corpus is bundled here.

## Findings and changes

| ID | Baseline finding | Change | Evidence scope |
| --- | --- | --- | --- |
| GUI-01 | Fixed 880 × 760 layout and multiple fixed-width controls in a single long page | Three panes, standard grouped forms, flexible field widths, 640 × 600 content minimum and 700 × 680 default | Source; rendering verification below |
| GUI-02 | General transfer control separated from output settings; no nearby explanation of original-file deletion | Transfer control moved into Output with Move/Copy explanation; bulk confirmation | Source; transfer implementation unchanged |
| GUI-03 | Icon-only template help has no explicit accessible name; multiple indistinguishable Choose buttons | Labeled help button, contextual folder button names, named Quality stepper, full path help and selectable text | Source; assistive-technology behavior requires runtime verification |
| GUI-04 | No filename example and an ineffective Custom preset choice | Example rendered through the existing renderer; Custom focuses the editor; text + symbol error | Source; renderer covered by existing tests |
| GUI-05 | Menu status uses green/red styling and has no explicit settings/quit shortcuts | System-rendered app/pause symbols, accessibility state, Command-Comma and Command-Q | Source; native menu checks noted below |

## Validation

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Baseline Debug build | pass | `/tmp/recapture-hig-baseline-build.log` |
| Final Debug build and existing regression suite | pass | Xcode 27 / macOS 27; 74 existing tests + 1 temporary rendering check, 0 failures; `/tmp/recapture-hig-final-tests.log` |
| Localization syntax and whitespace | pass | `plutil -lint` for both `.strings` files; `git diff --check` |
| Form content, Japanese Light/Dark | pass | Inspected General, Folders and Output layer-rendered snapshots; field/error/action text remains readable without overlapping controls |
| English layout | pass (limited) | SwiftUI locale override checked. Prelocalized Foundation/model strings retain the host's Japanese language; full English process launch not verified |
| Minimum-size error and long paths | pass (rendering only) | 640 × 600 requested content rect; invalid-template error remains visible; long synthetic paths wrap and Choose buttons remain visible |
| Whole-window/native material appearance | blocked | Computer-use app selection repeatedly timed out. ScreenCaptureKit returned TCC denial (-3801). Layer rendering cannot establish composited toolbar appearance: selected tabs appear black and some native control colors are incomplete in these snapshots |
| Keyboard navigation, menu shortcuts, sheet cancel/focus restoration | not-run | Implemented standard controls/shortcuts and sheet presentation, but live input could not be verified with the available computer-use connection |
| VoiceOver, Accessibility Inspector, focus/reading order | not-run | Source-level semantic labels verified only; this is not a VoiceOver execution result |
| Increase Contrast / Reduce Transparency / text-size settings | not-run | Standard semantic colors/fonts retained; actual system preference variants not exercised |
| Reduced Motion | not-applicable to new effects | No custom animations introduced; system transitions not independently tested |
| macOS 26 runtime | not-run | Build target preserved; only macOS 27 runtime available |
| Non-sandboxed advanced editor, bulk confirmation interaction | not-run | Compiled and reviewed; screenshots cover sandboxed setup/output states only |

Build/test invocation:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Recapture.xcodeproj -scheme Recapture -configuration Debug \
  -derivedDataPath /tmp/recapture-hig-build -destination 'platform=macOS' \
  test CODE_SIGNING_ALLOWED=NO
```

This is a local unsigned Debug qualification, not a release archive or signing check.
The final test result is
`/tmp/recapture-hig-build/Logs/Test/Test-Recapture-2026.09.21_11-22-13-+0900.xcresult`.

## Rendering evidence and remaining checks

Local evidence is in `build/hig-review/` (ignored by Git):

- `before-ja.png`: baseline view from `09c2f26`, 880 × 760 requested content.
- `general-ja-light.png`, `folders-ja-dark.png`, `output-ja-light.png`,
  `output-ja-dark.png`: updated content at 700 × 680 requested content.
- `output-ja-light-error.png`: final correction, primary-colored error text with
  a red warning symbol, minimum requested window size.
- `folders-en-dark-long-paths.png`: synthetic long folder paths.
- `SettingsRenderingCapture.swift`: temporary rendering fixture, using isolated
  preferences and fake bookmark storage; no real screenshot files are processed.

Snapshots are rendered from the app's native view layers, not live screen captures.
They support content-layout findings, but not a claim that native compositing,
selection materials, accessibility output or interaction passed. The temporary
fixture was removed from the regression target after verification.

Before release, open the actual Settings scene and verify the active tab label in
Light/Dark appearance, Command-Comma/Command-Q, keyboard traversal, Custom editor
focus, folder-sheet cancel/focus return, bulk-confirmation cancel/confirm behavior
using disposable fixtures, and VoiceOver names/order. Verify macOS 26 separately.
At the end of the initial GUI pass, no version bump, installation, App Store
submission, commit, or push had been performed. Release preparation follows below.

## Release-preparation follow-up

Version 1.2.0 (7) was archived on 2026-09-21. The original 74 regression tests
passed with the release identifiers; see `build/AppStore/test-1.2.0-7.log`.

An isolated, temporary native-window fixture enabled actual computer-use
inspection on macOS 27. It used synthetic folder paths, isolated preferences and
an unbound processing controller. No user screenshot files were processed.

- Native Japanese and English settings were inspected. The English fixture was
  launched with `-testLanguage en -testRegion US`, including model-localized text.
- The selected toolbar tabs were readable in the composited Light appearance;
  the earlier black tabs were a limitation of layer-rendered evidence.
- Selecting Custom selected the filename text and focused the editor. Typing
  `yyyyMMdd-{app}` updated the example to `20260921-App`.
- Bulk confirmation appeared and Escape cancelled it in the Japanese fixture.
- Accessibility-tree inspection exposed the contextual folder buttons, filename
  help, template field and Quality stepper names. This is not a VoiceOver test.
- Folder selection was invoked and Escape returned to settings, but the sheet
  itself was not exposed by the bound capture; full sheet/focus qualification
  remains unverified.

The first interaction attempt was interrupted around the fixture's timed window
shutdown. A duplicate task-owned app instance was removed, and a longer isolated
fixture completed successfully (`/tmp/recapture-release-live.log`). No production
code change was required for the successfully repeated Custom interaction.

Live screenshot evidence: `build/AppStore/Screenshots-1.2.0/output-en.png`.
The computer-use capture is 1229 × 768 and contains a system capture indicator;
it is diagnostic evidence, not an App Store screenshot. The temporary test source
is saved under ignored `build/AppStore/SettingsInteractionFixture-source.swift`
and removed from the committed test target.

The earlier unperformed checks still apply except where explicitly superseded
above: actual Settings scene keyboard commands, full keyboard traversal,
VoiceOver, system accessibility appearance settings, native Dark material, bulk
execution through the UI, and macOS 26 runtime remain unverified.
See [release-1.2.0.md](release-1.2.0.md) for release gates and store status.

## Original-resolution store captures

The developer explicitly authorized the macOS `screencapture` command after the
computer-use surface could not supply suitable original-resolution files.
Window-scoped `screencapture -x -o -t jpg -l <fixture-window-id>` captured the
actual composited settings window, without a shadow or unrelated desktop data.
This resolves the original-resolution/material limitation for these captures.
No image generation, retouching, upscaling or UI reconstruction was used.

English and Japanese processes were launched independently, using the existing
SettingsView with isolated preferences, synthetic paths and a dormant controller.
All four delivered images are 1280 × 800 JPEG, with no alpha channel; every image
was visually inspected. The selected tabs, native focus indicators, text and
controls are readable. The screenshots show the same GUI shipped in builds 7
and 8; build 8 only adds distribution metadata and bundled dependency notices.

- [English folders](app-store/1.2.0/recapture-en-folders.jpg)
- [English output](app-store/1.2.0/recapture-en-output.jpg)
- [Japanese folders](app-store/1.2.0/recapture-ja-folders.jpg)
- [Japanese output](app-store/1.2.0/recapture-ja-output.jpg)

Both App Store Connect localizations now show the two corresponding new images;
the old images were removed from the draft, and the saved previews were visually
checked. Temporary fixture code was removed from the test target. Remaining
runtime coverage limits above are not superseded by these screenshots.
