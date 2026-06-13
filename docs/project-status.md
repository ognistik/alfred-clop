# Alfred Clop Project Status

Last updated: June 13, 2026

This document records the current implementation checkpoint. Keep
`project-plan.md` as the longer-term product and architecture plan; update this
file whenever a task materially changes what works or what should happen next.

## Current checkpoint

Milestones 1 and 2 are substantially complete. Milestone 3 includes
parameter-free execution, a guided dynamic parameter step for crop and resize,
user-defined Crop / Resize action presets, explicit preset-location migration,
and the unified input and routing foundation planned for Milestone 6.

The public automation surface is now one typed `clop` request with independent
input and route values. Files, folders, HTTP/HTTPS URLs, clipboard content,
Finder selection, Universal Actions, and six configurable Hotkeys all
normalize through `InputCollector`.

The routing and feedback hardening checkpoint is complete: public execute
requests bypass Alfred's interactive Script Filter, normalized menu reruns
clear stale public-request state, and quiet feedback honors the independent
completion and error notification settings.

Raw image clipboard materialization is also complete. Clipboard PNG or TIFF
data now becomes a private cached image input when no native files or usable
path/URL text are available.

The shared settings and global execution-policy foundation is complete.
Portable workflow-owned settings and action presets now share `settings.json`,
original preservation uses validated Clop output templates, and Configuration
owns migration, output-template reset, global preset reset confirmation, and
clipboard-image cache cleanup.

## Completed

### Swift foundation

- Swift Package and executable under `src/`
- Codable Alfred Script Filter models
- Typed domain models for actions and operation requests
- Deterministic fuzzy action search
- Clop CLI discovery and diagnostics
- Build and test scripts

### Inputs and action menu

- One shared Alfred Script Filter for every input source
- Universal Action support for one or multiple selected files
- Clipboard support using `NSPasteboard`
- Clipboard parsing for native file URLs, `file://` URLs, newline-separated
  paths, and a single path
- External Trigger `clop` for typed clipboard, Finder-selection, and explicit
  input requests
- Path normalization, symlink resolution, validation, and deduplication
- Media detection for images, video, audio, and PDFs
- Context-aware action capability intersection for mixed inputs
- One Optimize result in the main menu; aggressive optimization remains
  available to typed execution and Hotkeys pending the planned Command-Return
  modifier
- Source-aware subtitles for selected, copied, and passed files
- Visible Alfred errors for missing, unsupported, and invalid inputs
- Injectable clipboard abstraction with no real clipboard dependency in tests
- Input context preserved across Script Filter reruns

### Unified input and routing

- Public `clop` request with separate typed `input` and `route` models
- Clipboard, explicit-item, and injectable Finder-selection acquisition
- Universal Action and Alfred-selected text extraction for supported URLs,
  quoted or backtick-wrapped paths with spaces, unquoted absolute paths,
  `~/...` paths, and `file://` URLs
- Native clipboard files take precedence over clipboard text
- Raw PNG and TIFF clipboard data materialized only after native files and
  usable path/URL text are unavailable
- Content-addressed clipboard image files stored in Alfred's workflow cache,
  with a private temporary fallback, restricted permissions, stable reuse
  across Script Filter reruns, and opportunistic expiry
- Clipboard image materialization failures retain the existing no-input
  feedback without requiring Alfred Clipboard History or its private database
- Exact structured explicit items remain distinct from prose extraction
- Local files, folders, and remote URLs classified through `InputCollector`
- HTTP/HTTPS query strings and fragments preserved
- Credential-bearing and unsupported-scheme URLs rejected
- Folder inspection controlled by `recursiveFolders`
- Fixed 500-visible-entry budget per input folder, counting inspected files
  and traversed directories
- Hidden entries, packages, and symlinks excluded from folder scans
- Empty, unsupported-only, unreadable, and budget-limited folders handled
  distinctly
- Clear media capabilities intersected across files, folder contents, and
  recognizable URL extensions
- Ambiguous URLs and budget-limited folders retain documented broad-input
  actions with concise media requirements
- Typed routes open the main menu, a clean implemented parameter menu, or
  quiet execution
