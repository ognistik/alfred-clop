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

The finished workflow should provide discoverable access to the complete
supported Clop 3.0 CLI surface. Release milestones may stage that work, but a
feature being deferred must still have an explicit place in this plan.

## Scope and release strategy

### First usable release

- Finder selection entry point
- Alfred Universal Action for files
- Clipboard file-path entry point
- Custom path/file selection entry point
- Optimize
- Command-Return aggressive optimization override
- Crop to dimensions or aspect ratio
- Resize to long edge
- Downscale by factor
- Convert images, videos, and audio to media-specific target formats
- Reversible PDF crop and uncrop
- Strip image/video metadata
- Context-aware menus
- Fuzzy filtering
- Configurable output behavior
- Modifier-based overrides
- Actionable success and error feedback

### Complete CLI coverage

- Media-specific image, video, PDF, and audio optimization controls
- Image compression and adaptive format selection
- Video compression, encoder selection, playback speed, and audio removal
- PDF DPI and destructive crop controls
- Audio compression and explicit bitrate controls
- Every documented image, video, and audio conversion target
- App-backed conversion with JSON results
- Legacy offline image conversion as an advanced compatibility action
- Reversible PDF crop by device, paper, ratio, or resolution
- PDF page layout and extend-with-empty-paper controls
- Saved pipeline discovery, inspection, execution, creation, replacement, and
  deletion
- Inline pipeline execution
- Folder and recursive processing
- URL inputs where supported by the selected command
- Include/exclude type filters where supported
- Copy-result-to-clipboard, skip-errors, Clop UI, and output controls
- Command-specific aggressive, adaptive, PDF-DPI, and remove-audio switches
  on the broad processing commands that expose them
- Explicit background submission for users who choose fire-and-forget behavior
- Raw bitmap clipboard data materialization
- Diagnostics that report the detected Clop app version and available command
  families

### Product enhancements

- User-defined action presets for reusable values inside parameter menus
- User-defined recipes that combine multiple typed actions and delivery steps
- Live progress UI
- Automatic update/release mechanism

The first release stays focused, but the architecture must not encode its
smaller action set as the permanent capability model.

## CLI coverage contract

The project tracks CLI coverage by command family:

| CLI family | Required workflow coverage |
| --- | --- |
| `optimise` | Mixed-type defaults plus typed image, video, PDF, and audio controls |
| `crop` | Size, ratio, single edge, long edge, smart crop, and every documented shared processing option |
| `downscale` | Typed factors and percentages plus every documented shared processing option |
| `convert image` | WebP, AVIF, HEIC, JXL, JPEG/JPG, and PNG |
| `convert video` | MP4/H.264, GIF, WebM/VP9, HEVC, x265, and AV1/MKV |
| `convert audio` | MP3, AAC, M4A, Opus, Ogg, FLAC, WAV, and AIFF |
| `convert legacy` | Offline AVIF, HEIC, and WebP conversion with quality and collision controls |
| `crop-pdf` | Device, paper, ratio/resolution, layout, extend, recursive, and output |
| `uncrop-pdf` | Single/batch input, recursive folders, and output |
| `strip-exif` | Image/video batches, folders, recursion, and type filters |
| `pipeline` | List, show, run, add, replace, and delete saved pipelines; run inline pipelines |

Whenever a future Clop release changes `--help`, update
`docs/clop-cli-reference.md` first and then reconcile this table, capability
definitions, tests, and status.

CLI coverage is complete only when each row has:

1. a discoverable Alfred route or menu;
2. typed request validation;
3. argument-array command construction;
4. success and error handling appropriate to JSON or text output;
5. focused tests for valid, invalid, batch, and filename-edge cases.

Unsupported combinations must be hidden or rejected before process launch.

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
alfred-clop automate --request-json '{...}'
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
    case optimiseImage
    case optimiseVideo
    case optimisePDF
    case optimiseAudio
    case crop
    case downscale
    case convert
    case cropPDF
    case uncropPDF
    case stripMetadata
    case runPipeline
}

enum InputItem {
    case localFile(URL)
    case folder(URL)
    case remoteURL(URL)
}

struct InputSelection {
    let items: [InputItem]
    let mediaKinds: Set<MediaKind>
}

