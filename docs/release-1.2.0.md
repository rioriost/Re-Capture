# Re-Capture 1.2.0 (8) — release preparation

Status observed 2026-09-21 (JST). This is an update of the macOS app
`st.rio.recapture`, App Store ID `6786072173`. Minimum macOS remains 26.0.

## Completed preparation

- Reorganized settings into General, Folders and Output; clarified Move/Copy,
  added filename examples and bulk confirmation, improved accessible labels.
- Version 1.2.0 / build 8 in `project.yml` and the generated Xcode project.
- 74 regression tests passed again for build 8, 0 failures. Localization lint and diff checks pass.
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

## Final build 8 and store assets

Build 8 adds bundled SDWebImage, SDWebImageWebPCoder and libwebp license/copyright
notices, plus the libwebp patent grant. The resource was compared byte-for-byte
with the archived copy. It also declares `ITSAppUsesNonExemptEncryption=false`,
matching the build 7 questionnaire. No GUI or processing code changed.

- Code/assets commit: `f56c677`.
- Archive: `build/AppStore/Re-Capture-1.2.0-8.xcarchive`.
- Archive/signature inspection: `build/AppStore/preflight-1.2.0-8.json`.
- Tests: `build/AppStore/test-1.2.0-8.log`, 74 passed.
- Upload: `build/AppStore/upload-1.2.0-8.log`, `EXPORT SUCCEEDED` at 12:34 JST.
- ASC build ID: `08577826-b012-494b-b5fc-f37e85045f86`; processing `終了`,
  TestFlight `提出準備完了`, with no missing-encryption warning.
- At 12:39 JST, build **1.2.0 (8)** replaced build 7 in the release draft and
  was saved. The version page shows the build 8 link and disabled Save button;
  status remains `提出準備中`. No review submission was performed.
- English/Japanese store screenshots replaced with two original 1280 × 800 JPEGs
  per locale, no alpha. Saved store previews were visually inspected.
  [Delivered files and provenance](app-store/1.2.0/README.md).

## Earlier build 7 upload evidence

Archive: `build/AppStore/Re-Capture-1.2.0-7.xcarchive`.
Archive log: `build/AppStore/archive-1.2.0-7.log`.
Test log: `build/AppStore/test-1.2.0-7.log`.
Local inspection: `build/AppStore/preflight-1.2.0-7.json`.

The initial export/upload attempts failed with `Failed to Use Accounts`.
After the developer signed into Xcode, the retry completed at 12:18 JST:
`Upload succeeded` and `EXPORT SUCCEEDED` in
`build/AppStore/upload-1.2.0-7-retry2.log` (exit 0).
App Store Connect independently shows version 1.2.0, build 7, uploaded at
Sep 21, 2026 12:18 PM, with upload ID `39d875e8-472b-4884-962e-7434c1270201`.
Processing was initially displayed as `処理中`, then changed to `終了`.
The build required its encryption questionnaire. Source/dependency inspection
found no implementation of proprietary or standard encryption algorithms;
`上記のアルゴリズムのどれでもない` was saved. TestFlight then displayed
`提出準備完了`. No testers were invited or notified.

At 12:22 JST, **1.2.0 (7) was selected and saved in the release draft**.
The saved page showed its build link, disabled Save button, and enabled Add for
Review button. This selection was superseded by build 8 at 12:39 JST.

Successful export/upload command (do not upload the same build again):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -exportArchive \
  -archivePath build/AppStore/Re-Capture-1.2.0-7.xcarchive \
  -exportOptionsPlist build/AppStore/ExportOptions.plist \
  -exportPath build/AppStore/Upload-1.2.0-7 \
  -allowProvisioningUpdates
```

Upload, processing completion and saved draft selection are independently
verified. No review submission or publication has been performed.

## App Store Review Preflight

Guidelines checked: live Apple page retrieved 2026-09-21; displayed update
June 8, 2026. Readiness: **READY WITH MANUAL CONFIRMATIONS**.

Counts (rows below): **BLOCKER 0 / WARNING 1 / MANUAL 3 / PASS 7 /
NOT APPLICABLE 5**. This assessment does not guarantee review approval.

| ID | Result | Finding and next verification |
| --- | --- | --- |
| R1 | PASS | Build 1.2.0 (8) uploaded, processing completed, encryption declaration accepted, and build selected/saved in the version draft at 12:39 JST. The selected build corresponds to the audited build 8 archive. |
| R2 | PASS | Two current screenshots per language saved in the draft and visually verified. Original window-scoped captures are 1280 × 800 JPEG with no alpha; no generated or retouched UI. [2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) |
| R3 | WARNING | Review phone/email remain blank. Existing values were preserved; confirm review contact completeness before submission. No contact data was invented. [1.5](https://developer.apple.com/app-store/review/guidelines/#developer-information) |
| R4 | MANUAL | Native Settings scene shortcuts, complete keyboard/VoiceOver interaction, macOS 26 and a sandboxed archive smoke test remain outstanding. Inspect current GUI evidence and exercise chosen folders plus disposable screenshot processing before review. [2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness) |
| R5 | MANUAL | ASC declares no third-party content; dependency license/copyright notices are now included and verified in build 8. Technical inspection cannot establish all branding/content rights; no new brand assets or dependency introduced. [5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) |
| R6 | MANUAL | ASC shows trader declaration and 27 EU regions unavailable. Regional verification/agreements remain unestablished; existing availability is retained. Build 8 explicitly declares no non-exempt encryption and ASC reports it ready. [5 Legal](https://developer.apple.com/app-store/review/guidelines/#legal), [DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) |
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
| Performance | MANUAL / PASS | R1–R2 resolved; R4 coverage limits remain; build 8 tests/archive pass. |
| Business | N/A | N2; no new monetization; existing pricing unchanged. |
| Design | PASS / MANUAL / N/A | Native settings and utility function; R4–R5, N4. |
| Legal | PASS / MANUAL / N/A | Privacy agreement across source/bundle/store; R5–R6, N5. |

Evidence: `Recapture/SettingsView.swift`, `Recapture/RecaptureApp.swift`,
`Recapture/Recapture.entitlements`, `Recapture/PrivacyInfo.xcprivacy`,
`PRIVACY.md`, archived bundle and its SDWebImage privacy manifest; App Store
Connect version/localizations, review information, App Information, App Privacy,
Pricing and Availability. UI evidence/limitations are in
[the GUI review](gui-hig-review-2026-09-21.md).

Build 8 was audited across all five guideline families against the latest source,
signed bundle, saved store metadata and new screenshots. The signed entitlements
remain sandbox, app-scoped bookmarks and user-selected read/write files. No new
protected-resource usage, tracking, networking or purchases were introduced.
The new resource and encryption declaration are the only functional distribution
changes after build 7. R3–R6 remain explicitly scoped manual/coverage limitations.
The temporary capture fixture was removed; committed tests are unchanged.

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
