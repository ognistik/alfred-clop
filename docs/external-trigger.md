# External Trigger

Alfred Clop exposes one External Trigger:

```text
workflow: com.aft.clop
trigger: clop
```

The trigger accepts a line-based shorthand intended for people and a typed
JSON request intended for advanced integrations. Both formats decode into the
same internal `ClopRequest` model and use the same input validation, action
capabilities, workflow settings, and execution path.

## Input

Bare input opens the main action menu:

```text
finder
```

```text
clipboard
```

```text
/path/one image.jpg
/path/two image.jpg
https://example.com/video.mp4
```

Use exactly one input source:

- `finder` reads Finder's current selection;
- `clipboard` reads the current clipboard;
- otherwise, each non-empty line is one exact local path, folder, or HTTP/HTTPS
  URL.

Do not combine `finder` or `clipboard` with explicit items.

## Action Menus

An action shortcut followed by a blank line opens that action's parameter menu:

```text
crop:

finder
```

Supported shortcuts:

```text
optimize:
crop:
downscale:
convert image:
convert video:
convert audio:
crop pdf:
uncrop pdf:
strip metadata:
```

The explicit form uses the visible workflow action name:

```text
menu: Crop / Resize

/path/one.jpg
/path/two.jpg
```

Action and parameter names are case-insensitive. The blank line between
directives and input is required.

## Configuration

Open Configuration directly while preserving an input source:

```text
menu: Configuration

clipboard
```

```text
menu: Configuration

finder
```

The menu opens with `:` in Alfred. Removing the colon returns to the processing
actions for the same collected input. Type or autocomplete `:template ` to
edit the output template.

The Workflow Settings result opens Alfred's workflow configuration with
Return and reveals the active settings folder with Command-Return. It also
represents the real `settings.json` file, so Alfred Quick Look and file actions
remain available.

## Execution

Use `execute:` with a visible workflow action name:

```text
execute: Optimize

/path/one.jpg
/path/two.jpg
```

Optional booleans default to `false` when omitted:

```text
execute: Optimize
aggressive: true

clipboard
```

Accepted boolean values are `true`, `false`, `yes`, `no`, `on`, and `off`.

Media-specific Optimize controls are also supported. They use explicit fields
or the same compact controls grammar as the Alfred menu:

```text
execute: Optimize
media: video
controls: 70, sw, m
playback speed: 1.5

/path/movie.mp4
```

Supported media controls:

- image: `compression: 70`, `compression: ad`, or `controls: 70`
- video: `compression: 70`, `compression: au`, `encoder: sw`,
  `remove audio: true`, `playback speed: 2`, or `controls: 70 sw m 2x`
- PDF: `dpi: 150`, `dpi: ad`, or `controls: dpi 150`
- audio: `compression: 70`, `bitrate: 128`, or `controls: b128`

The compact Optimize grammar accepts spaces or commas between tokens. Video
shorthand uses `5-100/au` for compression, `hw/sw/ll/ad` for encoder, `m` for
mute, and `2x` for speed. Full words such as `auto`, `software`, `lossless`,
`adaptive`, and `mute` remain accepted. External Trigger execution never uses
workflow action presets by name.

Crop / Resize requires `size`. It accepts the same values as the workflow menu:

```text
execute: Crop / Resize
size: 16:9
controls: sc

finder
```

`sc` / `smart-crop` enables Clop's Smart Crop feature for centering the crop
around detected image features. It is only valid with exact dimensions or aspect
ratios. Omit it to leave Smart Crop off. Supported size examples include
`1200x630`, `16:9`, `1920`, `w128`, `h720`, `128x0`, and `0x720`.

Crop / Resize also accepts the workflow menu's compact controls grammar:

```text
execute: Crop / Resize
size: 16:9
controls: sc no-ad m

/path/movie.mp4
```

Supported controls are `sc` / `smart-crop`, `ad` / `adaptive`, `no-ad` /
`no-adaptive`, and `m` / `mute`. In the interactive workflow, `no-ad` is
treated as an advanced explicit override because Clop's crop defaults already
keep adaptive optimization off unless requested. Explicit booleans are also
available for adaptive optimization and audio:

```text
execute: Crop / Resize
size: w128
adaptive: true
remove audio: true

/path/movie.mp4
```

Use either adaptive or no-adaptive, not both. `mute: true` and
`remove audio: true` are equivalent.

Downscale requires `factor`. It accepts the same values as the workflow menu:

```text
execute: Downscale
factor: 50

/path/photo.jpg
/path/audio.m4a
```

Supported factor examples include `50`, `50%`, `0.5`, `75%`, and `0.75`.
Whole numbers from `2` through `99` are interpreted as percentages. Values
must be greater than `0` and less than `100%`; bare `1`, `100%`, and larger
values are rejected.

Convert execution requires `format`. The generic `Convert` action infers
image, video, or audio from the format; media-specific action names can also
be used:

