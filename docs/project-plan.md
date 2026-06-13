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
- A Configuration menu for user-created settings, storage, reset, and portable
  export or backup
- Discoverable management of Clop's native saved and inline pipelines instead
  of a separate workflow-owned recipe system
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

Configure it to accept multiple files, URLs, and text. Treat Alfred's argument
as explicit input: structured file and URL values remain exact items, while
text may contain extractable paths or URLs. Do not combine inputs into a
comma-delimited string because commas are valid in filenames and URLs.

### Finder selection

Use a small injectable AppleScript/JXA bridge only when an External Trigger
request explicitly asks for `finderSelection`. The bridge obtains Finder's
selected paths and returns them to Swift as structured input. If Finder has no
selection, notify the user and stop; do not fall back to the clipboard.

Alfred Hotkey and Universal Action objects should pass their macOS selection
directly as explicit input. This may be files, URLs, or selected text and does
not require the Finder bridge.

### Clipboard

Swift should inspect `NSPasteboard` in this order:

1. native file URLs;
2. text containing paths or supported URLs.

Native files take precedence and must not be combined with the clipboard's
text representation because applications often publish the same selection in
several pasteboard formats.

Text extraction is intentionally broader than one item per line:

- extract every valid `http` or `https` URL from surrounding prose;
- accept quoted or backtick-wrapped local paths containing spaces;
- accept unquoted absolute paths and `~/...` paths when they contain no spaces;
- accept `file://` URLs as local paths;
- ignore unrelated prose and preserve the order of recognized inputs.

Structured explicit input is not prose. Every item supplied in the typed
External Trigger request is treated as one exact file, folder, or URL value.

### Unified External Trigger

Provide one public External Trigger with the stable identifier `clop`. The
project is unreleased, so replace the development-only `paths` trigger without
a compatibility alias. Keep the Script Filter's `mainMenu` inbound External
Trigger as an internal workflow navigation mechanism, not part of the public
API.

The primary public interface is a line-based shorthand that uses visible
workflow action names and American-English spelling. Bare `finder`,
`clipboard`, paths, folders, or URLs open the main menu. Directive forms use a
blank line to separate configuration from exact input:

```text
crop:

finder
```

```text
execute: Crop / Resize
size: 16:9
smart crop: true

/path/one image.png
/path/two image.png
```

Each explicit input line is one exact file, folder, or URL value. The blank
separator prevents directive syntax from conflicting with URL schemes, aspect
ratios, spaces, or punctuation in inputs. Omitted optional booleans default to
false unless a future field explicitly inherits a workflow setting. Required
action values such as crop size remain required when no global default exists.
Global execution settings such as copying results and recursive folder
processing continue to resolve through `Environment`; shorthand does not
duplicate them as per-request fields unless the product later deliberately
adds typed overrides.

Menu shortcuts mirror the workflow:

- `optimize:`
- `crop:`
- `downscale:`
- `convert image:`, `convert video:`, and `convert audio:`
- `crop pdf:`
- `uncrop pdf:`
- `strip metadata:`

`menu: ACTION` accepts the visible workflow action name. `execute: ACTION`
builds a complete typed action request. Actions whose execution parameter
model is not implemented must fail clearly rather than accepting speculative
syntax.

The shorthand parser immediately produces the same typed request used by the
rest of the workflow. Input acquisition and routing remain independent typed
choices:

- `clipboard`: inspect the current clipboard dynamically;
- `finderSelection`: ask Finder for its selected items;
- `explicit`: classify the supplied exact `items`;
- `menu`: open the main action menu or one action's parameter menu;
- `execute`: run one complete typed operation without showing Alfred.

Saved and inline Clop pipelines are typed actions within `menu` or `execute`;
they do not introduce a separate workflow route or recipe identifier.

Typed JSON remains an advanced compatibility API for integrations that need a
versioned structured contract. It is decoded into the same `ClopRequest`
model; it does not maintain a second routing or execution implementation.

Normal callers should omit `version`. An omitted version means "use the current
request contract implemented by this installed workflow," so ordinary
automations follow compatible workflow improvements without maintenance.

An explicit `"version": 1` pins the caller to the version 1 contract and
remains available for integrations that require a stable compatibility target.
Explicit versions are authoritative: unsupported numbers are rejected
visibly, and null or incorrectly typed versions are decoding errors. Evolve
the unversioned current contract additively whenever practical. Add
version-specific decoding only when a genuinely incompatible change makes it
necessary.

