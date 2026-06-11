# Alfred Clop Project Status

Last updated: June 11, 2026

This document records the current implementation checkpoint. Keep
`project-plan.md` as the longer-term product and architecture plan; update this
file whenever a task materially changes what works or what should happen next.

## Current checkpoint

Milestones 1 and 2 are substantially complete. The project has a native Swift
executable, tested input collection, media detection, capability filtering, and
a shared Alfred action menu. Clop operations are encoded but not executed yet.

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
- Release binary built at `workflow/alfred-clop`

## Not implemented

- Clop process execution
- Parameter menus
- Crop, downscale, conversion, and PDF-crop parameter parsing
- Output and backup policies
- Dynamic PDF device and paper-size menus
- Success/result presentation
- Workflow icons, user configuration, packaging, and release automation
- Raw bitmap clipboard data materialization

## Next recommended task

Start Milestone 3 with parameter-free execution:

1. Add a typed Clop command builder.
2. Decode `OperationRequest` in a new executable mode.
3. Run commands through an injectable `Process` abstraction.
4. Implement standard and aggressive optimize first.
5. Add visible Alfred feedback for discovery, launch, and exit failures.

Keep parameter-requiring actions encoded as `ParameterStepRequest`; do not
implement their menus in the same task.

## Verification baseline

At this checkpoint:

- `./scripts/test.sh` passes 42 tests.
- `./scripts/build.sh` produces `workflow/alfred-clop`.
- `plutil -lint workflow/info.plist` passes.
- The built workflow binary is currently Apple Silicon (`arm64`).
