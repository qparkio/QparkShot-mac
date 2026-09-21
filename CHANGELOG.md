# Changelog

## 1.2.0 — 2026-09-21

- Refreshed the native library, capture review, editor and settings interface; wider initial windows and settings positioned relative to the main window.
- Added an About section with version, build, copyright and website; replaced the app icon with the in-app camera mark.
- Unified appearance handling for light, dark and system themes.
- Protected editor loading against stale results when switching images; crop and annotations share undo/redo history.
- Aligned annotation preview and export rendering, corrected blur coordinates, and improved missing-image recovery.
- Processed the entire OCR backlog sequentially, including libraries larger than 40 files; separated errors from successful empty text and added bounded retries and stale-result protection.
- Reconciled gallery selection with filters and search, improved bookmarked-folder access, and retained compatible settings and index data.
- Rechecked active images and favorites immediately before cleanup, serialized cleanup passes, and kept saved-file removal in the Trash.
- Improved capture coordinate conversion, cancellation, export feedback and unsaved-work handling.
- Isolated test settings, gallery index and image folders; expanded regression and UI scenarios.

### Validation limits

The unit suite and universal macOS Release build are checked for this release. Earlier UI checks covered localized settings, review, library and editor layouts, but the final full UI gate remains incomplete: the crop undo/redo and shortcut scenarios require another manual or automated pass. The latest appearance and window-position changes have not been verified in a running UI. Real capture permissions, multiple physical monitors, older supported macOS versions and external-volume recovery have not been fully verified.
