# Alfred Clop Project Status

Last updated: June 17, 2026

This document records the current implementation checkpoint. Keep
`project-plan.md` as the longer-term product and architecture plan; update this
file whenever a task materially changes what works or what should happen next.

## Current checkpoint

Milestones 1 and 2 are substantially complete. Milestone 3 includes
parameter-free execution, a guided dynamic parameter step for crop and resize,
the bounded Downscale parameter step, user-defined Crop / Resize and
Downscale action presets, media-specific conversion with inline controls and
presets, media-specific Optimize controls and presets, reversible Crop PDF
controls and presets, the Downscale controls branch, shared settings, and the
unified input and routing foundation planned for Milestone 6.

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

The public External Trigger now supports advanced headless output overrides.
`execute` routes can inherit defaults, force the configured output template,
force a one-off custom template, or force in-place behavior for one run. Menu
routes reject execution overrides so interactive state stays predictable.

The shared settings and global execution-policy foundation is complete.
Workflow-owned settings and action presets now share `settings.json`,
original preservation uses validated Clop output templates, and Configuration
owns output-template reset, global preset reset confirmation, Workflow
Settings access, and clipboard-image cache cleanup.

Crop / Resize and Downscale preset saves now clear the parameter query and
return directly to the same submenu, restoring the instructional row and full
preset list while keeping Alfred open.

Settings storage now follows one direct rule: the configured folder is the
only source of truth. A missing file is created with defaults on the first
user-facing executable invocation, changing the folder switches
configurations, and no migration or fallback state is maintained.

Script Filter subtitles now share a compact style across the main action
menu, parameter menus, conversion controls, presets, Configuration, and
modifier rows. Processing subtitles keep source and folder-count clarity while
using short effect labels and consistent title-case hints such as `Save
Preset`, `Remove Preset`, `Smart Crop`, and `Clop Defaults`.

Crop PDF now has a complete shallow parameter menu for Clop's reversible
`crop-pdf` surface. The menu offers root branches for custom ratio/resolution,
Apple devices, and paper sizes; reads device and paper values from the
installed Clop CLI; supports inline `controls:` for `auto`, `portrait`,
`landscape`, and `extend`; infers the likely branch when the user types at the
root; and stores Crop PDF presets in `settings.json`.

The current polish checkpoint tightened parameter-menu language across
Optimize, Crop / Resize, Downscale, Convert, and Crop PDF. Inline examples now
use spaced slash separators, saved preset subtitles avoid repeating actions
already shown in titles, Crop / Resize preset titles now describe the action
rather than raw shorthand, Convert target branches keep a guide row above
matching presets for partial control input, and Convert and Optimize saved
controls now autocomplete with their visible menu syntax. Default executable
rows say `Run Defaults` where useful, Optimize default rows use singular media
names when one clear file is present, Optimize branch rows describe opening
controls instead of implying root-level typing, empty/partial/invalid guide
rows use compact `Use ...` syntax hints, valid typed rows avoid generic syntax
repetition, Large Type input references are capped to five visible inputs with
consistent `Inputs` spacing, and Optimize's default modifier now inverts the
configured aggressive default instead of always advertising both Standard and
Aggressive.

Crop PDF reversible menu rows now follow the same title/subtitle split as the
other parameter menus. Device, paper, ratio, and resolution rows carry their
target type in the title, explicit controls are appended only when selected,
saved preset subtitles stay compact, and branch guidance uses source context,
concise `Use ...` hints, and clear control affordances without repeating title
content.

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
- The `:` Configuration namespace remains available when selected, copied, or
  passed input has no processable media, including unsupported-only folders
- Returning from Configuration never treats an empty normalized input as
  compatible with every action; unresolved clipboard, Finder, and passed-input
  routes return to their original source-aware empty or unsupported state
- Unsupported clipboard content uses generic, path-free feedback because the
  clipboard contents may be incidental or unexpected
