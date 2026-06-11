# Alfred Clop Project Plan

## Product goal

Build a native Alfred workflow that makes Clop's CLI discoverable without
forcing users to remember commands or valid combinations.

The workflow should feel like one coherent tool:

- users bring files in from several Alfred entry points;
- the workflow detects what those files support;
- a fuzzy-searchable menu shows only valid actions;
- optional parameters appear as another searchable step;
- one Swift executable executes the final operation and reports the result.

## Recommended scope

### Version 1

- Finder selection entry point
- Alfred Universal Action for files
- Clipboard file-path entry point
- Custom path/file selection entry point
- Optimize
- Aggressive optimize
- Crop to dimensions or aspect ratio
- Resize to long edge
- Downscale by factor
- Convert images to AVIF, HEIC, or WebP
- Reversible PDF crop and uncrop
- Strip image/video metadata
- Context-aware menus
- Fuzzy filtering
- Configurable output behavior
- Modifier-based overrides
- Actionable success and error feedback

### Later

- Chained conversion and processing pipelines
- Saved user presets
- Folder-recursive workflows
- URL inputs
- Video playback-speed actions
- Video audio removal
- Copy-result-to-clipboard actions
- Live progress UI
- Automatic update/release mechanism

The CLI supports several later features already. Delaying them keeps the first
release understandable and gives the core input/action model time to settle.

## Repository structure

Use a Swift Package rather than an Xcode-only project. Xcode can open and work
with the package, while command-line builds remain predictable.

```text
src/
|-- Package.swift
|-- Sources/
|   `-- AlfredClop/
|       |-- main.swift
|       |-- Alfred/
|       |-- Clop/
|       |-- Domain/
|       |-- Features/
|       `-- Support/
`-- Tests/
    `-- AlfredClopTests/

workflow/
|-- info.plist
|-- icon.png
`-- assets/

scripts/
|-- build.sh
|-- package.sh
`-- release.sh
```

Do not commit Swift build output or Alfred's `prefs.plist`.

## One executable, multiple modes

The single binary approach is a good fit. Alfred objects can invoke the same
binary with different subcommands:

```text
alfred-clop menu --input-env finder --query "crop"
alfred-clop menu --input-env universal-action --query "webp"
alfred-clop execute --request-json '{...}'
alfred-clop probe
```

A stronger implementation avoids passing large or fragile state through a
human-readable command string. Script Filter items should pass a small encoded
request, either:

- as Alfred variables containing JSON; or
- as a base64-encoded JSON `arg`.

The executable decodes that request into typed Swift models and constructs the
Clop argument array.

## Proposed Swift modules

### `Alfred`

- Codable Script Filter response and item models
- modifier models
- workflow environment access
- Alfred variable parsing
- JSON output
- notification and error items

Reuse the ideas from `alfred-unified-search`, but extract only the pieces this
workflow needs. Do not copy its web-search-specific fuzzy types.

### `Domain`

Core types with no Alfred or Clop process details:

```swift
enum MediaKind {
    case image
    case video
    case audio
    case pdf
    case folder
    case unknown
}

enum ClopAction {
    case optimise
    case crop
    case downscale
    case convert
    case cropPDF
    case uncropPDF
    case stripMetadata
}

struct InputSelection {
    let urls: [URL]
    let mediaKinds: Set<MediaKind>
}

struct OperationRequest: Codable {
    let inputs: [String]
    let action: ActionRequest
    let execution: ExecutionOptions
}
```

### `Clop`

- CLI discovery
- capability definitions
- typed command builder
- `Process` runner
- JSON result decoder
- text result/error parser for commands without JSON
- dynamic PDF device and paper-size provider

Keep capability rules in data rather than scattered menu conditionals:

```swift
struct ActionDefinition {
    let id: String
    let supportedKinds: Set<MediaKind>
    let requiresHomogeneousInput: Bool
    let parameterKind: ParameterKind?
}
```

### `Features`

- input collection
- action menu
- parameter menu
- execution
- result presentation
- workflow diagnostics

### `Support`

- fuzzy matching
- file-type detection
- path normalization
- logging
- test fixtures

## Input handling

Normalize every entry point into `[URL]` as early as possible.

### Alfred Universal Action

Configure it to accept multiple files. Alfred passes paths to the executable;
do not combine them into a comma-delimited string because commas are valid in
filenames.

### Finder selection