Use `items`, not `paths`, because explicit input may include local files,
folders, and remote URLs.

Open the main menu for clipboard content with shorthand:

```text
clipboard
```

The equivalent typed JSON is:

```json
{
  "input": {
    "source": "clipboard"
  },
  "route": {
    "type": "menu"
  }
}
```

Open Crop / Resize for Finder's current selection with shorthand:

```text
crop:

finder
```

The equivalent typed JSON is:

```json
{
  "input": {
    "source": "finderSelection"
  },
  "route": {
    "type": "menu",
    "action": "crop"
  }
}
```

Execute a complete operation for explicit mixed input with shorthand:

```text
execute: Optimize
aggressive: false

/path/one image.png
/path/media folder
https://example.com/video.mp4
```

The equivalent typed JSON is:

```json
{
  "input": {
    "source": "explicit",
    "items": [
      "/path/one image.png",
      "/path/media folder",
      "https://example.com/video.mp4"
    ]
  },
  "route": {
    "type": "execute",
    "action": {
      "type": "optimise",
      "aggressive": false
    }
  }
}
```

A `menu` route without an action opens the main menu. A `menu` route with an
action opens that action's clean parameter menu. Action parameter values are
not part of a menu request; if accidentally present, ignore them. An `execute`
route requires a complete typed action. Do not infer the route from missing
fields or supplied parameter values.

Automation uses the same `InputCollector`, capability validation,
configuration resolution, command builder, and execution path as interactive
results. Successful execution stays quiet while Clop's configured UI may show
progress and results; failures produce a visible notification. Automation
inherits workflow execution settings. Clop pipelines retain the behavior
defined by Clop and accept only the shared CLI options supported by
`pipeline run`.

### Hotkeys

Provide six configurable Hotkey objects as thin predefined requests into the
same input and routing pipeline:

1. Open the main menu for clipboard input.
2. Open the main menu for Alfred-selected input.
3. Optimize clipboard input.
4. Aggressively optimize clipboard input.
5. Optimize Alfred-selected input.
6. Aggressively optimize Alfred-selected input.

The selected-input Hotkeys use the files, URLs, or text passed by Alfred; they
do not invoke the Finder-selection bridge. Hotkeys must not duplicate input,
capability, or execution logic.

### URLs

Accept only `http` and `https` remote URLs. Reject URLs containing credentials.
Preserve query strings and fragments. Pass recognized URLs directly to Clop;
the workflow should not download them.

Infer a media kind from a recognizable URL path extension when possible.
Extensionless and otherwise unclear URLs remain ambiguous rather than
unsupported. For ambiguous input, show documented URL-capable actions and add
concise media requirements only to actions whose validity depends on the
unknown type. Do not add this explanatory text when the input types are clear.

### Folders

Inspect folder contents to derive menu capabilities. The `recursiveFolders`
workflow checkbox controls both inspection depth and whether supported Clop
commands receive `--recursive`:

- disabled: inspect only immediate contents;
- enabled: descend into ordinary subdirectories.

Use one budget of 500 visible filesystem entries per input folder, counting
both inspected files and traversed directories. Ignore hidden entries. Do not
descend into macOS packages or directory symlinks, and do not follow symlinks
while scanning.

When inspection completes within the budget, derive actions from the supported
media found. An empty folder returns one non-executable item explaining that
the folder is empty. A folder containing no Clop-compatible files returns one
non-executable item explaining that no supported content was found. An
unreadable folder returns an error.

When the 500-entry budget is reached before inspection completes, mark the
folder ambiguous. Show documented folder-capable actions and add concise media
requirements only where needed. The budget is an internal safety threshold,
not user configuration.

### Validation

- standardize and resolve file URLs;
- preserve the original path for display;
- reject missing paths with a visible Alfred item;
- identify directories separately;
- determine media type with `UTType`, then extension fallback;
- deduplicate paths without changing user order;
- extract valid inputs from clipboard and Alfred-provided text;
- validate remote URLs without requiring local existence or downloading them;
- reject unsupported schemes and credential-bearing URLs;
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