- One Optimize result in the main menu opens the Optimize defaults, controls,
  and presets menu while keeping immediate Standard and Aggressive execution on
  modifiers
- Source-aware subtitles for selected, copied, and passed files
- Compact source/object subtitles distinguish selected, copied, and passed
  files, folders, URLs, and mixed batches without the generic "input" wording
- Processing action rows expose the original selected, copied, or passed input
  to Quick Look and Alfred Actions while preserving typed Clop requests on
  Return
- Processing action rows also expose the original paths and URLs through
  Alfred Large Type, capped for very large batches
- Multi-file and mixed file/folder menu inputs are passed to Alfred Actions as
  their original files and folders; folders are not expanded to inspected
  children
- HTTP/HTTPS menu inputs are passed to Alfred Actions as URL actions
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
- `menu: Configuration` and its typed route open the main menu with `:`
  prefilled while preserving the requested input source
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
- Universal Action exposes one Optimize entry; Command-Return inverts the
  configured aggressive default, Shift-Return inverts Preserve Original, and
  Command-Shift combines both
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
  presets, and keep a valid interpreted action first before partial preset
  matches
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
- Crop / Resize typed controls accept `ad` / `adaptive`, `no-ad` /
  `no-adaptive`, and `m` / `mute` after the size, with spaces or commas
  between tokens
- The empty Crop / Resize instruction row offers a `controls:` editor through
  Tab and Control-Return, matching the shallow controls flow used by Optimize
  and Convert
- Interactive guidance promotes `ad` for adaptive behavior and only shows
  video mute guidance when the selected, copied, or passed input could include
  video; `no-ad` remains accepted as an advanced explicit override in the
  Large Type reference and automation grammar
- Typed `m` / `mute` controls and saved mute presets are rejected or hidden for
  clearly non-video input, while video, folders, URLs, and ambiguous input keep
  them available
- Incomplete control prefixes keep a helpful non-executable grammar row
  instead of falling through to unrelated presets, while invalid and
  conflicting controls are rejected visibly
- Crop / Resize execution builds `--adaptive-optimisation`,
  `--no-adaptive-optimisation`, and `--remove-audio` as separate arguments
- External Trigger execution supports the same controls through compact
  `controls:` grammar or explicit `adaptive`, `no adaptive`, `mute`, and
  `remove audio` booleans
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
- Crop / Resize presets may include adaptive optimization and mute controls,
  and equivalent typed control aliases combine with saved presets
- Fixed grammar instruction followed by saved presets with stable item UIDs
- Saved presets use deterministic natural sorting by their friendly display
  values because Alfred learning is disabled for this submenu
- Free-form typed values remain available alongside saved presets
- Matching typed and saved values combine into one result marked as saved
- Control-Return saves new typed values immediately
- Control-Return on a saved preset opens a typed removal confirmation step
  with a visible Cancel row
- Confirmed removal returns to Crop / Resize with inputs and source context
  preserved
- Malformed and unsupported preset files are rejected visibly without being
  overwritten
- Configured paths and input filenames containing spaces are covered by tests

### Downscale

- Dedicated Downscale parameter menu follows the Crop / Resize guided-input
  pattern
- Empty Downscale queries show one non-executable instructional item instead
  of workflow-authored presets
- Typed factors accept `0.5`, `.5`, `50`, `50%`, `75`, `75%`, and similar
  supported values
- Whole numbers from `2` through `99` normalize as percentages; `50` becomes
  the factor `0.5`
- Values must be greater than zero and less than one; bare `1`, `100%`, zero,
  negative values, and enlarging values are rejected visibly
- Downscale results display percentage-first labels such as `50%` with the
  normalized Clop factor in the subtitle
- Downscale supports the same shallow `controls:` editor pattern as Crop /
  Resize, accepting `ad` / `adaptive`, `no-ad` / `no-adaptive`, and video
  `m` / `mute` after the required factor
- Root Downscale typing also accepts `factor + controls` while keeping
  factor-only rows and saved presets working as before
