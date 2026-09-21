# Re-Capture

Re-Capture is a lightweight macOS menu bar app for managing native macOS
screenshots.

It watches a screenshot folder selected by the user with FSEvents, then safely
moves or copies new screenshots to a selected destination folder, with a
configurable filename template and optional image conversion. Select the same
folder that macOS Screenshot uses for its output.

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later
- XcodeGen

## Current Features

- Uses the native macOS screenshot workflow
- Watches the configured screenshot folder with FSEvents
- Moves or copies screenshots to a user-selected destination folder
- Configurable filename template, for example `yyyyMMdd-HHmmss`
- Best-effort `{app}`, `{title}`, and `{sequence}` template tokens
- Source screenshot formats: PNG, JPEG, PDF, and TIFF
- Optional conversion targets: HEIC, WebP, AVIF, BMP, and PSD when the system
  ImageIO stack supports the target format
- Native Screenshot settings guidance and an explicit watched-folder picker
- Read-only refresh of available `com.apple.screencapture` defaults; direct
  editing is enabled only for confirmed non-sandboxed builds
- Bulk rename/convert for existing screenshots
- Login item toggle
- Open destination folder in Finder

## File Storage

Settings are grouped into **General**, **Folders**, and **Re-Capture Output**.
Use **Command-Comma** to open settings. The Output pane shows an example filename,
explains whether originals are moved or retained, and asks for confirmation before
processing existing screenshots. The most recently selected settings pane is restored.

Re-Capture does not use its app sandbox container for screenshot output. Before
any screenshot is saved by Re-Capture, the user must choose both a watched folder
and an output folder with the standard macOS folder picker. If either folder is missing,
automatic processing and bulk rename/convert remain inactive.

### macOS Screenshot Settings

In sandboxed builds (including App Store builds), Re-Capture does not directly
write another application's preferences. Use **Open Screenshot** or
**Shift-Command-5**, choose **Options > Save to**, then select that same directory
as Re-Capture's **Watched folder**. Selecting a watched folder changes only
Re-Capture; it does not change the macOS save location.

**Refresh macOS Defaults** replaces unapplied edits but preserves the approved
watched folder. Sandbox preference reads may not reflect the actual global
settings, so the native Screenshot UI is authoritative. Direct preference
editing is disabled when the sandbox is enabled or its status is unknown.
In confirmed non-sandboxed builds, edits remain separate from applied values
until **Apply to macOS** succeeds; synchronization failures are reported.

### Release Note

Version 1.1.1 adds persistent processing history and safer transfers. The first
automatic scan of each newly selected screenshot folder records its existing
files without changing them. Use **Rename/Convert Existing Screenshots** to
process that initial inventory explicitly. After that baseline, new or changed
screenshots, including those created while paused or while the app was closed,
are processed on the next scan. Copy mode does not copy the same version again
after restarting; explicit bulk processing can process it again.

Pause cancels pending automatic work and stops before the next file. An already
started file transaction may finish safely. Bulk processing is an explicit action
and can be used while automatic processing is paused. Incomplete or changing
files are retained, with bounded retries and a visible deferred status.

If saving succeeds but deleting the original fails, the output is recorded and
the original is retained. A later scan retries deletion instead of creating a
duplicate. Failures to read, write, or maintain processing history are shown in
the status text; unreadable or corrupt history stops processing rather than
silently treating all files as new.

After an upgrade, reselect a folder only if Re-Capture requests it. Output images
stay in your selected folder; recovery staging files are temporarily written
there too.

## Filename Templates

Date portions use `DateFormatter` syntax. Outside quoted date-format literals,
the following tokens are expanded directly (adjacent tokens are supported):

- `{app}`: frontmost app name at processing time
- `{title}`: frontmost window title at processing time, when available
- `{sequence}`: processing sequence padded to at least four digits, retained across restarts

For example:

```text
yyyyMMdd-HHmmss-{app}-{sequence}
```

Use single quotes for literals, for example `'Screenshot' yyyyMMdd-{sequence}`.
A quoted token such as `'{app}'` is literal text. Empty names, names starting
with a dot, invalid tokens/quotes, and overlong filenames are rejected without
moving the source. The base name is limited to 250 UTF-8 bytes; the complete
filename including extension and any collision suffix must fit 255 bytes.

## Formats

Re-Capture treats macOS screenshot output and Re-Capture conversion output as two
separate settings.

Native macOS screenshot source formats:

- PNG
- JPEG
- PDF
- TIFF

Re-Capture conversion target formats:

- HEIC
- WebP
- AVIF
- BMP
- PSD

If a conversion target is unavailable on the current macOS ImageIO stack,
Re-Capture keeps processing safe by saving the screenshot in its original source
format and reporting the fallback in the status text.
Multi-page PDF/TIFF files also retain their original format rather than silently
discarding additional pages during conversion.

WebP encoding is provided by the bundled `SDWebImageWebPCoder` / `libwebp`
Swift Package dependency so App Store builds do not depend on Homebrew or other
external command-line tools.

## Build

Generate the Xcode project:

```sh
xcodegen generate
```

Build from the command line:

```sh
xcodebuild -project Recapture.xcodeproj -scheme Recapture -configuration Debug build
```

Run the regression suite:

```sh
xcodebuild -project Recapture.xcodeproj -scheme Recapture -destination 'platform=macOS' test
```

The test scheme sets `RECAPTURE_TESTING=1`, preventing the host app from starting
its normal watcher. Tests use isolated folders, preferences, and processing
history; they do not modify the user's macOS screenshot settings.

For App Store distribution, open `Recapture.xcodeproj` in Xcode, configure the
signing team for `st.rio.recapture`, archive, and upload through App Store
Connect.

## Privacy

Re-Capture processes screenshots locally and does not send screenshot contents,
filenames, preferences, or folder paths to external services.

- [Privacy Policy](PRIVACY.md)
- [プライバシーポリシー](PRIVACY.ja.md)

## License

MIT License. See [LICENSE](LICENSE).
