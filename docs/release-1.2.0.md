# Re-Capture 1.2.0 (7) — release preparation

Status observed 2026-09-21 (JST). This is an update of the macOS app
`st.rio.recapture`, App Store ID `6786072173`. Minimum macOS remains 26.0.

## Completed preparation

- Reorganized settings into General, Folders and Output; clarified Move/Copy,
  added filename examples and bulk confirmation, improved accessible labels.
- Version 1.2.0 / build 7 in `project.yml` and the generated Xcode project.
- 74 regression tests passed, 0 failures. Localization lint and diff checks pass.
- Signed universal arm64/x86_64 archive created with Xcode 27.0 (27A266a).
  `codesign --verify --deep --strict` passed. Archive entitlement scope remains
  App Sandbox, app-scoped bookmarks and user-selected read/write files.
- App Store Connect previously released 1.1.1 (6) is currently
  `配信準備完了`. A 1.2.0 draft is saved as `提出準備中`.
- English and Japanese What's New and updated review instructions saved.
  Existing automatic release after approval setting retained.
- App Privacy still declares no data collected and links to the same policy
  exposed in the app menu. Utilities category, 4+ rating and standard Apple EULA
  remain. ASC reports 148 available regions and 27 unavailable EU regions.

## Upload gate

Archive: `build/AppStore/Re-Capture-1.2.0-7.xcarchive`.
Archive log: `build/AppStore/archive-1.2.0-7.log`.
Test log: `build/AppStore/test-1.2.0-7.log`.
Local inspection: `build/AppStore/preflight-1.2.0-7.json`.

Export/upload failed with `Failed to Use Accounts`: Xcode requires App Store
Connect access for the configured team. Xcode Apple Accounts currently has no
account; its sign-in page was opened for the developer. No build 7 upload,
processing, selection, review submission or publication is established.

After signing into the authorized developer account, retry:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -exportArchive \
  -archivePath build/AppStore/Re-Capture-1.2.0-7.xcarchive \
  -exportOptionsPlist build/AppStore/ExportOptions.plist \
  -exportPath build/AppStore/Upload-1.2.0-7 \
  -allowProvisioningUpdates
```

Then verify processing and select 1.2.0 (7) in the draft. Recheck the selected
binary and any export-compliance prompts before submission.

## App Store Review Preflight

Guidelines checked: live Apple page retrieved 2026-09-21; displayed update
June 8, 2026. Readiness: **NOT READY**.

Counts (rows below): **BLOCKER 2 / WARNING 1 / MANUAL 3 / PASS 5 /
NOT APPLICABLE 5**. This assessment does not guarantee review approval.

| ID | Result | Finding and next verification |
| --- | --- | --- |
| R1 | BLOCKER | Build 7 has not uploaded or been selected because Xcode has no account. Complete authentication, upload, processing and build selection. [2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness) |
| R2 | BLOCKER | Draft screenshots inherited the previous settings UI. Replace with current English/Japanese screenshots and inspect the saved store previews. Diagnostic capture is 1229 × 768 with a system capture indicator, unsuitable for delivery. Use a supported 16:10 Mac size such as 1280 × 800. [2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) |
| R3 | WARNING | Review phone/email remain blank. Existing values were preserved; confirm review contact completeness before submission. No contact data was invented. [1.5](https://developer.apple.com/app-store/review/guidelines/#developer-information) |
| R4 | MANUAL | Native Settings scene shortcuts, complete keyboard/VoiceOver interaction, macOS 26 and a sandboxed archive smoke test remain outstanding. Inspect current GUI evidence and exercise chosen folders plus disposable screenshot processing before review. [2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness) |
| R5 | MANUAL | ASC declares no third-party content; technical inspection cannot establish all branding/content rights or complete legal license compliance. No new content or dependency introduced. [5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) |
| R6 | MANUAL | ASC shows trader declaration and 27 EU regions unavailable. Regional verification/agreements and build-specific export compliance are not established; retain existing availability until reviewed. [5 Legal](https://developer.apple.com/app-store/review/guidelines/#legal), [DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) |
| P1 | PASS | 74 automated tests pass; build/archive identity and signature verified locally. |
| P2 | PASS | Selected-folder sandbox/bookmark scope retained; no new permission or processing/storage code. |
| P3 | PASS | Saved localized release notes and actionable review setup steps; no account/backend needed by app. |
| P4 | PASS | Privacy menu/ASC URL agree; app and bundled SDWebImage manifests disclose no collection/tracking. Required-reason declarations are present. |
| P5 | PASS | Native utility functionality and scoped GUI improvements inspected; accessible control names present in live tree. |
| N1 | NOT APPLICABLE | No UGC service, social posting, Kids category, medical/physical-harm feature. |
| N2 | NOT APPLICABLE | No IAP, subscription, external purchase, advertising or financial service code. |
| N3 | NOT APPLICABLE | No login/account service, account deletion flow, remote backend or external hardware requirement. |
| N4 | NOT APPLICABLE | No extension, mini-app host, downloadable code, Game Center or alternate-icon feature in this update. |
| N5 | NOT APPLICABLE | No gambling, VPN, MDM or regulated service. |

| Guideline family | Coverage | Evidence |
| --- | --- | --- |
| Safety | PASS / WARNING / N/A | Local utility, scoped file access; support path present; R3, N1. |
| Performance | BLOCKER / MANUAL / PASS | R1–R2, R4; completed tests/archive; unchanged self-contained sandbox behavior. |
| Business | N/A | N2; no new monetization; existing pricing unchanged. |
| Design | PASS / MANUAL / N/A | Native settings and utility function; R4–R5, N4. |
| Legal | PASS / MANUAL / N/A | Privacy agreement across source/bundle/store; R5–R6, N5. |

Evidence: `Recapture/SettingsView.swift`, `Recapture/RecaptureApp.swift`,
`Recapture/Recapture.entitlements`, `Recapture/PrivacyInfo.xcprivacy`,
`PRIVACY.md`, archived bundle and its SDWebImage privacy manifest; App Store
Connect version/localizations, review information, App Information, App Privacy,
Pricing and Availability. UI evidence/limitations are in
[the GUI review](gui-hig-review-2026-09-21.md).

The reviewed archive is not yet a selected App Store Connect build.
**No submission action was performed.**

## Saved What's New — English

Redesigned settings make Re-Capture easier to configure.
- Find options in General, Folders, and Re-Capture Output panes.
- Preview filename rules and see clearer validation messages.
- Read how Move and Copy handle original files before processing.
- Confirm bulk processing before changing existing screenshots.
- Improved folder selection, keyboard shortcuts, and accessibility labels.

Your existing screenshot processing and selected-folder access are preserved.

## Saved What's New — Japanese

設定画面を刷新し、Re-Captureをより分かりやすく設定できるようになりました。
・設定を「一般」「フォルダ」「Re-Captureの出力」に整理
・ファイル名ルールのプレビューと入力エラー表示を追加・改善
・移動／コピー時の元ファイルの扱いを明示
・既存スクリーンショットの一括処理前に確認画面を表示
・フォルダ選択、キーボードショートカット、読み上げ用ラベルを改善

既存のスクリーンショット処理と、選択したフォルダへのアクセス設定は引き継がれます。
