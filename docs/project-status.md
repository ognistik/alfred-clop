# Alfred Clop Project Status

Last updated: June 12, 2026

This document records the current implementation checkpoint. Keep
`project-plan.md` as the longer-term product and architecture plan; update this
file whenever a task materially changes what works or what should happen next.

## Current checkpoint

Milestones 1 and 2 are substantially complete. The first bounded Milestone 3
slice now executes parameter-free Clop actions through a typed, tested process
boundary.

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

### CLI research

- CLI reference refreshed against the official Clop 3.0.0 release
- Media-specific optimization subcommands documented
- Image, video, and audio conversion formats documented
- Native pipeline commands and PDF `--extend` behavior documented
- Product plan now targets complete supported CLI coverage across typed
  optimization, conversion, PDF controls, folders, URLs, shared switches, and
  pipeline management

## Not implemented

- Parameter menus
- Crop, downscale, conversion, and PDF-crop parameter parsing
- Output and backup policies
- Dynamic PDF device and paper-size menus
- Workflow icons, user configuration, packaging, and release automation
- Raw bitmap clipboard data materialization

## Next recommended task

Continue Milestone 3 with the first parameter menu:

1. Add crop/resize parameter choices and parsing.
2. Encode the selected crop parameters into `OperationRequest`.
3. Extend the typed command builder for `crop`.
4. Add focused menu, parsing, command, and execution tests.

Keep downscale, conversion, and PDF crop encoded as `ParameterStepRequest`
until their own bounded slices.

## Verification baseline

At this checkpoint:

- `./scripts/test.sh` passes 58 tests.
- `./scripts/build.sh` produces `workflow/alfred-clop`.
- `plutil -lint workflow/info.plist` passes.
- The built workflow binary is currently Apple Silicon (`arm64`).