```text
execute: Convert Audio
format: mp3
bitrate: 128

/path/recording.wav
```

Image and MP4 conversion accept `compression`; MP4 also accepts `auto`. Audio
accepts `compression` or `bitrate`.

Crop PDF requires exactly one target: `ratio`, `device`, or `paper size`.
`ratio` accepts ratio or resolution values such as `16:9` and `1200x630`.
`device` and `paper size` accept names from Clop's current `crop-pdf`
device and paper lists.

```text
execute: Crop PDF
ratio: 16:9
page layout: landscape
extend: true

/path/slides.pdf
```

```text
execute: Crop PDF
device: iPad mini 6 & 7
controls: portrait extend

/path/book.pdf
```

```text
execute: Crop PDF
paper size: A4

/path/document.pdf
```

Supported Crop PDF controls are `a` / `auto`, `p` / `portrait`,
`l` / `landscape`, and `e` / `extend`. Omit `extend` to use Clop's normal
crop behavior.

Pipeline execution accepts one `pipeline` value. It can be a saved Clop
pipeline name or inline Clop pipeline steps:

```text
execute: Pipeline
pipeline: To WebP

/path/photo.png
```

```text
execute: Pipeline
pipeline: crop(width: 1600) -> convert(to: webp)
skip: true
hide: true

/path/photo.png
```

For inline steps, omitting `skip` makes Alfred Clop optimize first and then run
the written steps. `skip: true` runs only the written steps. `hide: true`
hides Clop's floating result UI by suppressing the runtime UI flag. `skip` is
not accepted for saved pipeline names because saved pipelines already carry
their own Clop optimization setting. The older `name` field remains accepted
as a compatibility alias, but new requests should use `pipeline`.

### Current Grammar

This table is the complete shorthand execution grammar currently implemented:

| Action | Parameters | Omitted behavior |
| --- | --- | --- |
| `Optimize` | `aggressive` (optional boolean), optional media-specific controls | Standard optimization |
| `Crop / Resize` | `size` (required), optional compact controls such as `sc`, `ad`, `no-ad`, and `m`; optional adaptive/mute booleans | Smart Crop disabled, Clop defaults for adaptive optimization and audio |
| `Downscale` | `factor` (required) | Uses workflow execution settings |
| `Convert`, `Convert Image`, `Convert Video`, `Convert Audio` | `format` (required), optional compression/bitrate where supported | Uses Clop defaults for that target |
| `Crop PDF` | exactly one of `ratio`, `device`, or `paper size`; optional `page layout`, `extend`, or compact `controls` | Auto layout, crop content |
| `Pipeline` | `pipeline` (required), optional `skip` for inline steps, optional `hide` | Saved pipeline settings, or optimize first for inline steps |
| `Uncrop PDF` | None | Uses workflow execution settings |
| `Strip Metadata` | None | Uses workflow execution settings |

### Defaults And Workflow Settings

Omitting an optional shorthand boolean means `false`. Required values cannot
be omitted unless that action later gains a documented workflow default.

Execution also inherits the workflow's existing global settings without
requiring shorthand fields:

- `copyResult`
- `recursiveFolders`
- completion and error notification preferences

Those settings are resolved by the same typed execution path used by workflow
menus and JSON requests. They are not duplicated as shorthand parameters.

Future optional parameters should follow the same rule: omission uses the
documented workflow or Clop default. Every new field must be added to this
reference when its corresponding operation is implemented.

## AppleScript

Open Crop / Resize for Finder's selection:

```applescript
tell application id "com.runningwithcrayons.Alfred"
  run trigger "clop" in workflow "com.aft.clop" with argument "crop:" & linefeed & linefeed & "finder"
end tell
```

Open the main menu for multiple files:

```applescript
set request to "/path/one image.jpg" & linefeed & "/path/two image.jpg"

tell application id "com.runningwithcrayons.Alfred"
  run trigger "clop" in workflow "com.aft.clop" with argument request
end tell
```

Execute a crop for multiple files:

```applescript
set request to "execute: Crop / Resize" & linefeed & ¬
  "size: 16:9" & linefeed & linefeed & ¬
  "/path/one image.jpg" & linefeed & ¬
  "/path/two image.jpg"

tell application id "com.runningwithcrayons.Alfred"
  run trigger "clop" in workflow "com.aft.clop" with argument request
end tell
```

## Typed JSON

Typed JSON remains supported for integrations that need an explicit,
versionable contract. It is an advanced form of the same request, not a
separate execution implementation:

```json
{
  "version": 1,
  "input": {
    "source": "finderSelection"
  },
  "route": {
    "type": "menu",
    "action": "crop"
  }
}
```

Configuration uses an explicit menu destination:

```json
{
  "input": {
    "source": "clipboard"
  },
  "route": {
    "type": "menu",
    "destination": "configuration"
  }
}
```