- Downscale controls use compact guidance rows, scoped preset matching,
  autocomplete that mirrors visible syntax, and Large Type references with
  the shared input block
- Downscale execution uses
  `clop downscale --factor VALUE --json --no-progress --skip-errors`, plus
  optional `--adaptive-optimisation`, `--no-adaptive-optimisation`, and
  `--remove-audio` when explicitly requested
- Downscale inherits configured Clop UI, copy-result, recursion, and output
  preservation settings
- External Trigger execution supports `execute: Downscale` with required
  `factor:` using the same grammar as the menu, plus optional `controls:`,
  `adaptive:`, `no adaptive:`, `mute:`, and `remove audio:`
- Downscale presets are stored in `settings.json`, scoped to the Downscale
  submenu, and support Control-Return save and confirmation-based removal with
  a visible Cancel row

### Media-specific conversion

- Image, video, and audio conversion menus execute built-in targets immediately
  with Clop's app defaults
- Image targets: WebP, AVIF, HEIC, JXL, JPEG, and PNG
- Video targets: MP4/H.264, GIF, WebM/VP9, HEVC, x265, and AV1/MKV
- Audio targets: MP3, AAC, M4A, Opus, Ogg, FLAC, WAV, and AIFF
- Tab opens a reversible inline controls editor by autocompleting the target in
  the current query; deleting the value returns to the target list
- Control-Return on a controllable built-in target enters the same visible
  target query as Tab, so Backspace returns to the format list identically
- Image conversion accepts compression `5...100`
- MP4 conversion accepts compression `5...100` or `auto`; fixed-setting video
  targets do not expose meaningless controls
- Audio conversion uses explicit `c70` compression and `b128` bitrate grammar
- Empty controls editors retain an executable Clop-default result rather than
  requiring another step
- Complete target-and-control combinations can be saved with Control-Return;
  saves and confirmed removals return to the full media target list, while
  existing presets use confirmation-based Control-Return removal with a
  visible Cancel row
- Saved conversion presets appear in both the media target list and the
  target-specific controls editor with concise saved-preset subtitles
- Built-in same-format image targets are hidden only for clear homogeneous
  inputs, with JPG and JPEG treated as equivalent
- Saved same-format recompression presets remain visible and executable
- Typed External Trigger execution supports `execute: Convert` with format
  inference plus optional compression or bitrate parameters; media-specific
  `Convert Image`, `Convert Video`, and `Convert Audio` remain compatible
- App-backed conversion uses JSON result inspection and inherits Clop UI,
  copy-result, recursion, and preservation settings
- External Trigger conversion requests are rejected before process launch when
  the inferred target media does not match the normalized input
- Preservation preflight predicts the converted extension before checking
  collisions and choosing numeric suffixes

### Media-specific Optimize controls

- Optimize is a first-class parameter menu: Return opens the Optimize menu,
  Command-Return runs immediate Aggressive Optimize, Option-Return runs
  immediate Standard Optimize, and Shift combinations invert preservation for
  immediate runs
- Homogeneous input interprets typed Optimize queries directly as controls,
  with `controls:` still available as an explicit editor; mixed input exposes
  `image controls:`, `video controls:`, `pdf controls:`, and
  `audio controls:` prefixes for compatible media kinds
- Empty Optimize controls editors show one non-executable typing guide row
  with concise Large Type references followed by saved presets for the
  relevant media kind
- Image Optimize accepts `70` compression and `ad` / `adaptive` compression
- Video Optimize accepts `70` compression, `au` / `auto` compression,
  `hw` / `hardware`, `sw` / `software`, `ll` / `lossless`, and `ad` /
  `adaptive` encoders, `m` / `mute`, and playback speeds such as `2x` or
  `1.5x`; compact subtitles keep encoder detail in Large Type and use
  `Use 5-100 / au + encoder + m + 2x`
- PDF Optimize accepts `ad` / `adaptive`, supported bare DPI values, and
  `dpi 150` forms