- Omitted public request versions use the installed workflow's current
  contract; explicit version 1 pins compatibility, while unsupported and
  malformed explicit versions remain errors
- Folder subtitles identify folders and show exact processable item counts only
  when bounded inspection completes
- Non-recursive folders with supported media only in ordinary subfolders
  offer a Return action that opens Alfred's workflow configuration for manual
  adjustment
- Menu routes ignore accidental parameter objects instead of inferring an
  execution route
- Quiet execution inherits current workflow `copyResult` and
  `recursiveFolders` settings
- Empty Finder selections stop visibly without clipboard fallback
- Normalized source and ambiguity metadata survive Script Filter reruns

### Workflow

- Universal Action wired through an Args and Vars object
- Clipboard keyword `clop`
- Public External Trigger `clop` accepts typed requests with optional explicit
  compatibility versions
- Human-friendly External Trigger shorthand for bare Finder, clipboard, path,
  folder, and URL input; workflow action menus; and complete supported actions
- Required blank-line boundary between shorthand directives and exact input
- Workflow-facing action names and American-English `Optimize` spelling
- Typed JSON retained as an advanced compatibility form that decodes into the
  same `ClopRequest` model
- Public menu requests enter the internal `mainMenu` route, while execute
  requests bypass the Script Filter and run headlessly
- Public menu requests pass their raw public request through a workflow
  variable and open `mainMenu` with an empty query, keeping request data out of
  Alfred's bar
- Internal `mainMenu` trigger remains reserved for Script Filter navigation
- Shared normalized input state stored in `alfred_clop_input_json`
- Immediate actions handed to a quiet Run Script execution action
- Clop UI used for successful progress/results, with notifications for errors
- Completion and error notification settings independently control quiet and
  headless feedback without hiding interactive Script Filter errors
- Release binary built at `workflow/alfred-clop`
- User configuration fields for `settingsPath`, preservation, optimization
  default, Clop UI, notifications, copying, recursion, and cache retention
- `copyResult` is applied to supported app-backed commands
- `recursiveFolders` controls both folder inspection and supported Clop
  command arguments
- Universal Action accepts files, URLs, text, and multiple items
- Six configurable Hotkeys: menu, optimize, and aggressive optimize for
  clipboard or Alfred-selected input

### Parameter-free execution

- Typed Clop command builder using `ClopCLIDiscovery`
- `execute` mode decoding `OperationRequest` JSON
- Injectable process-running abstraction
- Standard and aggressive optimization with JSON output
- PDF uncrop and metadata stripping with text-only process results
- Argument-array invocation preserving spaces and multiple-file payloads
- Visible Alfred feedback for invalid and parameter-step requests, missing
  Clop, launch failures, invalid JSON results, and nonzero exits
- Per-file JSON result inspection for app-backed commands, including visible
  notifications when Clop exits successfully but skips some or all inputs
- Known false-negative HTTPS failures for submitted nested Substack CDN URLs
  are ignored without suppressing unrelated partial failures
- Focused fake-based tests that never launch the real Clop CLI

### Crop and resize

- Explicit typed menu state for the top-level action menu and crop parameter
  menu
- Typed Alfred routing that sends `ParameterStepRequest` values back to the
  shared Script Filter through its `mainMenu` inbound configuration
- Immediate `OperationRequest` values continue to the existing quiet execution
  action
- Empty crop queries show one non-executable instructional item instead of
  workflow-authored presets
- Typed queries remove the instructional item immediately, filter saved
  presets, and select matching presets before offering a free-form action
- Partial preset queries remain useful without showing premature validation
  errors; exact normalized preset matches produce one saved interpreted action
- Typed values without matching presets produce exactly one interpreted result
  or one visible validation error
- Free-form validation for `1200x630`, `16:9`, `1920`, `w128`, `h720`,
  `128x0`, and `0x720`
- `wNUMBER` and `hNUMBER` normalize to Clop's native `NUMBERx0` and `0xNUMBER`
  forms
- Result subtitles explain exact dimensions, aspect ratio, long edge, fixed
  width, or fixed height behavior before execution