For ambiguous URLs or budget-limited folders, show actions documented for that
broad input type rather than removing potentially valid choices. Add concise
media requirements only to affected results and let typed validation or Clop
report the final incompatibility.

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
mandatory wizard. Aggressive Optimize is not a separate top-level action;
Command-Return will provide that override on Optimize.

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
relevant Convert menu. Add and remove them there; do not duplicate preset
management in Configuration.

Portable workflow settings storage:

- store one versioned `settings.json` document containing action presets,
  the configured output template, and future portable workflow-owned settings;
- if the `settingsPath` workflow setting is empty, store `settings.json` in
  `alfred_workflow_data`;
- if `settingsPath` points to a custom folder, read and write
  `<settingsPath>/settings.json`;
- migrate the existing versioned `presets.json` content explicitly and
  non-destructively when introducing the shared document;
- temporarily recognize the old `presetsPath` variable while moving users to
  `settingsPath`;
- create the document when absent and use an existing compatible file when
  present;
- use a versioned JSON schema and atomic writes;
- never store user settings in the workflow bundle itself;
- when the configured location changes, do not silently copy, merge, or delete
  files. Offer an explicit pending settings migration.

The custom folder is the simple cross-Mac strategy: users may choose an iCloud
Drive, Dropbox, or other locally available synchronized directory.

Do not create a separate workflow recipe system. Clop saved and inline
pipelines are the multi-step automation feature. Keep pipeline expressions
opaque until their grammar is stable enough to model safely.

### Configuration menu

Add a discoverable `Configuration` action to the main menu. It is separate
from Alfred's static workflow configuration and must remain available without
files to process.

Expected responsibilities:

- configure the active output template through one live editor that offers
  prefix and suffix choices for plain text, accepts advanced templates
  directly, validates while typing, and shows the raw template beside an
  example output path;
- keep a concise token reference on the editor screen through Alfred Large
  Type. Advertise source path, filename, date, time, random, and incrementing
  tokens there. Do not advertise `%e` or operation-specific advanced tokens;
- show a pending settings migration only when one requires action; remove the
  migration action from the main action menu once Configuration owns it;
- reset the workflow-owned output template to `%P/%f-clop` through explicit
  confirmation while preserving action presets and Alfred's static
  preferences;
- show `Reset output template` only when the active template differs from the
  built-in value;
- offer a separate confirmed `Remove all action presets` action only when at
  least one preset exists. Never couple global preset removal to output reset;
- export or back up portable user-created settings to a chosen location;
- restore or import settings only after conflict, merge, schema-version, and
  overwrite behavior has been designed;
- provide an explicit maintenance action to remove workflow-owned materialized
  clipboard images from the workflow cache and temporary fallback directory.
  Keep this separate from settings reset, import, and export because cached
  images are disposable runtime data. Show the action only when matching
  cached images exist, include the image count and space used, require
  confirmation, and report the number of files and space reclaimed.

When a pending migration blocks an inline save, Return on the explicit
`Move existing settings` row should perform the non-destructive move directly
and resume the interrupted menu operation without a second confirmation.
Otherwise, pending migration is managed from Configuration and omitted when
there is nothing to migrate.

Use the precise label `Reset output template` and state the built-in template
that will be restored. The separate preset-removal confirmation must state the
number of presets that will be removed. Individual preset removal remains in
each action menu. Export and backup cover portable user-created data, not
Alfred preferences, Clop preferences, workflow binaries, or caches. Cache
cleanup is a separate maintenance operation and must delete only files created
by this workflow's clipboard image materializer.

The output-template editor follows these rules:

- plain text produces two complete safe choices: a suffix beside the original
  and a prefix beside the original;
- input containing `%`, `/`, or beginning with `~` is treated only as an
  advanced template;
- templates must identify a predictable destination with `%P/`, `~/`, or an
  absolute path and must end in a filename containing a filename-producing
  token;
- leading `~/` is stored without expansion for portable settings, then
  expanded for preview, preflight, and execution;
- `%e` and literal terminal file extensions are rejected because Clop appends
  the resulting extension;
- `%z`, `%s`, `%x`, and `%q` remain accepted for advanced users but are omitted
  from the workflow's concise Large Type reference because they are meaningful
  only for particular operations.

Design the shared settings document and conflict policy before implementing
the menu so output settings and presets do not require another incompatible
storage transition.

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
| Command-Return | Invert the configured aggressive-processing default where supported |
| Option-Return | Enable the action's documented alternate processing mode where one exists |
| Command-Option-Return | Combine the aggressive-default inversion with the alternate mode when both are supported |
| Shift-Return | Invert the configured Preserve Original behavior |
| Control-Return | Save a typed value as a preset, or request removal of an existing preset |