Prefer a small AppleScript/JXA bridge only for obtaining Finder's selected
paths. Pass one path per line or as JSON to Swift. All validation and action
logic stays in Swift.

### Clipboard

Swift can inspect `NSPasteboard` for:

1. file URLs;
2. newline-separated paths;
3. a single path or supported URL.

This is more robust than relying only on AppleScript's file URL clipboard
class.

### Custom paths

Use Alfred's File Filter or Browse in Alfred object to collect files, then feed
the selected paths into the same normalization route.

### Validation

- standardize and resolve file URLs;
- preserve the original path for display;
- reject missing paths with a visible Alfred item;
- identify directories separately;
- determine media type with `UTType`, then extension fallback;
- deduplicate paths without changing user order;
- handle mixed selections deliberately.

## Context-aware action menu

For a homogeneous selection, show all actions supported by that media kind.

For mixed selections, default to the intersection of supported actions. For
example:

- image + video: optimize, crop, downscale, strip metadata;
- image + PDF: optimize, crop;
- video + audio: optimize, downscale;
- image + video + PDF: optimize, crop;
- PDF only: optimize, crop, reversible crop, uncrop;
- audio only: optimize, downscale.

Conversion should only appear when every selected item is an image.

If a folder is selected, either:

- show recursive actions explicitly; or
- inspect only when the user chooses a recursive action.

Avoid recursively scanning large folders while Alfred is waiting for a Script
Filter response.

## Menu flow

Use a small state machine instead of several unrelated binaries:

```text
Input
  -> Action menu
      -> Parameter menu, when required
          -> Execute
      -> Execute, for immediate actions
```

Suggested top-level actions:

1. Optimize
2. Aggressive Optimize
3. Crop / Resize
4. Downscale
5. Convert
6. PDF Crop
7. PDF Uncrop
8. Strip Metadata
9. More Video Actions

The query should fuzzy-match title, synonyms, and keywords. Examples:

- `compress`, `shrink`, `small` -> Optimize
- `resize`, `dimensions`, `edge` -> Crop / Resize
- `half`, `75`, `scale` -> Downscale
- `webp`, `avif`, `heic`, `format` -> Convert
- `metadata`, `privacy`, `exif` -> Strip Metadata

## Parameter menus

### Crop and resize

Offer presets plus free-form parsing:

- common sizes: `1200x630`, `1920x1080`, `1080x1080`;
- common ratios: `16:9`, `4:3`, `3:2`, `1:1`, `9:16`;
- long edge: `1920`, `1600`, `1280`, `1080`;
- width or height preserving ratio: `128x0`, `0x720`;
- custom typed value.

### Downscale

Offer `0.9` through `0.1`, with `0.5` prominent. Accept percentages such as
`75%` and normalize them to `0.75`.

### Convert

First choose AVIF, HEIC, or WebP, then choose quality. A user-configured default
quality can make this a one-step action.

### PDF crop

Offer four categories:

- device;
- paper size;
- aspect ratio;
- custom resolution.

Read device and paper values from the installed CLI and cache them in Alfred's
workflow cache directory. Refresh when the Clop app version changes.

## Modifier proposal

Modifiers should be predictable and visible in each Alfred result subtitle.

Recommended defaults:

| Input | Effect |
| --- | --- |
| Return | Run with configured defaults |
| Command-Return | Toggle aggressive optimization |
| Option-Return | Toggle preserving the original via output/backup policy |
| Control-Return | Toggle Clop floating UI |
| Shift-Return | Copy processed output to clipboard when supported |

Do not hard-code "Command means aggressive" at execution time. Encode the
modifier's resolved `OperationRequest` directly in that Alfred item's `mods`
JSON. This makes the subtitle and actual operation impossible to drift apart.

For an action that is already explicitly aggressive, Command can invert back
to standard optimization.

## Workflow configuration

Suggested Alfred user configuration:

| Setting | Initial values |
| --- | --- |
| Clop CLI path | Auto-detect, optional override |
| Default optimization | Standard / Aggressive |
| Output behavior | Replace in place / Same folder / Specific folder |
| Output template | `%P/%f_optimised.%e` or custom |
| Backup behavior | Trust Clop / Workflow copy / None |
| Backup folder | Same folder / Specific folder |
| Show Clop UI | On / Off |
| Copy result | On / Off |
| Default conversion format | WebP / AVIF / HEIC |
| Default conversion quality | 0-100 |
| Adaptive optimization | App default / On / Off |
| PDF aggressive DPI | App default / Adaptive / fixed DPI |