- Bare positive integers encoded as long-edge resize requests
- Invalid, malformed, negative, decimal, and zero-only values rejected visibly
- Crop execution through `clop crop --size VALUE --json --no-progress`
- Conditional `--long-edge`; menu-generated requests keep `smartCrop` disabled
- Crop and resize notifications distinguish complete success, partial batches,
  and all-skipped batches such as requests that would enlarge source images
- Normalized inputs and selected, copied, or passed context preserved across
  inbound transitions and Script Filter query reruns

### Crop and resize presets

- Normalized typed crop presets retained inside versioned `settings.json`
- Atomic persistence in `alfred_workflow_data` by default or
  `<settingsPath>/settings.json` when configured
- No preset inputs, custom names, or execution-setting overrides
- Friendly normalization for equivalent forms such as `w128` and `128x0`
- Fixed grammar instruction followed by saved presets with stable item UIDs
- Saved presets use deterministic natural sorting by their friendly display
  values because Alfred learning is disabled for this submenu
- Free-form typed values remain available alongside saved presets
- Matching typed and saved values combine into one result marked as saved
- Control-Return saves new typed values immediately
- Control-Return on a saved preset opens a typed removal confirmation step
- Confirmed removal returns to Crop / Resize with inputs and source context
  preserved
- Malformed and unsupported preset files are rejected visibly without being
  overwritten
- Configured paths and input filenames containing spaces are covered by tests

### Preset location migration

- Versioned workflow-owned location metadata stored under
  `alfred_workflow_data`
- Changed settings locations detected without silently moving, merging,
  overwriting, or deleting portable data
- Context-specific Move existing settings action appears first in the main
  action menu with concise, path-free wording
- Pending settings migration remains available when there are no current files
  to process, alongside the relevant non-executable input message
- New preset saves are blocked while a settings move or two-location conflict
  is unresolved, preventing accidental creation of a second settings file
- A blocked preset save offers the move inline; Return performs it directly,
  saves the pending preset, and restores Crop / Resize
- Separate typed confirmation and execution states
- Atomic destination write followed by destination reload and validation
  before source deletion
- Default-to-custom and custom-to-default moves supported
- Successful moves return to the main action menu with inputs and selected,
  copied, or passed context preserved
- Both-files conflicts, missing sources, malformed or unsupported sources, and
  malformed or unsupported metadata produce visible non-destructive feedback
- No accumulating migration backup copies
- Paths containing spaces and injected write/validation failures covered by
  focused tests

### Shared settings and execution policy

- Versioned `settings.json` stores action presets and the active output
  template together
- Default storage under `alfred_workflow_data`; optional `settingsPath`
  selects a custom folder
- Explicit, non-destructive migration from `presets.json`, `presetsPath`,
  changed `settingsPath` locations, and legacy location metadata
- Built-in preservation template `%P/%f-clop`
- Template validation rejects empty values and unsupported tokens
- Preflight rejects duplicate planned outputs, existing-file collisions,
  source-path collisions, and inputs that cannot be safely planned
- Preservation uses Clop's validated `--output` template only; no
  workflow-managed backups
- Static settings for Preserve Original, Standard or Aggressive default,
  Clop UI, completion notifications, error notifications, copy result,
  recursion, and 1-15 day clipboard-image retention
- Automatic `--skip-errors` for implemented app-backed batch commands that
  support it, while structured partial failures remain visible
- Independent completion and error notification policy for interactive,
  Hotkey, and headless execution
- Raw clipboard-image expiry follows the configured retention period
- Discoverable Configuration action remains available without processable
  input
- Guided output-template entry includes validation and an example preview
- Pending migration appears in Configuration and inline blocked preset saves
  still move directly before resuming
- `Reset output template` restores `%P/%f-clop` without changing presets or
  Alfred preferences
- Command-Return on reset opens a separate global preset-removal confirmation
  with the preset count
- Conditional clipboard-image cleanup reports file count and space usage,
  requires confirmation, and removes only workflow-owned cache files
- Return uses configured aggressive and preservation defaults
- Command-Return and Shift-Return invert those defaults in fully resolved
  operation requests
- Crop-capable values expose Smart Crop through Option combinations; resize-only
  forms omit Smart Crop modifiers
- Pipeline delivery remains owned by Clop; no workflow recipe system or
  pipeline output override was added