- Audio Optimize accepts `70` compression, `b128`, and `bitrate 128`
- Optimize controls accept spaces or commas between tokens
- Optimize presets are stored in `settings.json`, scoped by action and media
  kind, visible in both the Optimize menu and the matching controls editor,
  and support Control-Return save plus confirmation-based removal with a
  visible Cancel row
- Menu and External Trigger execution both use typed media-specific Optimize
  request models and build Clop arguments as arrays
- External Trigger execution supports explicit media controls, including video
  playback speed, while presets remain interactive-only
- Mixed local or URL input is filtered to matching known media before launching
  a media-specific Optimize command; folders remain broad and are passed
  through to Clop with the configured recursion policy

### Crop PDF

- Crop PDF opens a dedicated parameter menu instead of the previous placeholder
- Root branches use `ratio:`, `device:`, and `paper:` so Backspace naturally
  returns to broader choices
- Root typing infers the likely branch: ratio-like values open the custom
  ratio flow, device-like searches filter devices, and paper-like searches
  filter paper sizes
- `device:` and `paper:` browse and filter Clop's current supported target
  lists, preserving group names and searchable aliases without long subtitles
- Empty `ratio:`, `device:`, and `paper:` branches keep one concise guidance
  row first, then show only saved presets scoped to that branch instead of
  flooding the menu with every Clop target
- Device and paper lists are read through `crop-pdf --list-devices` and
  `crop-pdf --list-paper-sizes`, then cached under Alfred's workflow cache
  when available
- `ratio:` accepts supported ratio and resolution values such as `16:9` and
  `1200x630`
- Incomplete or invalid ratio searches still keep matching saved ratio presets
  visible below the validation feedback
- Optional controls support `a` / `auto`, `p` / `portrait`,
  `l` / `landscape`, and `e` / `extend` both directly after the target and
  through a target-specific `controls:` editor
- Crop PDF presets are stored in `settings.json` and can be saved or removed
  from the menu with the same confirmation pattern as other parameter menus
- Execution builds `crop-pdf` argument arrays with exactly one of
  `--aspect-ratio`, `--for-device`, or `--paper-size`, plus optional
  `--page-layout`, `--extend`, `--recursive`, and `--output`
- External Trigger execution supports `execute: Crop PDF` with exactly one
  `ratio`, `device`, or `paper size` target and optional layout or extend
  controls

### Shared settings and execution policy

- Versioned `settings.json` stores action presets and the active output
  template together
- Default storage under `alfred_workflow_data`; optional `settingsPath`
  selects a custom folder
- Changing `settingsPath` switches to the independent settings in that folder
- Missing settings files are atomically created with defaults on the first
  user-facing executable invocation
- Newly written settings documents use stable, human-readable JSON for Quick
  Look and manual inspection
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
- Public headless `execute` requests may use `output: default`,
  `output: template`, `output template: TEMPLATE`, or `output: false`;
  omitted output is the same as `output: default`
- Output overrides are not accepted on `menu` routes and are rejected for
  Strip Metadata because Clop's `strip-exif` command has no output option
- Raw clipboard-image expiry follows the configured retention period
- Typing `:` replaces processing actions with Configuration commands; deleting
  it restores actions for the same normalized input
- Output Template autocompletes to the query-based `:template ` editor
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
- The file-backed Workflow Settings result opens Alfred configuration with
  Return, reveals the active settings folder with Command-Return, and supports
  Quick Look and Alfred file actions for `settings.json`
- Every Configuration namespace row, including Output Template editor results,
  confirmations, and mutation feedback, exposes the active `settings.json` to
  Quick Look and Alfred file actions when settings can be resolved
- Configuration Large Type shows a readable settings summary with the settings
  path, current output template, and preset counts plus up to five examples per
  category; the Output Template editor keeps the token reference in Large Type
- Root Configuration commands provide stable Tab autocomplete values such as
  `:settings`, `:reset output`, `:remove presets`, and `:clear cache`
- `Reset output template` appears only for a customized template and restores
  `%P/%f-clop` without changing presets or Alfred preferences
