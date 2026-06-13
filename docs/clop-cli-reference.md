# Clop CLI Reference

Research date: June 12, 2026

## Target version and method

This reference was verified against the CLI bundled with the locally installed
official Clop release:

```text
Clop app version: 3.0.0
Clop app build: 3.0.0
CLI path: /Applications/Clop.app/Contents/SharedSupport/ClopCLI
CLI architecture: universal (arm64 and x86_64)
```

Clop's CLI has no `--version` option. The containing app's bundle version is
therefore the practical version identifier.

The command hierarchy and option lists below were captured directly with
`clop --help` and `clop help <subcommand>`. Small missing-file probes were also
used to verify that the legacy mixed-type `optimise` syntax and the new JSON
result mode still parse without launching work on real files.

The installed CLI is authoritative for this project. Clop's public GitHub
releases page still reported 2.11.6 as its latest release during this research,
so it should not be used to infer the installed 3.0 CLI surface.

Supporting sources:

- [Clop website](https://lowtechguys.com/clop/)
- [Clop source repository](https://github.com/FuzzyIdeas/Clop)
- [Clop releases](https://github.com/FuzzyIdeas/Clop/releases)

## What changed from the 3.0 beta reference

- `optimise` now documents `image`, `video`, `pdf`, and `audio` subcommands
  with media-specific compression controls.
- `convert` now supports app-backed image, video, and audio conversion.
- Image conversion targets now include JXL, JPEG/JPG, and PNG in addition to
  WebP, AVIF, and HEIC.
- Video conversion supports MP4/H.264, animated GIF, WebM/VP9, hardware HEVC,
  software x265, and AV1 in MKV.
- Audio conversion supports MP3, AAC, M4A, Opus, Ogg, FLAC, WAV, and AIFF.
- New app-backed conversion commands support shared options such as `--json`,
  `--gui`, `--recursive`, `--copy`, and `--output`.
- The old local image converter remains available as a compatibility mode.
- A new `pipeline` command can list, inspect, run, add, and delete Clop
  pipelines.
- `crop-pdf` gained `--extend`, which adds empty paper instead of clipping
  content.
- Device presets now include current iPhone 17, iPad M5, and related families.

## Command overview

| Command | Inputs | Purpose |
| --- | --- | --- |
| `optimise` | images, videos, audio, PDFs, URLs, folders | Optimize mixed inputs or use media-specific controls |
| `crop` | images, videos, PDFs, URLs, folders | Crop and optimize to dimensions or an aspect ratio |
| `downscale` | images, videos, audio, URLs, folders | Scale dimensions, or audio bitrate, by a factor |
| `convert image` | images, URLs, folders | Convert images through Clop |
| `convert video` | videos, URLs, folders | Convert video format or codec through Clop |
| `convert audio` | audio, URLs, folders | Convert audio format through Clop |
| `convert legacy` | images | Locally convert images to AVIF, HEIC, or WebP |
| `crop-pdf` | PDFs or folders | Apply a reversible PDF crop box |
| `uncrop-pdf` | PDFs or folders | Remove a PDF crop box |
| `strip-exif` | images, videos, folders | Remove metadata |
| `pipeline` | supported files and folders | Manage and run saved or inline pipelines |

The spelling is `optimise`, not `optimize`.

## Capability matrix

| Capability | Image | Video | Audio | PDF | URL | Folder |
| --- | --- | --- | --- | --- | --- | --- |
| Optimize | Yes | Yes | Yes | Yes | Yes | Yes |
| Type-specific optimization | Yes | Yes | Yes | Yes | Yes | Yes |
| Crop | Yes | Yes | No | Yes | Yes | Yes |
| Downscale | Yes | Yes | Yes (bitrate) | No | Yes | Yes |
| Convert | Yes | Yes | Yes | No | Yes | Yes |
| Strip metadata | Yes | Yes | No | No | No | Yes |
| Reversible PDF crop | No | No | No | Yes | No | Yes |
| Pipeline | Depends on steps | Depends on steps | Depends on steps | Depends on steps | Not documented | Yes |

Conversion menus must be media-specific because each media kind has a
different target-format list. Mixed image/video/audio selections should not
offer one ambiguous conversion menu unless the workflow deliberately splits
the request by media kind.

## Shared app-backed options

The typed `optimise` and `convert` subcommands share these options:

| Option | Meaning |
| --- | --- |
| `-g`, `--gui` | Show Clop's floating result UI |
| `-n`, `--no-progress` | Suppress progress on standard error |
| `--async` | Submit work in the background |
| `-r`, `--recursive` | Recurse when an input is a folder |
| `-c`, `--copy` | Copy the processed file to the clipboard |
| `-s`, `--skip-errors` | Skip missing files and unreachable URLs |
| `-j`, `--json` | Print structured result JSON |
| `-o`, `--output VALUE` | Choose an output path or filename template |

`crop` and `downscale` retain the broad processing options documented by their
own help, including aggressive optimization, type filters, adaptive image
optimization, and video audio removal.

The broad commands report these default specific types:

```text
webp, avif, heic, jxl, bmp, tiff, png, jpeg, gif,
mov, mp4, webm, mkv, m2v, avi, m4v, mpg,
wav, aiff, mp3, flac, m4a, ogg, pdf
```

Help examples name generic `image`, `video`, and `pdf` filters. The typed
commands make an audio type filter unnecessary for most workflow operations;
if the workflow later exposes raw `--types`, generic `audio` should still be
verified with a real fixture.

## `optimise`

```text
clop optimise <subcommand>
```

Documented subcommands:

| Subcommand | Specific controls |
| --- | --- |
| `optimise image` | `--compression`, `--downscale-factor`, `--crop` |
| `optimise video` | `--compression`, `--encoder`, `--remove-audio`, `--playback-speed-factor`, `--downscale-factor`, `--crop` |
| `optimise pdf` | `--dpi`, `--crop` |
| `optimise audio` | `--compression`, `--bitrate` |

### Image optimization

```sh
clop optimise image --compression 70 photo.png
clop optimise image --compression adaptive --crop 1200x630 photo.png
clop optimise image --downscale-factor 0.5 --json photo.png
```

`--compression` accepts `5` through `100`, where 5 favors quality and 100
favors the smallest file. It also accepts `adaptive`, which lets Clop choose
the best format for each image.

### Video optimization

```sh
clop optimise video --encoder software screencast.mov
clop optimise video --compression auto --remove-audio video.mp4
clop optimise video --playback-speed-factor 2 --downscale-factor 0.5 video.mp4
```

`--encoder` accepts:

- `hardware`: fast, larger files;
- `software`: slow, smaller files;
- `lossless`: no perceptible quality loss;
- `adaptive`: choose the best encoder per file.

Video `--compression` accepts `5` through `100` or `auto`.

### PDF optimization

```sh
clop optimise pdf --dpi adaptive document.pdf
clop optimise pdf --dpi 100 --crop 1200x630 document.pdf
```

`--dpi` accepts `adaptive`, `300`, `250`, `200`, `150`, `100`, `72`, or `48`.
The parent `optimise` help currently shows `--dpi 96` as an example, but the
typed command parser rejects 96. Use the values accepted by
`optimise pdf --help`.

### Audio optimization

```sh
clop optimise audio --compression 70 recording.wav
clop optimise audio --bitrate 128 recording.wav
```

`--bitrate` is expressed in kbps, takes priority over `--compression`, never
increases the source bitrate, and snaps to a bitrate supported by the output
format.

### Legacy mixed-type optimization

The 3.0 help says files and folders can still be passed directly to `optimise`
for mixed-type processing with shared options. The workflow's current form
continues to parse successfully:

```sh
clop optimise --json --no-progress image.png video.mp4 document.pdf
clop optimise --aggressive --pdf-dpi adaptive document.pdf
clop optimise --no-adaptive-optimisation image.png
```

This compatibility form is useful for one mixed selection. The typed
subcommands should be preferred when the workflow exposes media-specific
compression, bitrate, encoder, crop, or conversion controls.

## `crop`

```text
clop crop [options] --size SIZE [items...]
```

Additional options:

| Option | Meaning |
| --- | --- |
| `-s`, `--size VALUE` | Required dimensions, aspect ratio, or single edge |
| `-l`, `--long-edge` | Treat a single number as the maximum long edge |
| `--smart-crop` | Center the crop on detected image features |

Accepted size forms:

```text
1200x630   exact crop
16:9       aspect ratio
1920       single dimension
128x0      calculate height while preserving aspect ratio
0x720      calculate width while preserving aspect ratio
```

Examples:

```sh
clop crop -g --size 1200x630 image.png
clop crop --size 16:9 --smart-crop image.png
clop crop --long-edge --size 1920 video.mp4
clop crop --size 0x720 image.png
```

## `downscale`

```text
clop downscale [options] [items...]
```

`--factor NUMBER` defaults to `0.5`. For images and videos, the factor changes
dimensions. For audio, it changes bitrate.

```sh
clop downscale -g --factor 0.5 image.png video.mp4
clop downscale --factor 0.75 audio.m4a
```

The help describes `1.0` as no change and `0.5` as half size or bitrate. The
workflow should validate its intended range with fixtures before allowing
values greater than or equal to 1.

## `convert`

Clop 3.0 has two distinct conversion systems.

### App-backed typed conversion

```text
clop convert image --to FORMAT [options] [items...]
clop convert video --to FORMAT [options] [items...]
clop convert audio --to FORMAT [options] [items...]
```

These commands communicate with Clop and support shared app-backed options,
including `--json`.

#### Image targets

```text
webp, avif, heic, jxl, jpeg, jpg, png
```

`--compression` accepts `5` through `100` and defaults to the app's image
compression setting.

```sh
clop convert image --to webp --compression 75 photo.png
clop convert image --to jxl --json photo.png
```

#### Video targets

| Value | Result |
| --- | --- |
| `mp4` | H.264 |
| `gif` | Animated GIF |
| `webm` | VP9 |
| `hevc` | Hardware H.265 |
| `x265` | Software H.265 |
| `av1` | SVT-AV1 in MKV |

`--compression` accepts `5` through `100` or `auto`, but only affects MP4/H.264.
The other codecs use tuned fixed settings.

```sh
clop convert video --to gif screencast.mov
clop convert video --to mp4 --compression auto clip.mov
clop convert video --to av1 --json clip.mp4
```

#### Audio targets

```text
mp3, aac, m4a, opus, ogg, flac, wav, aiff
```

`--compression` maps `5` through `100` to a target bitrate. `--bitrate` is in
kbps, takes priority, never increases the source bitrate, and snaps to an
allowed bitrate for the target format.

```sh
clop convert audio --to mp3 --bitrate 128 recording.wav
clop convert audio --to flac --json recording.aiff
```

The typed conversion help says `--output` defaults to modifying the file in
place. Because conversion necessarily changes a format or codec, the exact
source replacement and backup behavior must be tested with disposable fixtures
before Alfred Clop relies on the default.

### Legacy local image conversion

The beta-era syntax remains supported and is shown by help as `convert legacy`:

```text
clop convert legacy --format FORMAT [options] [images...]
```

The compatibility shortcut also works:

```sh
clop convert -f webp -q 75 image.png
```

| Option | Meaning |
| --- | --- |
| `-f`, `--format VALUE` | Required: `avif`, `heic`, or `webp` |
| `-q`, `--quality NUMBER` | Output quality from 0 to 100; default `60` |
| `-o`, `--output VALUE` | Output path or template |
| `--force` | Replace an existing output |

Legacy conversion runs locally without the Clop app, has no JSON output, and
places a new converted file beside the original by default.

The workflow should choose one conversion model explicitly. New media support
and structured results require the typed app-backed commands; offline image
conversion and the old quality scale require legacy mode.

## `crop-pdf`

```text
clop crop-pdf [options] [pdfs...]
```

Exactly one crop target is normally supplied:

| Option | Meaning |
| --- | --- |
| `--for-device VALUE` | Crop for a named Apple device |
| `--paper-size VALUE` | Crop for a named paper size |
| `--aspect-ratio VALUE` | Crop for dimensions or a ratio |
| `--page-layout VALUE` | `auto`, `portrait`, or `landscape`; default `auto` |
| `-e`, `--extend` | Add empty paper instead of clipping content |
| `-r`, `--recursive` | Recurse into a folder |
| `-o`, `--output VALUE` | Output file or folder |
| `--list-devices` | Print accepted device names |
| `--list-paper-sizes` | Print accepted paper sizes |

This operation changes the PDF crop box and is reversible with `uncrop-pdf`.
`--extend` is useful when fitting a document to a target ratio must not cut off
text or other page content.

The 3.0 device list is grouped by exact screen aspect ratio and includes:

- iPhone 4 through iPhone 17 families, including SE, mini, Plus, Pro, Pro Max,
  Air, 16e, and 17e models where applicable;
- iPad generations 2 through 11;
- iPad Air generations 1 through M4;
- iPad mini generations 1 through 7;
- iPad Pro models through M5;
- iPod touch generations 4 through 7.

Paper sizes are grouped by aspect ratio and include ISO A/B and extended sizes,
US ANSI and architectural sizes, photography formats, newspaper formats, and
common book formats.

Both group names and individual names are accepted. The workflow should call
the list commands and cache their output instead of hard-coding either list.

```sh
clop crop-pdf --for-device 'iPad Air M4 11inch' book.pdf
clop crop-pdf --paper-size A4 --page-layout portrait document.pdf
clop crop-pdf --aspect-ratio 16:9 --extend slides.pdf
```

## `uncrop-pdf`

```text
clop uncrop-pdf [--output VALUE] [--recursive] [pdfs...]
```

Removes the crop box added by reversible PDF cropping.

```sh
clop uncrop-pdf book.pdf
```

## `strip-exif`

```text
clop strip-exif [options] [files...]
```

| Option | Meaning |
| --- | --- |
| `-r`, `--recursive` | Recurse into a folder |
| `--types VALUE` | Restrict types |
| `--exclude-types VALUE` | Exclude types |

This command is documented for images and videos. PDFs are not supported.

## `pipeline`

```text
clop pipeline <subcommand>
```

| Subcommand | Purpose |
| --- | --- |
| `pipeline list [--json]` | List saved pipelines and folder automations |
| `pipeline show [--json] NAME` | Show a saved pipeline's steps |
| `pipeline run ... PIPELINE [items...]` | Run a saved pipeline or inline steps |
| `pipeline add ... NAME STEPS` | Save a pipeline to Clop's library |
| `pipeline delete NAME` | Delete a saved pipeline |

Inline example:

```sh
clop pipeline run \
  'crop(width: 1600) -> convert(to: webp)' \
  image.png
```

Inline pipelines run exactly the written steps and do not add an implicit
optimization pass. Saved pipelines preserve their own "skip optimization"
setting; when that setting is off, Clop optimizes before running the steps.

Documented steps:

```text
optimise, downscale, lowerBitrate, convert, crop, extractPagesAsImages,
copy, move, rename, delete, if, ifNot, removeAudio, changeSpeed,
runScript, runShortcut, copyToClipboard, copyLinkForSending,
shelveWith, uploadWith, openWith
```

`pipeline run` supports `--gui`, `--no-progress`, `--async`, `--recursive`,
`--skip-errors`, `--json`, and `--types`.

`pipeline add` supports:

| Option | Meaning |
| --- | --- |
| `--file-type VALUE` | Limit to `image`, `video`, `pdf`, or `audio` |
| `--skip-optimisation` | Run only the explicit steps |
| `--hide-result` | Hide floating results |
| `--force` | Replace a pipeline with the same name |

Pipelines make multi-step conversion and processing possible in one Clop
request. Alfred Clop should still defer a pipeline UI until its core single
actions are complete, but it no longer needs to implement those chains as
multiple CLI processes.

## Output templates

App-backed processing commands document these common tokens:

| Token | Value |
| --- | --- |
| `%y` | Year |
| `%m` | Numeric month |
| `%n` | Month name |
| `%d` | Day |
| `%w` | Weekday |
| `%H` | Hour |
| `%M` | Minutes |
| `%S` | Seconds |
| `%p` | AM/PM |
| `%P` | Source path without filename |
| `%f` | Source filename without extension |
| `%e` | Source extension |
| `%r` | Random characters |
| `%i` | Auto-incrementing number |

The shared app-backed help also displays `%z` for crop size, `%s` for scale
factor, and `%x` for playback speed factor. Use a token only when the selected
operation actually supplies its value.

Legacy conversion additionally supports `%q` for conversion quality.

Disposable-file probes against Clop 3.0.0 verified these output details:

- omitting `--output` processes the input in place;
- Clop appends the resulting extension automatically, so a preservation
  template should use `%P/%f-clop`, not `%P/%f-clop.%e`;
- a literal directory path, including one with a trailing slash, is treated as
  an output filename rather than as a destination directory;
- writing to a chosen directory therefore requires a filename template such as
  `/chosen/folder/%f-clop`;
- an empty output value fails inside the JSON result and must not be passed;
- unknown template tokens remain literal instead of producing a validation
  error;
- an existing output path is overwritten without confirmation;
- `%f` gives distinct names for ordinary multiple-file batches, but inputs
  from different directories may still collide when they share a basename;
- app-backed conversion appends the converted extension, such as `.webp`.

The workflow must validate templates itself and preflight batch collisions
before launching Clop. The built-in preservation template is
`%P/%f-clop`.

## Integration behavior

### Locate the CLI

Recommended lookup order:

1. User-configured override path.
2. `/Applications/Clop.app/Contents/SharedSupport/ClopCLI`.
3. `/Applications/Setapp/Clop.app/Contents/SharedSupport/ClopCLI`, after local
   verification.
4. An executable named `clop` found through the process environment.

The workflow should validate executability and show an Alfred action that opens
Clop's download page when no CLI is found.

### Process invocation

Use Foundation `Process` with an argument array. Do not build a shell command
or use `eval`. Direct arguments correctly preserve spaces, quotes, and unusual
characters in file paths.

For synchronous runs:

- set `executableURL` to the discovered Clop CLI;
- pass each option and path as its own argument;
- capture standard output and standard error separately;
- request `--json` for app-backed commands that support it;
- inspect both termination status and decoded results.

`--async` should not be used when the workflow needs final status because it
returns before processing completes.

The typed app-backed commands require communication with Clop. Legacy image
conversion explicitly runs without the app.

### Original preservation and output safety

The CLI has no explicit `--backup` or `--backup-directory` option. Alfred Clop
does not promise workflow-managed backup copies. It preserves an original by
supplying a distinct, validated `--output` template and replaces in place by
omitting `--output`.

Because Clop silently overwrites an existing output path, the workflow must
detect collisions between planned outputs, existing files, and the source
paths before process launch. An output template is preservation behavior, not
a true backup policy.

## Known limitations and items to probe

- No CLI version flag exists.
- `crop --json` exits with status 0 when requested dimensions would enlarge an
  image. The JSON result reports the skipped input under `failed`, with an
  "already at the correct size or smaller" error. Mixed batches include
  processed inputs under `done` and skipped inputs under `failed`, so callers
  must inspect both arrays rather than relying on termination status.
- Legacy image conversion has no JSON output.
- `crop-pdf`, `uncrop-pdf`, and `strip-exif` have no JSON output.
- Output behavior for folders, remote URLs, videos, audio, and PDFs still needs
  disposable-fixture coverage where each command supports `--output`.
- The parent `optimise` help's `--dpi 96` example conflicts with the typed
  parser, which accepts only `adaptive`, `300`, `250`, `200`, `150`, `100`,
  `72`, or `48`.
- The exact JSON schema should be captured with fixture files for optimize,
  convert, and pipeline results.
- Mixed media batches need integration tests.
- Clop 3.0.0 can return status 0 with a JSON `failed` entry saying URL type
  HTTPS is unsupported for nested Substack CDN image URLs even though Clop's
  app UI accepts and processes the same submitted URL. Alfred Clop treats only
  that exact remote-URL false failure as a successful submission; other
  failures in the same batch remain reportable.
- Generic `--types audio` remains worth a runtime fixture test if exposed.
- Pipeline syntax beyond the examples should be treated as opaque user input
  until Clop publishes a complete step grammar.
- Clop must be running for commands that communicate with the app; the
  workflow should detect and explain connection failures.