Alfred was verified directly after implementation. Script Filter knowledge
sorting is response-wide: after a UID result is learned, Alfred can promote it
above a no-UID instructional row. Alfred does not support pinning one result
while learning the relative order of other results in the same response.
Crop / Resize therefore returns `skipknowledge: true` as the smallest reliable
fallback that keeps the grammar instruction first. Stable preset UIDs remain
in the JSON, but Alfred learning is disabled for this submenu until Alfred
provides per-item knowledge control or the product adopts a different menu
structure.

### CLI research

- CLI reference refreshed against the official Clop 3.0.0 release
- Media-specific optimization subcommands documented
- Image, video, and audio conversion formats documented
- Native pipeline commands and PDF `--extend` behavior documented
- Product plan now targets complete supported CLI coverage across typed
  optimization, conversion, PDF controls, folders, URLs, shared switches, and
  pipeline management
- Main-menu conversion discovery is media-specific for homogeneous image,
  video, and audio input; ambiguous broad input shows separate honest,
  non-executable conversion routes until their parameter menus are built
- Disposable-file output probes verified in-place behavior, automatic
  extension appending, directory-template requirements, silent collision
  overwrites, empty-output failure, literal unknown tokens, multi-file
  expansion, and app-backed conversion extensions

## Not implemented

- Downscale, conversion, and PDF-crop parameter menus and parsing
- Dynamic PDF device and paper-size menus
- Portable settings export, backup, restore, and import
- Workflow icons, packaging, and release automation

### Implemented unified input design

- One public External Trigger identifier: `clop`; no compatibility alias for
  the unreleased `paths` trigger
- Internal `mainMenu` External Trigger retained only for Script Filter
  navigation
- Line-based shorthand is the primary public interface; typed JSON remains the
  advanced compatibility form with independent `input` and `route` values
- Omitted JSON `version` tracks the installed workflow's current contract,
  while explicit version 1 remains a pinned compatibility target
- Input sources: clipboard, explicit items, and an injectable Finder-selection
  bridge for External Trigger requests
- Explicit items may be local files, folders, or `http`/`https` URLs
- Universal Actions and Hotkeys pass files, URLs, or text as explicit input
- Native clipboard files take precedence over text without merging pasteboard
  representations
- Raw PNG or TIFF pasteboard data is a final clipboard fallback and normalizes
  into the same local-file pipeline without querying Alfred's clipboard
  database
- Prose extraction for URLs, quoted or backtick-wrapped paths containing
  spaces, and unquoted absolute or `~/...` paths without spaces
- Credential-bearing and unsupported-scheme URLs rejected; query strings and
  fragments preserved
- `menu` route opens either the main menu or a clean action parameter menu;
  accidental action values are ignored
- `execute` route requires a complete typed action and inherits workflow
  execution settings
- Empty Finder selection notifies and stops without clipboard fallback
- `recursiveFolders` controls both folder inspection depth and Clop's
  `--recursive` argument
- Folder inspection budget fixed initially at 500 visible entries per input
  folder, counting files and traversed directories
- Hidden entries, packages, and directory symlinks excluded from folder scans
- Empty, unsupported-only, and unreadable folders produce specific
  non-actionable feedback
- Budget-limited folders and unclear URLs remain ambiguous; documented
  broad-input actions stay available with concise type requirements only where
  needed
- Six configurable Hotkeys planned: menu, optimize, and aggressive optimize
  for clipboard or Alfred-selected input

## Next recommended task

Implement the Downscale parameter menu and action presets:

1. Add guided parsing for factors and percentages such as `0.5` and `75%`.
2. Normalize percentages to typed factors and validate the supported range
   without permitting enlargement.
3. Add per-action preset save and confirmed removal using the shared
   `settings.json`.
4. Apply the shared aggressive, preservation, Clop UI, copy, recursion,
   notification, output preflight, and `--skip-errors` policies.
5. Preserve every existing input route, normalized state, and modifier meaning.

## Verification baseline

At this checkpoint:

- `./scripts/test.sh` passes 170 tests.
- `./scripts/build.sh` produces `workflow/alfred-clop`.
- `plutil -lint workflow/info.plist` passes.
- The built workflow binary is currently Apple Silicon (`arm64`).