There is an important distinction between output and backup:

- `--output` preserves the original by writing elsewhere;
- a workflow-managed backup copies the original before an in-place operation;
- Clop's own backup behavior is configured in Clop, not through a CLI flag.

The interface should use those precise terms.

## Execution design

Build arguments as an array:

```swift
let arguments = [
    "optimise",
    "--json",
    "--no-progress",
    "--output", outputTemplate,
] + inputPaths
```

Never use `eval`, shell quoting, or one combined argument string.

Execution steps:

1. Resolve and validate the Clop CLI.
2. Optionally launch Clop if it is not running.
3. Perform workflow-managed backups if requested.
4. Build a typed command.
5. Run synchronously unless fire-and-forget was explicitly chosen.
6. Decode JSON or parse command text.
7. Return a notification or Alfred result with output paths and failures.

For long video/PDF jobs, Alfred should hand off execution to a Run Script or
background invocation rather than keeping the Script Filter process alive.
The same binary can implement both modes.

## Fuzzy search

The fuzzy matcher in `alfred-unified-search` is a reasonable starting point,
but it currently targets a web-search-specific model. Generalize it:

```swift
protocol FuzzySearchable {
    var searchableText: String { get }
    var searchAliases: [String] { get }
}
```

Rank:

1. exact action ID or alias;
2. prefix matches;
3. word-boundary matches;
4. ordinary subsequence matches;
5. recently/frequently used actions as a small tie-breaker.

The data set is tiny, so clarity and deterministic ranking matter more than
micro-optimization.

## Testing strategy

### Unit tests

- media type detection
- mixed-selection capability intersection
- fuzzy ranking
- size, ratio, percentage, and quality parsing
- modifier resolution
- output-template construction
- CLI path discovery
- command argument construction
- Codable Alfred JSON

### Integration tests

Use small fixture files for each supported media kind:

- PNG and JPEG
- MP4
- M4A or MP3
- PDF

Run tests against a temporary copy, never the original fixture. Capture:

- successful JSON schemas;
- already-optimized/no-change results;
- missing inputs;
- invalid factors and sizes;
- mixed batch success/failure;
- output templates;
- Clop-not-running behavior;
- conversion collision behavior.

### Manual Alfred checks

- Finder selection
- clipboard file URLs
- Universal Action with multiple files
- filenames containing spaces, quotes, commas, and Unicode
- every modifier
- missing Clop installation
- workflow configuration migration

## Milestones

### 1. Swift foundation

- Create `src/` Swift Package.
- Add Alfred Codable models.
- Generalize fuzzy search.
- Add CLI discovery and diagnostics.
- Establish tests.

### 2. Inputs and action menu

- Normalize Universal Action, Finder, clipboard, and custom paths.
- Detect media kinds.
- Produce context-aware Script Filter JSON.
- Add fuzzy action filtering.

### 3. Core execution

- Implement optimize, crop, downscale, and conversion.
- Add typed command builder.
- Decode Clop JSON.
- Add output and backup policies.

### 4. PDF and metadata

- Add dynamic PDF device/paper menus.
- Add crop/uncrop PDF.
- Add metadata stripping.

### 5. Alfred packaging

- Build workflow objects and user configuration.
- Add icons and modifier subtitles.
- Package a universal or architecture-appropriate binary.
- Generate `.alfredworkflow`.

### 6. Reliability and release

- Complete integration fixtures.
- Test on clean Alfred/Clop configuration.
- Add versioning, changelog, and release automation.
- Publish installation and troubleshooting documentation.

## Decisions made

- Use one Swift executable for menu generation and execution.
- Use a Swift Package under `src/`.
- Keep Alfred workflow source under `workflow/`.
- Use direct `Process` invocation, never shell `eval`.
- Derive available actions from selected media types.
- Dynamically read Clop's PDF presets.
- Treat the installed Clop CLI as the capability authority.
- Separate output preservation from true backups.

## Open decisions

- Minimum macOS version.
- Whether the released binary is universal or Apple Silicon only.
- Whether Clop should be launched automatically when needed.
- Exact default output and backup policy.
- Whether version 1 includes folders and URLs.
- Whether recent-action ranking is desirable.
- Whether chained convert/process pipelines belong in version 1.1 or later.