- Separate global preset removal appears only when presets exist and requires
  confirmation with the preset count
- Final template saves/resets, global preset removal, and cache cleanup close
  Alfred on Return; Command-Return applies the mutation and returns to `:`
- Conditional clipboard-image cleanup reports file count and space usage,
  requires confirmation, and removes only workflow-owned cache files
- Return uses configured aggressive and preservation defaults
- Command-Return and Shift-Return invert those defaults in fully resolved
  operation requests
- Crop-capable values expose Smart Crop through Option combinations; resize-only
  forms omit Smart Crop modifiers
- Pipeline delivery remains owned by Clop; no workflow recipe system or
  pipeline output override was added
- Configured settings are authoritative and malformed active files never fall
  back to another location
- No migration metadata, automatic moves, fallback reads, or location-change
  warnings remain

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
  video, and audio input; ambiguous broad input shows separate honest routes
  into the implemented media-specific target menus
- Disposable-file output probes verified in-place behavior, automatic
  extension appending, directory-template requirements, silent collision
  overwrites, empty-output failure, literal unknown tokens, multi-file
  expansion, and app-backed conversion extensions
- Disposable mixed-input probes verified that broad `optimise` handles mixed
  image, video, audio, and PDF batches; typed media Optimize and Convert
  commands internally filter to matching media; and broad `crop` and
  `downscale` also process out-of-scope media through optimization side
  effects. Alfred Clop keeps strict filtering for clear known inputs, but
  ambiguous selections now preserve the broad submitted batch so Clop owns the
  final processed set, clipboard result, and output behavior.
- Ambiguous mixed input no longer lets partial known media hide otherwise
  source-capable actions, and media-specific Optimize requests preserve the
  full ambiguous batch instead of pre-filtering to the matching media subset.

## Not implemented

- Workflow icons, packaging, and release automation

### Implemented controls model

The shared controls interaction model is now:

- main action rows with controls or presets open their action menu on Return;
- fast defaults remain available through explicit modifiers;
- the main Optimize row opens the Optimize menu on Return;
- Command-Return runs immediate Aggressive Optimize;
- Option-Return runs immediate Standard Optimize;
- Shift combinations invert Preserve Original for the immediate run;
- Optimize presets are scoped by media kind and appear in both the Optimize
  menu and the relevant controls editor;
- Optimize does not expose crop or downscale controls in Alfred's UI because
  Crop / Resize and Downscale already own those workflows and already optimize;
- Crop / Resize exposes adaptive optimization and video mute controls through
  the same shallow typed query as geometry values and through a `controls:`
  editor, with longer grammar help in Large Type;
- Downscale exposes adaptive optimization and video mute controls through the
  same shallow typed query as factors and through a `controls:` editor, with
  factor-only root behavior preserved;
- Crop PDF uses root `ratio:`, `device:`, and `paper:` branches, with
  target-specific `controls:` for page layout and extend behavior;
- video Optimize includes playback speed as a typed control and External
  Trigger parameter;
- parameter menus stay shallow and query-driven, using prefixes such as
  `controls:` or `video controls:` so Backspace naturally returns to the
  broader menu;
- subtitles use compact symbols such as `⏎`, `⇥`, `⌘`, `⌥`, `⌃`, and `⇧`;
- Alfred Large Type may provide concise grammar references for dense control
  surfaces.

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
- `execute` route requires a complete typed action, inherits workflow
  execution settings, and accepts only documented advanced headless overrides
- `execute: Convert` infers image, video, or audio conversion from `format`;
  presets are intentionally not addressable through the External Trigger
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

Continue workflow polish with icons, packaging, and release automation.

## Verification baseline

At this checkpoint:

- `./scripts/test.sh` passes 298 tests.
- `./scripts/build.sh` produces `workflow/alfred-clop`.
- `plutil -lint workflow/info.plist` passes.
- The built workflow binary is currently Apple Silicon (`arm64`).