Do not hard-code "Command means aggressive" at execution time. Encode the
modifier's resolved `OperationRequest` directly in that Alfred item's `mods`
JSON. This makes the subtitle and actual operation impossible to drift apart.

Modifiers keep one meaning across top-level and parameter menus, but only
appear where applicable. Unsupported modifiers must not silently acquire a
different action-specific meaning.

Configuration is an administrative surface rather than an operation menu. Its
reset item may therefore use Command-Return for the clearly labeled global
preset-reset confirmation without changing Command's aggressive inversion
meaning on executable media actions.

Do not add a separate Aggressive Optimize action to the menu. Return uses the
configured Standard or Aggressive default, while Command-Return resolves the
opposite behavior and states it accurately in the subtitle.

For Crop / Resize results that perform an actual crop, Option-Return enables
Smart Crop, centering the crop around detected visual features.
Command-Option-Return combines the configured aggressive-default inversion and
Smart Crop when the selected input and Clop command support both. Do not offer
Smart Crop modifiers for resize-only forms such as a long edge, fixed width,
or fixed height because those forms do not choose crop positioning.

Option is therefore reserved for a clearly labeled action-specific alternate
processing mode, not for preserving the original.

Shift is the workflow-wide Preserve Original inversion. When the global
checkbox is off, Shift uses the configured output template. When it is on,
Shift omits `--output` and replaces in place for that run. It must encode the
resolved `OutputBehavior` in the item's `OperationRequest`; it must not rely on
a later execution-time guess. Do not expose Shift-Return until the output
policy has been implemented and tested.

Modifier effects are additive when Alfred exposes the combination and the
action supports every requested effect. Command-Shift inverts both the
aggressive and preservation defaults. Option-Shift combines the alternate mode
with the preservation inversion. Command-Option-Shift applies all three
effects. Each combined modifier needs an accurate subtitle and a fully
resolved request. Unsupported combinations must be omitted rather than
silently dropping one effect.

Control-Return is valid only when the selected item contains complete
parameters that can be saved and replayed. On an existing preset it must route
to a confirmation step before removal.

Do not reserve modifiers for width/height syntax. Use `w128` and `h720` in the
query grammar so modifier keys remain available for consistent workflow-wide
behavior.

## Workflow configuration

Suggested Alfred user configuration:

| Setting | Initial values |
| --- | --- |
| Clop CLI path | Auto-detect, optional override |
| Settings path | Empty for `alfred_workflow_data`, or a custom folder |
| Preserve original files | Off / On; Shift inverts for one run |
| Default optimization | Standard / Aggressive |
| Show Clop UI | On / Off |
| Completion notifications | Off / On |
| Error notifications | On / Off |
| Ensure result is copied | On / Off |
| Recurse into folders | On / Off |
| Clipboard image retention | 1-15 days; default 7 |
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
| Conversion engine | App-backed / Legacy local when available |

For output behavior, the static Alfred panel exposes only the Preserve Original
toggle. The interactive Configuration menu owns how preservation works. Its
built-in default template is `%P/%f-clop`, so enabling preservation works
immediately without prior setup. Plain typed text offers complete prefix and
suffix templates beside the original; advanced templates may select another
absolute or home-relative destination. Do not expose permanently visible
dependent folder, suffix, and template fields in Alfred's non-dynamic panel.

An output template preserves the original by writing elsewhere. Alfred Clop
does not implement workflow-managed backup copies.

The `copyResult` workflow checkbox should resolve into
`ExecutionOptions.copyResult`. When enabled, supported commands must receive
Clop's explicit `--copy` option. Do not assume that showing Clop's floating UI
also guarantees clipboard copying; `--gui` and `--copy` are independent CLI
options.

The `recursiveFolders` checkbox should resolve once and control both folder
inspection depth and `--recursive` command construction.

Pass `--skip-errors` automatically to every supported batch-capable command.
Do not expose it as a user preference. Continue to inspect structured results
and report skipped or failed inputs according to the notification settings.

Completion and error notifications are independent preferences and should be
honored even when Clop's floating UI is enabled. macOS remains responsible for
Focus and notification presentation.

