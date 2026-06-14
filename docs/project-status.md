# Alfred Clop Project Status

Last updated: June 14, 2026

This document records the current implementation checkpoint. Keep
`project-plan.md` as the longer-term product and architecture plan; update this
file whenever a task materially changes what works or what should happen next.

## Current checkpoint

Milestones 1 and 2 are substantially complete. Milestone 3 includes
parameter-free execution, a guided dynamic parameter step for crop and resize,
user-defined Crop / Resize action presets, shared settings, and the unified
input and routing foundation planned for Milestone 6.

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
Workflow-owned settings and action presets now share `settings.json`,
original preservation uses validated Clop output templates, and Configuration
owns output-template reset, global preset reset confirmation, location moves,
and clipboard-image cache cleanup.

The revised settings-location behavior is complete. A valid configured
`settings.json` is authoritative, while an empty configured location may use
the previous output template read-only until the user explicitly moves the
settings or starts fresh.

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
- Configuration remains available when selected, copied, or passed input has
  no processable media, including unsupported-only folders
- Unsupported clipboard content uses generic, path-free feedback because the
  clipboard contents may be incidental or unexpected
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
- Customizable clipboard keyword, with `Clop` as its fallback keyword
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
- Clop UI is the sole successful processing feedback when enabled; background
  successes may use Completion notifications
- Completion notifications default on and also cover successful Configuration
  mutations; error notifications remain independent without hiding
  interactive Script Filter errors
- Release binary built at `workflow/alfred-clop`
- User configuration fields for `settingsPath`, preservation, optimization
  default, Clop UI, notifications, copying, recursion, keyword clipboard
  access, and cache retention
- Keyword clipboard access defaults on and can be disabled without affecting
  explicit clipboard Hotkeys or External Trigger requests; the disabled
  keyword result opens Alfred workflow configuration
- The menu-with-clipboard Hotkey uses an explicit clipboard route and bypasses
  the keyword-only clipboard preference
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

### Shared settings and execution policy

- Versioned `settings.json` stores action presets and the active output
  template together
- Default storage under `alfred_workflow_data`; optional `settingsPath`
  selects a custom folder
- Existing compatibility for `presets.json`, `presetsPath`, changed
  `settingsPath` locations, and legacy location metadata
- Explicit settings moves use atomic destination writes and validation before
  source deletion
- Built-in preservation template `%P/%f-clop`
- Template validation rejects empty values, unsupported tokens, `%e`, literal
  terminal extensions, folder-only values, and unpredictable relative paths
- Leading `~/` stays portable in `settings.json` and expands for preview,
  preflight, and execution
- Preflight rejects duplicate planned outputs, source-path collisions, and
  inputs that cannot be safely planned
- Existing output collisions resolve to the next available numeric suffix,
  such as `-clop-2` and `-clop-3`, without changing the stored template
- Preservation uses Clop's validated `--output` template only; no
  workflow-managed backups
- Static settings for Preserve Original, Standard or Aggressive default,
  Clop UI, completion notifications, error notifications, copy result,
  recursion, and 1-15 day clipboard-image retention
- Automatic `--skip-errors` for implemented app-backed batch commands that
  support it, while structured partial failures remain visible
- Successful processing notifications are suppressed when Clop UI is visible;
  background execution and Configuration mutations follow the default-on
  completion policy
- Raw clipboard-image expiry follows the configured retention period
- Discoverable Configuration action remains available without processable
  input
- Command-Return on the main Configuration item opens Alfred workflow settings
- The Output Template editor offers complete prefix and suffix choices for
  plain text, advanced entry for template syntax, immediate validation, and
  raw-template plus example-path subtitles
- `%P` examples use `Original folder`; home-relative and absolute destinations
  remain literal
- The empty Output Template editor contains one instructional row showing the
  current template; every editor result and error exposes the concise token
  reference through `⌘L`
- The Large Type reference does not advertise `%e` or operation-specific
  advanced tokens
- `%z`, `%s`, `%x`, and `%q` remain accepted for advanced users
- Pending location moves appear in Configuration and inline blocked preset
  saves
- `Reset output template` appears only for a customized template and restores
  `%P/%f-clop` without changing presets or Alfred preferences
- Separate global preset removal appears only when presets exist and requires
  confirmation with the preset count
- Final template saves/resets, global preset removal, and cache cleanup close
  Alfred and optionally notify instead of returning a redundant result menu
- Conditional clipboard-image cleanup reports file count and space usage,
  requires confirmation, and removes only workflow-owned cache files
- Return uses configured aggressive and preservation defaults
- Command-Return and Shift-Return invert those defaults in fully resolved
  operation requests
- Crop-capable values expose Smart Crop through Option combinations; resize-only
  forms omit Smart Crop modifiers
- Pipeline delivery remains owned by Clop; no workflow recipe system or
  pipeline output override was added
- Configured settings are authoritative and malformed configured files never
  fall back to another location
- Pending location changes hide previous presets while keeping every action
  and typed parameter executable
- Previous settings remain read-only; preset and output-template writes are
  blocked until Configuration moves the settings or starts fresh
- Starting fresh creates defaults at the configured location without deleting
  the previous file
- Interactive and headless preserved-output execution use the previous output
  template during the unresolved state
- Successful preserved-output execution warns only for a previous customized
  template when Error notifications are enabled; in-place and failed
  operations remain unchanged

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

Implement the bounded Downscale parameter menu and typed parsing described in
the product plan, following the established Crop / Resize routing, validation,
execution, and preset patterns without starting conversion or PDF-crop work.

## Verification baseline

At this checkpoint:

- `./scripts/test.sh` passes 190 tests.
- `./scripts/build.sh` produces `workflow/alfred-clop`.
- `plutil -lint workflow/info.plist` passes.
- The built workflow binary is currently Apple Silicon (`arm64`).
