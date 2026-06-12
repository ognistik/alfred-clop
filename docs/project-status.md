# Alfred Clop Project Status

Last updated: June 12, 2026

This document records the current implementation checkpoint. Keep
`project-plan.md` as the longer-term product and architecture plan; update this
file whenever a task materially changes what works or what should happen next.

## Current checkpoint

Milestones 1 and 2 are substantially complete. Milestone 3 now includes
parameter-free execution, a guided dynamic parameter step for crop and resize,
user-defined Crop / Resize action presets, and explicit preset-location
migration.

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
- External Trigger `paths` for one or multiple directly passed file paths
- Path normalization, symlink resolution, validation, and deduplication
- Media detection for images, video, audio, and PDFs
- Context-aware action capability intersection for mixed inputs
- Source-aware subtitles for selected, copied, and passed files
- Visible Alfred errors for missing, unsupported, and invalid inputs
- Injectable clipboard abstraction with no real clipboard dependency in tests
- Input context preserved across Script Filter reruns

### Workflow

- Universal Action wired through an Args and Vars object
- Clipboard keyword `clop`
- External Trigger `paths` wired through an Args and Vars object
- Shared normalized input state stored in `alfred_clop_input_json`
- Immediate actions handed to a quiet Run Script execution action
- Clop UI used for successful progress/results, with notifications for errors
- Release binary built at `workflow/alfred-clop`
- User configuration fields added for optional `presetsPath` and `copyResult`
- `presetsPath` is wired into preset storage; `copyResult` is not wired yet

### Parameter-free execution

- Typed Clop command builder using `ClopCLIDiscovery`
- `execute` mode decoding `OperationRequest` JSON
- Injectable process-running abstraction
- Standard and aggressive optimization with JSON output
- PDF uncrop and metadata stripping with text-only process results
- Argument-array invocation preserving spaces and multiple-file payloads
- Visible Alfred feedback for invalid and parameter-step requests, missing
  Clop, launch failures, invalid JSON results, and nonzero exits
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
- Typed values produce exactly one interpreted result or one visible validation
  error
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
- Context-specific Move presets action in the main action menu with source and
  destination paths shown explicitly
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

## Not implemented

- Modifier behavior for aggressive processing and original preservation
- Wiring for the `copyResult` workflow setting
- Typed headless automation request and External Trigger
- Downscale, conversion, and PDF-crop parameter menus and parsing
- Smart Crop menu choices
- Output and backup policies
- Dynamic PDF device and paper-size menus
- Workflow icons, user configuration, packaging, and release automation
- Raw bitmap clipboard data materialization

## Next recommended task

Implement the next bounded global execution-setting slice:

1. Wire the existing `copyResult` workflow checkbox into
   `ExecutionOptions.copyResult`.
2. Add Clop's explicit `--copy` argument only to commands that support it.
3. Keep `--gui` and `--copy` independent.
4. Add focused configuration, request, command-building, and filename-edge
   tests without adding output or backup policy work early.

Keep aggressive and original-preservation modifier work separate until their
execution policies are ready. Do not expand action presets into recipes,
manual ordering, custom names, or execution-option overrides.

Keep downscale, conversion, and PDF crop encoded as `ParameterStepRequest`
until their own tasks.

The longer-term automation route is one typed headless External Trigger that
accepts a versioned JSON request for inputs, action parameters, and execution
options. Do not replace the current interactive `paths` trigger until a
compatibility plan is implemented.

## Verification baseline

At this checkpoint:

- `./scripts/test.sh` passes 100 tests.
- `./scripts/build.sh` produces `workflow/alfred-clop`.
- `plutil -lint workflow/info.plist` passes.
- The built workflow binary is currently Apple Silicon (`arm64`).
