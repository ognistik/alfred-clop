# External Trigger reference

Clop for Alfred exposes one public External Trigger:

```text
workflow: com.aft.clop
trigger: clop
```

The trigger accepts two request formats:

- a line-based shorthand for scripts, AppleScript, Shortcuts, Keyboard Maestro,
  and humans;
- typed JSON matching the workflow’s `ClopRequest` model.

Both formats use the same validation and execution path as the interactive
workflow.

## Request structure

Most shorthand requests have two blocks:

```text
directive
optional parameter: value
optional parameter: value

input
input
input
```

The blank line between directives/parameters and input is required whenever a
directive is present.

Bare input has no directive and opens the main action menu.

## Input sources

Use exactly one input source per request.

| Input | Meaning |
| --- | --- |
| `finder` | Read Finder’s current selection. |
| `clipboard` | Read the current clipboard. |
| explicit lines | Treat each non-empty line as one exact path, folder, or HTTP/HTTPS URL. |

Examples:

```text
finder
```

```text
clipboard
```

```text
/Users/me/Desktop/first image.jpg
/Users/me/Desktop/second image.jpg
https://example.com/video.mp4
```

Do not combine `finder` or `clipboard` with explicit paths or URLs.

Explicit lines preserve significant spaces. This allows paths such as:

```text
/Users/me/Desktop/ leading-space.jpg
/Users/me/Desktop/trailing-space.jpg 
```

## Open the main menu

Pass only input:

```text
clipboard
```

```text
/Users/me/Desktop/photo.png
```

## Open an action menu

Use an action shortcut followed by a blank line and input:

```text
crop:

finder
```

Supported shortcuts:

| Shortcut | Opens |
| --- | --- |
| `optimize:` | Optimize |
| `crop:` | Crop / Resize |
| `downscale:` | Downscale |
| `convert image:` | Convert Image |
| `convert video:` | Convert Video |
| `convert audio:` | Convert Audio |
| `crop pdf:` | Crop PDF |
| `uncrop pdf:` | Uncrop PDF |
| `strip metadata:` | Strip Metadata |

You can also use the explicit `menu:` form with the visible workflow action
name. Matching is case-insensitive.

```text
menu: Crop / Resize

clipboard
```

## Open Configuration

Use:

```text
menu: Configuration

clipboard
```

Configuration opens in Alfred with the same `:` namespace used by the
interactive workflow.

## Execute an action

Use `execute:` with the visible action name:

```text
execute: Optimize

/Users/me/Desktop/photo.png
```

Direct execution runs headlessly through Alfred. Notifications follow the
workflow’s completion/error notification settings.

Boolean values accept:

```text
true
false
yes
no
on
off
```

## Output overrides

Execution requests can override the configured output behavior for one run.

| Parameter | Values | Meaning |
| --- | --- | --- |
| `output` | `template` | Use the configured output template. |
| `output` | `false`, `off`, `no` | Disable template output for this run. |
| `output template` | template string | Use a custom output template for this run. |

Examples:

```text
execute: Optimize
output: template

/Users/me/Desktop/photo.png
```

```text
execute: Convert
format: mp3
output template: %P/%f-podcast

/Users/me/Desktop/audio.wav
```

`output` and `output template` are execute-only parameters. They are rejected
for `menu:` requests.

## Optimize

Basic optimize:

```text
execute: Optimize

/Users/me/Desktop/photo.png
```

Aggressive optimize:

```text
execute: Optimize
aggressive: yes

clipboard
```

Media-specific Optimize controls are also supported.

```text
execute: Optimize
media: video
controls: 70, sw, m
playback speed: 2

/Users/me/Desktop/movie.mp4
```

Supported media values:

```text
image
video
audio
pdf
```

Supported controls:

| Media | Parameters |
| --- | --- |
| image | `compression: 70`, `compression: ad`, or `controls: 70` |
| video | `compression: 70`, `compression: au`, `encoder: sw`, `remove audio: true`, `playback speed: 2`, or `controls: 70 sw m 2x` |
| audio | `compression: 70`, `bitrate: 128`, or `controls: b128` |
| pdf | `dpi: 150`, `dpi: ad`, or `controls: dpi 150` |

The compact Optimize grammar accepts spaces or commas between tokens. Video
shorthand supports:

- `5` through `100`, or `au`, for compression;
- `hw`, `sw`, `ll`, or `ad` for encoder;
- `m` for mute/remove audio;
- `2x` style values for playback speed.

Full words such as `auto`, `software`, `lossless`, `adaptive`, and `mute` are
also accepted where they apply.

Preset names are not accepted in External Trigger execution. Use explicit
parameters instead.

## Crop / Resize

Crop / Resize requires `size`.

```text
execute: Crop / Resize
size: 16:9
controls: sc

finder
```

Supported size examples:

```text
1200x630
16:9
1920
w128
h720
128x0
0x720
```

`32:18` normalizes to `16:9`. `w128` normalizes to `128x0`; `h720` normalizes
to `0x720`.

Supported controls:

| Control | Meaning |
| --- | --- |
| `sc`, `smart-crop` | Enable Smart Crop. Valid only with exact dimensions or aspect ratios. |
| `ad`, `adaptive` | Enable adaptive optimization after crop. |
| `no-ad`, `no-adaptive` | Explicitly disable adaptive optimization. |
| `m`, `mute` | Remove audio from video output. |

Example:

```text
execute: Crop / Resize
size: 16:9
controls: sc, no-ad, m

/Users/me/Desktop/movie.mp4
```

Explicit booleans are also available:

