# Alfred Clop Project Status

Last updated: June 12, 2026

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
clear stale public-request state, and quiet errors honor the `dnd` setting.

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
- Public menu requests enter the internal `mainMenu` route, while execute
  requests bypass the Script Filter and run headlessly
- Internal `mainMenu` trigger remains reserved for Script Filter navigation
- Shared normalized input state stored in `alfred_clop_input_json`
- Immediate actions handed to a quiet Run Script execution action
- Clop UI used for successful progress/results, with notifications for errors
- `dnd` suppresses quiet/headless error notifications without hiding
  interactive Script Filter errors
- Release binary built at `workflow/alfred-clop`
- User configuration fields for optional `presetsPath`, `copyResult`,
  `recursiveFolders`, and `dnd`
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

- Versioned `presets.json` schema storing normalized typed crop actions only
- Atomic persistence in `alfred_workflow_data` by default or
  `<presetsPath>/presets.json` when configured
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
- Changed `presetsPath` values detected without silently moving, merging,
  overwriting, or deleting preset data
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

## Not implemented

- Modifier behavior for aggressive processing and original preservation
- Downscale, conversion, and PDF-crop parameter menus and parsing
- Smart Crop menu choices
- Output and backup policies
- Dynamic PDF device and paper-size menus
- Configuration menu for preset and recipe management, explicit resets,
  storage migration, and portable settings export or backup
- Workflow icons, user configuration, packaging, and release automation
- Raw bitmap clipboard data materialization

### Implemented unified input design

- One public External Trigger identifier: `clop`; no compatibility alias for
  the unreleased `paths` trigger
- Internal `mainMenu` External Trigger retained only for Script Filter
  navigation
- JSON request with independent `input` and `route` values; omitted `version`
  tracks the installed workflow's current contract, while explicit version 1
  remains a pinned compatibility target
- Input sources: clipboard, explicit items, and an injectable Finder-selection
  bridge for External Trigger requests
- Explicit items may be local files, folders, or `http`/`https` URLs
- Universal Actions and Hotkeys pass files, URLs, or text as explicit input
- Native clipboard files take precedence over text without merging pasteboard
  representations
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

Implement capability-aware modifier behavior and finish the remaining global
execution-setting foundation:

1. Add Command-Return aggressive optimization requests to supported Optimize
   results and verify the modifier in Alfred.
2. Resolve the remaining shared execution settings into typed
   `ExecutionOptions` without adding output or backup policies prematurely.
3. Keep URL and folder capability validation shared between interactive and
   quiet execution.
4. Add focused modifier and configuration-inheritance tests.

Do not implement recipes, raw bitmap materialization, output policies, or new
action parameter menus in that slice.

## Verification baseline

At this checkpoint:

- `./scripts/test.sh` passes 145 tests.
- `./scripts/build.sh` produces `workflow/alfred-clop`.
- `plutil -lint workflow/info.plist` passes.
- The built workflow binary is currently Apple Silicon (`arm64`).
