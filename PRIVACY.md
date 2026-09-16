# Privacy Policy

Effective date: September 16, 2026

Re-Capture is a macOS utility that watches a screenshot folder selected by the
user, renames screenshots, optionally converts their image format, and moves
or copies them to a destination folder selected by the user with the standard
macOS folder picker.

## Data Collection

Re-Capture does not collect, transmit, sell, or share personal information.

Re-Capture processes screenshot files locally on the user's Mac. Screenshot
contents, filenames, folder paths, preferences, and processing logs are not sent
to the developer or to any external service by the app.

## Local Data

Re-Capture stores preferences locally using macOS user defaults. These
preferences may include the filename template, output format, transfer mode,
and security-scoped bookmarks for folders selected by the user.

Re-Capture also keeps a local processing journal in its Application Support
directory (inside its sandbox container in sandboxed builds). It records input
and output paths, file identifiers, sizes, modification timestamps, processing
sequence numbers, the initial folder inventory, and transfer/recovery state.
The journal contains no screenshot image data and is not transmitted. Records
are retained until the app's local data is removed, so restarting or recovering
an interrupted transfer does not duplicate output. Removing this history resets
the initial inventory and duplicate protection.

Screenshot output files are not stored in Re-Capture's app sandbox container.
Re-Capture saves processed screenshots only after the user selects an output
folder, and saves them to that selected folder.

## File Access

Re-Capture accesses screenshot files only in folders selected by the user.
Access is used to monitor, rename, convert, move, copy, and
open screenshots in Finder. If a watched or output folder has not been selected,
Re-Capture does not save processed screenshot files.

## Network Access

Re-Capture does not require network access for its core functionality.

## Contact

For questions about this privacy policy, contact the project maintainer through
the public GitHub repository:
https://github.com/rioriost/Re-Capture