struct OperationRequest: Codable {
    let inputs: [String]
    let action: ActionRequest
    let execution: ExecutionOptions
}
```

`ActionRequest` should model typed parameters rather than passing through an
unvalidated flag bag. Expected request families include:

- mixed and media-specific optimization;
- crop and downscale;
- media-specific conversion;
- reversible PDF crop and uncrop;
- metadata stripping;
- saved and inline pipeline execution.

Pipeline administration should use separate request types because list/show
are read operations while add/delete mutate Clop's pipeline library.

`ExecutionOptions` should represent only options valid across the selected
command, such as UI visibility, output, copy result, recursion, skip errors,
background submission, and type filters. Media-specific compression, bitrate,
encoder, DPI, and crop choices belong in `ActionRequest`. Broad-command
modifiers such as aggressive mode, adaptive optimization, PDF DPI, and remove
audio must be capability-checked because they are not accepted everywhere.

### `Clop`

- CLI discovery
- capability definitions
- typed command builder
- `Process` runner
- JSON result decoder
- text result/error parser for commands without JSON
- dynamic PDF device and paper-size provider
- pipeline list/show provider and pipeline mutation commands
- app-version reader for cache invalidation and diagnostics

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
- media-specific optimization menus
- media-specific conversion menus
- pipeline browser, runner, and administration menus
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

Normalize every entry point into `[InputItem]` as early as possible. Remote
URLs are not file URLs and must remain distinct from local paths until command
validation. Do not pass remote URLs through local existence checks or
`FileManager` normalization.

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

### External automation

Provide one stable headless External Trigger for callers that already know the
desired operation and do not want to show Alfred's UI. Prefer the identifier
`clop`; retain or alias the existing `paths` trigger while migrating existing
interactive callers.

The trigger argument must be a versioned JSON envelope, not comma-separated
text or a shell-like command. Paths may contain commas, spaces, quotes, and
newlines, and future actions require typed parameters and execution options.

Example shape:

```json
{
  "version": 1,
  "inputs": ["/path/one.png", "/path/two.png"],
  "action": {
    "type": "crop",
    "size": "1920",
    "longEdge": true,
    "smartCrop": false
  },
  "execution": {
    "aggressive": false,
    "preserveOriginal": false
  }
}
```

The External Trigger should pass this payload to the same Swift executable and
typed validation used by Alfred menu results. It must normalize local inputs
through `InputCollector`, capability-check the requested action, build process
arguments as arrays, and report failures without requiring a Script Filter.
Successful automation should remain quiet by default, with an explicit result
mode added later if automation clients need structured output.

The interactive `paths` route and headless `clop` route solve different
problems:

- `paths`: pass files, then let the user choose in Alfred;
- `clop`: pass a complete typed request and execute without Alfred UI.

Do not infer whether to show a menu from missing ad hoc string fields. Keep the
two request modes explicit and typed.

### URLs

Provide a dedicated keyword or External Trigger for one or more `http`/`https`
URLs. Show only commands whose help documents URL support. Preserve each URL
as one argument and reject unsupported schemes visibly.

### Folders

Treat a folder as an explicit input mode. Before execution, let the user choose
top-level-only or recursive processing and, where supported, include/exclude
type filters. Do not enumerate a large folder merely to build the action menu.

### Validation

- standardize and resolve file URLs;
- preserve the original path for display;
- reject missing paths with a visible Alfred item;
- identify directories separately;
- determine media type with `UTType`, then extension fallback;
- deduplicate paths without changing user order;
- validate remote URLs without requiring local existence;
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
- audio only: optimize, downscale, convert.

Conversion should appear for homogeneous image, video, or audio selections.
Each media kind needs its own target-format menu. For a mixed selection,
conversion may appear only if the workflow first offers an explicit
media-specific split; do not send mixed media to one ambiguous conversion
request.

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
2. Optimize with Controls
3. Crop / Resize
4. Downscale
5. Convert
6. PDF Crop
7. PDF Uncrop
8. Strip Metadata
9. Run Pipeline
10. Manage Pipelines

Keep fast defaults near the top. Advanced controls should remain discoverable
through searchable actions rather than turning every operation into a long
mandatory wizard. Aggressive Optimize should not remain a separate top-level
action once Command-Return is implemented for Optimize.

The query should fuzzy-match title, synonyms, and keywords. Examples:

- `compress`, `shrink`, `small` -> Optimize
- `resize`, `dimensions`, `edge` -> Crop / Resize
- `half`, `75`, `scale` -> Downscale
- `webp`, `avif`, `heic`, `gif`, `mp3`, `format`, `codec` -> Convert
- `metadata`, `privacy`, `exif` -> Strip Metadata

## Parameter menus

### Crop and resize

Do not ship workflow-authored size presets. With an empty query, show one
non-executable instructional item:

```text
Type crop or resize parameters
Examples: 1200x630, 16:9, 1920, w128, h720
```

Once the user types, show one primary interpreted result:

| Input | Meaning | Clop size |
| --- | --- | --- |
| `1200x630` | Exact dimensions | `1200x630` |
| `16:9` | Aspect ratio | `16:9` |
| `1920` | Aspect-preserving long edge | `1920` with `--long-edge` |
| `w128` | Fixed width, calculated height | `128x0` |
| `h720` | Fixed height, calculated width | `0x720` |

Continue accepting Clop's native `128x0` and `0x720` forms. Subtitles must
explain the interpretation before execution. Invalid input should produce one
clear, non-executable result with concise examples.

The instructional item must always remain at the top of the parameter menu,
even when presets exist. Users must always be able to type and run a new value
without first choosing a preset.

Only user-created presets may appear below the instructional or interpreted
item. Do not automatically promote recent values into presets. Give each
preset a stable Alfred item `uid` so Alfred can learn the relative order of
the presets from usage; do not add manual preset ordering. Verify this in
Alfred itself because its Script Filter documentation does not guarantee how a
fixed non-learning row and learned UID rows are ordered when mixed. The
required product behavior is that the instructional row stays first while
Alfred learns the order among presets.

An action preset is one normalized typed action choice. It stores no inputs
and no execution settings. Output behavior, filename templates, copy-result
behavior, Clop UI visibility, preservation, and backups always come from the
current workflow configuration. Presets never override those global settings.

Simple action presets do not have custom names. Their normalized value is
their identity and display label: for example `1200x630`, `16:9`, `1920`,
`w128`, or `h720`. Equivalent input forms must resolve to one preset and use
the friendlier workflow grammar for display; for example, `w128` and `128x0`
represent the same preset and display as `w128`.

Control-Return on a valid typed result saves it immediately. If the normalized
value is already saved, show one combined result marked as saved rather than a
duplicate typed result and preset. Attempting to save it again must leave
storage unchanged and provide clear feedback.

Return on a preset executes it. Control-Return on an existing preset opens a
confirmation step. Confirming removes the preset and returns to the same
parameter menu with the remaining presets visible. Never delete a preset
immediately from the modifier action.

Presets live only in the submenu for their action. Crop presets appear in Crop
/ Resize, downscale presets in Downscale, and conversion presets in the
relevant Convert menu. A separate Manage Presets menu is not required.

Preset storage:

- if the `presetsPath` workflow setting is empty, store `presets.json` in
  `alfred_workflow_data`;
- if `presetsPath` points to a custom folder, read and write
  `<presetsPath>/presets.json`;
- create the file when absent and use an existing compatible file when present;
- use a versioned JSON schema and atomic writes;
- never store presets in the workflow bundle itself;
- when the configured location changes, do not silently copy, merge, or delete
  files. A future explicit migration action may move or merge presets between
  the previous and new locations.

The custom folder is the simple cross-Mac strategy: users may choose an iCloud
Drive, Dropbox, or other locally available synchronized directory.

Recipes are a separate future concept. A recipe may combine multiple ordered
actions with output naming or destination behavior and may eventually have a
custom name and management menu. Do not widen the action-preset schema into a
recipe schema or implement recipe persistence as part of the initial preset
work. Clop saved pipelines remain a separate native Clop feature and should
stay opaque until their grammar is stable enough to model safely.

### Downscale

Use the same guided-input principle as crop: show syntax help when empty, then
interpret a typed factor or percentage as one primary result. Accept values
such as `0.5` and `75%`, normalizing percentages to factors such as `0.75`.
Only user-created presets should appear as additional choices.

### Convert

First choose a target valid for the selected media kind:

- images: WebP, AVIF, HEIC, JXL, JPEG, or PNG;
- videos: MP4/H.264, GIF, WebM/VP9, HEVC, x265, or AV1/MKV;
- audio: MP3, AAC, M4A, Opus, Ogg, FLAC, WAV, or AIFF.

Then offer compression or bitrate controls supported by that target. A
user-configured media-specific default can make conversion a one-step action.

Offer legacy local conversion as a clearly labeled image-only alternative for
AVIF, HEIC, and WebP. Its 0-100 quality scale and overwrite behavior are
different from app-backed conversion and must not share the same request model.

### Media-specific optimize

- image: compression `5...100` or adaptive, optional downscale and crop;
- video: compression `5...100` or auto, encoder, remove audio, speed,
  downscale, and crop;
- PDF: adaptive or enumerated DPI, optional destructive crop;
- audio: compression `5...100` or an explicit supported bitrate.

The simple Optimize action should continue to use Clop's mixed-type defaults.
The controlled variants require homogeneous media input.

### PDF crop

Offer:

- device;
- paper size;
- aspect ratio;
- custom resolution;
- page layout: auto, portrait, or landscape;
- crop content or extend pages with empty paper.

Read device and paper values from the installed CLI and cache them in Alfred's
workflow cache directory. Refresh when the Clop app version changes.

### Pipelines

For selected inputs, list compatible saved pipelines from
`clop pipeline list --json`, then execute the chosen name. Also provide an
advanced inline pipeline action that accepts the pipeline expression as one
opaque argument.

Pipeline management should support:

- listing saved pipelines and folder automations;
- showing a saved pipeline's steps;
- adding or replacing a named pipeline;
- choosing an optional image, video, PDF, or audio restriction;
- toggling implicit optimization and floating results;
- deleting with an explicit confirmation step.

Do not attempt to parse or visually compose every pipeline step until Clop
publishes a stable complete grammar. Preserve inline step text exactly.

### Advanced execution options

Show an optional final options menu for commands that support it:

- output path or template;
- recurse into folders;
- include or exclude file types;
- copy result;
- skip invalid/unreachable inputs;
- show Clop UI;
- submit asynchronously.

Also expose aggressive mode, adaptive image optimization, PDF DPI, and video
audio removal on each broad processing command whose help includes them.

Hide unsupported options per command. Async execution is fire-and-forget and
must not promise final output paths or completion status.

## Modifier proposal

Modifiers should be predictable and visible in each Alfred result subtitle.

Recommended defaults:

| Input | Effect |
| --- | --- |
| Return | Run with configured defaults |
| Command-Return | Enable aggressive processing where the command supports it |
| Option-Return | Preserve the original using the configured output policy |
| Command-Option-Return | Enable aggressive processing and preserve the original |
| Control-Return | Save a typed value as a preset, or request removal of an existing preset |

Do not hard-code "Command means aggressive" at execution time. Encode the
modifier's resolved `OperationRequest` directly in that Alfred item's `mods`
JSON. This makes the subtitle and actual operation impossible to drift apart.

Modifiers keep one meaning across top-level and parameter menus, but only
appear where applicable. Unsupported modifiers must not silently acquire a
different action-specific meaning.

Remove the separate Aggressive Optimize action after Command-Return is
available on Optimize. Option-Return depends on a tested output-preservation
policy and must not be enabled before that policy exists. Control-Return is
valid only when the selected item contains complete parameters that can be
saved and replayed. On an existing preset it must route to a confirmation step
before removal.

Do not reserve modifiers for width/height syntax. Use `w128` and `h720` in the
query grammar so modifier keys remain available for consistent workflow-wide
behavior.

## Workflow configuration

Suggested Alfred user configuration:

| Setting | Initial values |
| --- | --- |
| Clop CLI path | Auto-detect, optional override |
| Presets path | Empty for `alfred_workflow_data`, or a custom folder |
| Default optimization | Standard / Aggressive |
| Output behavior | Replace in place / Same folder / Specific folder |
| Output template | `%P/%f_optimised.%e` or custom |
| Backup behavior | Trust Clop / Workflow copy / None |
| Backup folder | Same folder / Specific folder |
| Show Clop UI | On / Off |
| Ensure result is copied | On / Off |
| Default image conversion | WebP / AVIF / HEIC / JXL / JPEG / PNG |
| Default video conversion | MP4 / GIF / WebM / HEVC / x265 / AV1 |
| Default audio conversion | MP3 / AAC / M4A / Opus / Ogg / FLAC / WAV / AIFF |
| Default conversion compression | 5-100 / Auto where supported |
| Default audio bitrate | App default / supported kbps value |
| Default image compression | App default / Adaptive / 5-100 |
| Default video compression | App default / Auto / 5-100 |
| Default video encoder | App default / Hardware / Software / Lossless / Adaptive |
| Default PDF DPI | App default / Adaptive / enumerated DPI |
| Default audio compression | App default / 5-100 |
| Adaptive optimization | App default / On / Off |
| PDF aggressive DPI | App default / Adaptive / fixed DPI |
| Folder recursion | Ask / Top level / Recursive |
| Skip errors | On / Off |
| Conversion engine | App-backed / Legacy local when available |

There is an important distinction between output and backup:

- `--output` preserves the original by writing elsewhere;
- a workflow-managed backup copies the original before an in-place operation;
- Clop's own backup behavior is configured in Clop, not through a CLI flag.

The interface should use those precise terms.

The `copyResult` workflow checkbox should resolve into
`ExecutionOptions.copyResult`. When enabled, supported commands must receive
Clop's explicit `--copy` option. Do not assume that showing Clop's floating UI
also guarantees clipboard copying; `--gui` and `--copy` are independent CLI
options.

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
- compression, bitrate, DPI, encoder, layout, and format validation
- modifier resolution
- output-template construction
- CLI path discovery
- command argument construction
- per-command option compatibility
- pipeline list/show decoding and mutation request construction
- Codable Alfred JSON

### Integration tests

Use small fixture files for each supported media kind:

- PNG and JPEG
- MP4
- M4A or MP3
- PDF
- a folder containing mixed nested fixtures

Run tests against a temporary copy, never the original fixture. Capture:

- successful JSON schemas;
- already-optimized/no-change results;
- missing inputs;
- invalid factors and sizes;
- mixed batch success/failure;
- output templates;
- Clop-not-running behavior;
- conversion replacement, backup, and collision behavior for each media kind;
- app-backed conversion JSON results;
- typed optimization controls for each media kind;
- crop-PDF layout and extend behavior;
- recursive and type-filter behavior;
- saved and inline pipeline execution;
- pipeline list/show JSON and add/delete lifecycle;
- legacy conversion with Clop stopped;
- async submission semantics.

### Manual Alfred checks

- Finder selection
- clipboard file URLs
- Universal Action with multiple files
- filenames containing spaces, quotes, commas, and Unicode
- every modifier
- fixed instructional-row placement alongside Alfred-learned preset ordering
- folder recursion and type filters
- URL input routes
- every media-specific conversion target
- saved pipeline browsing and destructive pipeline confirmation
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

- Implement mixed optimize, crop, and downscale.
- Add typed command builder.
- Decode Clop JSON.
- Add output and backup policies.
- Replace built-in crop presets with a guided dynamic grammar.
- Add user-defined action-preset persistence and Control-Return add/remove
  behavior.
- Add capability-aware modifier requests.

### 4. Typed optimization and conversion

- Add image, video, PDF, and audio optimization controls.
- Add app-backed image, video, and audio conversion.
- Add every documented target format and target-specific control.
- Add legacy local image conversion as an advanced compatibility action.

### 5. PDF and metadata

- Add dynamic PDF device/paper menus.
- Add crop/extend layout controls and uncrop PDF.
- Add recursive and output behavior.
- Add metadata stripping with folder and type-filter support.

### 6. Folders, URLs, and shared options

- Add explicit folder and recursive routes.
- Add URL input collection for documented commands.
- Add a typed headless External Trigger for complete automation requests.
- Add raw bitmap clipboard materialization into temporary image inputs.
- Add include/exclude type filters, copy result, skip errors, and async mode.
- Make option availability command-aware.

### 7. Pipelines

- Add saved pipeline list and detail views.
- Run saved and inline pipelines.
- Add, replace, and delete saved pipelines with confirmation.
- Preserve Clop's file-type, implicit-optimization, and result-visibility
  settings.

### 8. Alfred packaging

- Build workflow objects and user configuration.
- Add icons and modifier subtitles.
- Package a universal or architecture-appropriate binary.
- Generate `.alfredworkflow`.

### 9. Reliability and release

- Complete integration fixtures.
- Add a CLI coverage checklist derived from `clop --help`.
- Report the detected Clop app version and command families in diagnostics.
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
- Keep empty parameter menus instructional rather than filling them with
  workflow-authored presets.
- Define an action preset as one normalized typed action with no inputs, custom
  name, or execution-setting overrides.
- Keep action presets inside their relevant parameter submenu; use stable
  Alfred item UIDs for learned relative ordering and keep the instructional
  item fixed at the top.
- Use Control-Return to save a typed value and to request confirmed removal of
  an existing preset.
- Keep recipes, recipe naming, recipe management, and multi-step execution as
  a separate future product concept.
- Store user presets in a versioned `presets.json`, using
  `alfred_workflow_data` by default or the configured custom folder.
- Use one typed JSON automation contract for headless execution; never parse
  comma-separated paths or shell-like request strings.
- Keep `--gui` and `--copy` as independent execution options.
- Target complete supported CLI coverage, staged across releases.
- Keep pipeline expressions opaque until Clop exposes a stable full grammar.

## Open decisions

- Minimum macOS version.
- Whether the released binary is universal or Apple Silicon only.
- Whether Clop should be launched automatically when needed.
- Exact default output and backup policy.
- Exact preset location-migration flow.
- Recipe schema, naming, editing, deletion, ordering, and execution behavior.
- Final External Trigger identifier and compatibility lifetime for `paths`.
- Whether headless automation should optionally return structured result JSON
  to callers in addition to quiet execution.
- Which complete-coverage features ship in the first public release versus
  follow-up releases.
- Whether recent-action ranking is desirable.
- Whether pipeline creation should remain a text-based advanced feature or gain
  a visual builder after the grammar stabilizes.