```text
execute: Crop / Resize
size: w128
adaptive: true
remove audio: yes

/Users/me/Desktop/movie.mp4
```

`mute: true` and `remove audio: true` are equivalent. Use either adaptive or
no-adaptive, not both.

## Downscale

Downscale requires `factor`.

```text
execute: Downscale
factor: 50%

/Users/me/Desktop/photo.jpg
```

Accepted factor examples:

```text
50
50%
0.5
75%
0.75
```

Whole numbers from `2` through `99` are interpreted as percentages. Values must
be greater than `0` and less than `100%`; `1`, `100%`, and larger values are
rejected.

Optional controls:

```text
execute: Downscale
factor: 50%
controls: adaptive mute

/Users/me/Desktop/movie.mp4
```

Supported controls are `adaptive`, `no-adaptive`, `mute`, and their compact
forms where accepted by the interactive menu.

## Convert

Convert requires `format`.

Media-specific actions:

```text
execute: Convert Image
format: jpg
compression: 75

/Users/me/Desktop/image.png
```

```text
execute: Convert Audio
format: mp3
bitrate: 128

/Users/me/Desktop/audio.wav
```

Generic `Convert` infers media from the format:

```text
execute: Convert
format: webm

/Users/me/Desktop/video.mov
```

Common optional settings:

| Parameter | Applies to |
| --- | --- |
| `compression` | image, video, audio where Clop supports compression |
| `bitrate` | audio |

`jpg` normalizes to `jpeg`.

## Crop PDF

Crop PDF requires exactly one target kind:

- `ratio`
- `device`
- `paper size`

Examples:

```text
execute: Crop PDF
ratio: 32:18
controls: landscape extend

/Users/me/Desktop/book.pdf
```

```text
execute: Crop PDF
device: iPad mini 6 & 7
page layout: portrait

/Users/me/Desktop/book.pdf
```

```text
execute: Crop PDF
paper size: A4
extend: true

/Users/me/Desktop/book.pdf
```

Supported controls:

| Parameter/control | Meaning |
| --- | --- |
| `page layout: portrait` | Use portrait layout. |
| `page layout: landscape` | Use landscape layout. |
| `controls: portrait` | Compact portrait layout. |
| `controls: landscape` | Compact landscape layout. |
| `extend: true` | Extend pages to the target. |
| `controls: extend` | Compact extend flag. |

Ratios normalize, so `32:18` becomes `16:9`.

## Uncrop PDF and Strip Metadata

These actions do not require extra parameters.

```text
execute: Uncrop PDF

/Users/me/Desktop/book.pdf
```

```text
execute: Strip Metadata

/Users/me/Desktop/photo.jpg
```

## Pipeline

Pipeline execution accepts one `pipeline` value. It can be a saved Clop
pipeline name or inline Clop pipeline steps.

Saved pipeline:

```text
execute: Pipeline
pipeline: To WebP
hide: true

/Users/me/Desktop/photo.png
```

Inline pipeline:

```text
execute: Pipeline
pipeline: crop(width: 1600) -> optimize -> convert(to: webp)
opt: true
hide: true

/Users/me/Desktop/photo.png
```

Supported parameters:

| Parameter | Meaning |
| --- | --- |
| `pipeline` | Saved pipeline name or inline pipeline steps. |
| `name` | Compatibility alias for `pipeline`. Prefer `pipeline` in new requests. |
| `opt` | Optimize before inline pipeline steps. Only valid for inline steps. |
| `skip` | Compatibility alias for skipping the automatic optimize step where supported. |
| `hide` | Hide Clop result UI for this pipeline run. |

Known newer Clop step names such as `normalize` are treated as inline pipeline
steps.

## Typed JSON

Typed JSON remains supported for integrations that prefer the internal request
model.

Example:

```json
{
  "version": 1,
  "input": {
    "type": "clipboard"
  },
  "route": {
    "type": "menu",
    "action": "crop"
  }
}
```

The current contract omits `version` when encoding new requests, but missing
version still decodes as the current contract. Invalid future versions are
reported visibly.

## AppleScript examples

Open the menu for Finder selection:

```applescript
tell application id "com.runningwithcrayons.Alfred" to run trigger "clop" in workflow "com.aft.clop" with argument "finder"
```

Execute Optimize on the clipboard:

```applescript
set request to "execute: Optimize" & linefeed & ¬
  "aggressive: yes" & linefeed & linefeed & ¬
  "clipboard"

tell application id "com.runningwithcrayons.Alfred" to run trigger "clop" in workflow "com.aft.clop" with argument request
```

Execute Crop / Resize on explicit files:

```applescript
set request to "execute: Crop / Resize" & linefeed & ¬
  "size: 16:9" & linefeed & ¬
  "controls: sc" & linefeed & linefeed & ¬
  "/Users/me/Desktop/first image.jpg" & linefeed & ¬
  "/Users/me/Desktop/second image.jpg"

tell application id "com.runningwithcrayons.Alfred" to run trigger "clop" in workflow "com.aft.clop" with argument request
```

## Validation errors

Common rejected requests:

| Request problem | Result |
| --- | --- |
| Missing blank line after an action directive | `missingSeparator` |
| `execute: Crop / Resize` without `size` | missing `size` |
| `execute: Downscale` without `factor` | missing `factor` |
| `execute: Convert Image` without `format` | missing `format` |
| `aggressive: maybe` | invalid boolean parameter |
| `output template:` with an empty value | missing `output template` |
| `menu: Optimize` with `output: false` | execute-only parameter |
| `finder` mixed with explicit paths | mixed input sources |
