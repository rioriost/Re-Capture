# Re-Capture

Re-Capture is a lightweight macOS menu bar app for managing native macOS
screenshots.

It watches the screenshot directory configured by `com.apple.screencapture`
with FSEvents, then safely moves or copies new screenshots to a destination
folder using a configurable filename template and optional image conversion.

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later
- XcodeGen

## Current Features

- Uses the native macOS screenshot workflow
- Watches the configured screenshot folder with FSEvents
- Moves or copies screenshots to a destination folder
- Configurable filename template, for example `yyyyMMdd-HHmmss`
- Best-effort `{app}`, `{title}`, and `{sequence}` template tokens
- Source screenshot formats: PNG, JPEG, PDF, and TIFF
- Optional conversion targets: HEIC, WebP, AVIF, BMP, and PSD when the system
  ImageIO stack supports the target format
- GUI for editing still-image file output defaults from `com.apple.screencapture`
  including location, filename prefix, source format, date suffix, window shadow,
  floating thumbnail, and mouse pointer capture
- Bulk rename/convert for existing screenshots
- Login item toggle
- Open destination folder in Finder

## Filename Templates

The template is interpreted as a `DateFormatter` date format first. After date
formatting, these tokens are replaced:

- `{app}`: frontmost app name at processing time
- `{title}`: frontmost window title at processing time, when available
- `{sequence}`: four-digit processing sequence

For example:

```text
yyyyMMdd-HHmmss-{app}-{sequence}
```

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