Clipboard image retention applies only to workflow-owned materialized raw
clipboard images. It accepts 1 through 15 days and defaults to 7.

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
3. Validate and preflight any configured output template.
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
- exact explicit-input classification
- prose extraction for URLs and local paths
- native clipboard file precedence over text
- remote URL validation, including credentials, queries, and fragments
- folder inspection depth, exclusions, and the 500-entry budget
- empty, unsupported-only, unreadable, and ambiguous folders
- typed External Trigger request decoding and route dispatch
- empty Finder selection without clipboard fallback
- mixed-selection capability intersection
- ambiguous-input capability presentation
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
- clipboard prose containing multiple URLs and quoted paths
- Universal Action with multiple files
- Universal Action and selected-input Hotkeys with text or URLs
- all six configurable Hotkeys
- public `clop` trigger routes for clipboard, Finder selection, and explicit
  input
- filenames containing spaces, quotes, commas, and Unicode
- every modifier
- fixed instructional-row placement alongside Alfred-learned preset ordering
- folder recursion, the inspection budget, and type filters
- clear and ambiguous URL inputs
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

- Normalize Universal Action, Finder, clipboard, and explicit inputs.
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

- Replace the development-only `paths` trigger with the typed public `clop`
  request dispatcher.
- Add unified clipboard, Finder-selection, and explicit input acquisition.
- Classify files, folders, and URLs through `InputCollector`.
- Extract paths and URLs from clipboard and Alfred-provided prose.
- Add bounded folder inspection and wire `recursiveFolders`.
- Route typed requests to the main menu, parameter menus, or quiet execution.
- Add the six predefined configurable Hotkey entry points.
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
- Preserve originals only through a validated `--output` template; do not
  implement workflow-managed backups.
- Keep empty parameter menus instructional rather than filling them with
  workflow-authored presets.
- Define an action preset as one normalized typed action with no inputs, custom
  name, or execution-setting overrides.
- Keep action presets inside their relevant parameter submenu; use stable
  Alfred item UIDs for learned relative ordering and keep the instructional
  item fixed at the top.
- Use Control-Return to save a typed value and to request confirmed removal of
  an existing preset.
- Use Clop pipelines instead of a separate workflow-owned recipe system.
- Store portable workflow settings and action presets in one versioned
  `settings.json`, using `alfred_workflow_data` by default or the configured
  custom folder.
- Use `%P/%f-clop` as the built-in original-preservation template.
- Make Preserve Original and aggressive processing configurable defaults;
  Shift-Return and Command-Return invert them for one run.
- Pass `--skip-errors` automatically where supported rather than exposing a
  preference.
- Keep completion and error notifications independent.
- Use one typed JSON automation contract for headless execution; never parse
  comma-separated paths or shell-like request strings.
- Use one public `clop` External Trigger for interactive menus and quiet
  execution; keep `mainMenu` internal.
- Keep input source separate from route: clipboard, Finder selection, or
  explicit items may target a menu or complete action, including a Clop
  pipeline action.
- Let `InputCollector` classify files, folders, and `http`/`https` URLs;
  extract supported inputs from prose only for clipboard and Alfred text.
- Prefer native clipboard files over text and do not merge pasteboard formats.
- Inspect at most 500 visible entries per folder, controlled by the
  `recursiveFolders` setting; treat budget-limited scans as ambiguous.
- Use `menu` for both the main action menu and action parameter menus; ignore
  accidental action values on menu routes.
- Inherit workflow execution settings for automation; Clop pipelines retain
  their own step behavior and receive only supported shared execution options.
- Provide configurable Hotkeys for menu, standard optimization, and aggressive
  optimization using clipboard or Alfred's selected input.
- Keep `--gui` and `--copy` as independent execution options.
- Target complete supported CLI coverage, staged across releases.
- Keep pipeline expressions opaque until Clop exposes a stable full grammar.

## Open decisions

- Minimum macOS version.
- Whether the released binary is universal or Apple Silicon only.
- Whether Clop should be launched automatically when needed.
- Whether headless automation should optionally return structured result JSON
  to callers in addition to quiet execution.
- Which complete-coverage features ship in the first public release versus
  follow-up releases.
- Whether recent-action ranking is desirable.
- Whether pipeline creation should remain a text-based advanced feature or gain
  a visual builder after the grammar stabilizes.
