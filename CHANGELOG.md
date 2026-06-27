# CHANGELOG

## UNRELEASED

### Added
* Added output-template support for Pipeline runs. Shift-Return in the Pipeline menu and External Trigger output overrides now run saved or inline pipelines from a templated working copy, preserving saved pipeline optimize-first and hide-result settings while leaving the original input untouched.

---
## [v1.1.0](https://github.com/ognistik/alfred-clop/releases/tag/v1.1.0) - 2026/06/25
### Changed
* Tightened the manual update-check hint and made its Return shortcut consistent with other Configuration affordances.
* Shortened output-template guidance by moving errors and output previews into titles and reserving subtitles for concise examples and keyboard actions.
* Updated Pipeline support for Clop 3.2 by recognizing the new `fork` step, using Clop's pipeline result-visibility flags, and clarifying how inline `hide`, saved pipeline `hide`, and the workflow Floating Result setting interact.
* Added autocomplete hints for strong inline Pipeline step prefixes, including chained steps, while keeping saved pipeline matches and typo guidance distinct.

### Fixed
* Kept Configuration open after applying output-template and deletion changes with Return, while documenting Command-Return as the apply-and-close shortcut in the output-template editor.

---
## [v1.0.1](https://github.com/ognistik/alfred-clop/releases/tag/v1.0.1) - 2026/06/20
### Added
* Added image and video pixel dimensions to Large Type input details, with abbreviated home paths and a single shared-folder heading for same-folder batches.

### Changed
* Made automatic Clipboard History recovery skip ambiguous web links, while preserving clearly supported media URLs and permissive handling for a standalone URL on the current clipboard.
* Gave the main-menu update notice a distinctive high-contrast icon so available workflow releases are easier to spot.
* Kept cached PDF crop targets synchronized when the installed Clop app or CLI executable changes.
* Added a Command-Return shortcut to reveal the clipboard image cache folder from Configuration.

---
## [v1.0.0](https://github.com/ognistik/alfred-clop/releases/tag/v1.0.0) - 2026/06/19
### Released
* First stable public release of Clop for Alfred.
* Promoted the extensively tested v0.2.0 feature set to 1.0 without functional changes.

### Feedback and documentation
* Please report bugs through [GitHub Issues](https://github.com/ognistik/alfred-clop/issues). Type `:` and choose `Diagnostics` in the workflow to copy a privacy-conscious support report for your issue.

---
## [v0.2.0](https://github.com/ognistik/alfred-clop/releases/tag/v0.2.0) - 2026/06/19
### Added
* Added weekly stable-release checks through GitHub Releases.
* Added a `Notify on Updates` workflow setting, one-time native notifications for each new version, and an actionable update item in the main menu.
* Added a manual `Check for Updates` command to Configuration.

---
## [v0.1.0](https://github.com/ognistik/alfred-clop/releases/tag/v0.1.0) - 2026/06/19
### Added
* Initial public release.
