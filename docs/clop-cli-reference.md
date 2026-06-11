# Clop CLI Reference

Research date: June 6, 2026

## Target version and method

This reference was generated primarily from the CLI bundled with the locally
installed Clop app:

```text
Clop app version: 3.0.0b4
CLI path: /Applications/Clop.app/Contents/SharedSupport/ClopCLI
CLI architecture: universal (arm64 and x86_64)
```

Clop's CLI has no `--version` option, so the containing app's bundle version is
the practical version identifier.

The installed CLI's own `--help` output is authoritative for this project.
Clop's public GitHub repository and website were used as supporting sources,
but the public latest release was still 2.11.6 on February 19, 2026 and can lag
the installed 3.0 beta.

Sources:

- [Clop website](https://lowtechguys.com/clop/)
- [Clop source repository](https://github.com/FuzzyIdeas/Clop)
- [Clop releases](https://github.com/FuzzyIdeas/Clop/releases)

## Command overview

| Command | Inputs | Purpose |
| --- | --- | --- |
| `optimise` | images, videos, audio, PDFs, URLs, folders | Optimize in place or to an output path |
| `crop` | images, videos, PDFs, URLs, folders | Crop and optimize to dimensions or an aspect ratio |
| `downscale` | images, videos, audio, URLs, folders | Scale dimensions, or audio bitrate, by a factor |
| `convert` | images | Convert to AVIF, HEIC, or WebP |
| `crop-pdf` | PDFs or folders | Apply a reversible PDF crop box |
| `uncrop-pdf` | PDFs or folders | Remove a PDF crop box |
| `strip-exif` | images, videos, folders | Remove metadata |

The spelling is `optimise`, not `optimize`.

## Capability matrix

| Capability | Image | Video | Audio | PDF | URL | Folder |
| --- | --- | --- | --- | --- | --- | --- |
| Optimize | Yes | Yes | Yes | Yes | Yes | Yes |
| Aggressive optimize | Yes | Yes | Yes | Yes | Yes | Yes |
| Crop | Yes | Yes | No | Yes | Yes | Yes |
| Downscale | Yes | Yes | Yes (bitrate) | No | Yes | Yes |
| Convert | Yes | No | No | No | No | No |
| Strip metadata | Yes | Yes | No | No | No | Yes |
| Reversible PDF crop | No | No | No | Yes | No | Yes |

Some flags are accepted on broad commands even when they only affect one media
kind. For example, `--remove-audio` only changes videos, and adaptive
optimization only affects images.

## Shared processing options

The following options appear on some or all of `optimise`, `crop`, and
`downscale`:

| Option | Meaning |
| --- | --- |
| `-g`, `--gui` | Show Clop's floating result UI |
| `-n`, `--no-progress` | Suppress progress on standard error |
| `--async` | Submit work in the background |
| `-a`, `--aggressive` | Use aggressive optimization |
| `--pdf-dpi VALUE` | Aggressive PDF DPI: `adaptive`, `300`, `250`, `200`, `150`, `100`, `72`, or `48` |
| `--adaptive-optimisation` | Allow detail-based JPEG/PNG conversion |
| `--no-adaptive-optimisation` | Disable adaptive conversion |
| `-r`, `--recursive` | Recurse when an input is a folder |
| `--types VALUE` | Restrict processing to generic or specific file types |
| `--exclude-types VALUE` | Exclude generic or specific file types |
| `-c`, `--copy` | Copy the processed file to the clipboard |
| `-s`, `--skip-errors` | Skip missing files and unreachable URLs |
| `--remove-audio` | Remove audio from videos |
| `-j`, `--json` | Print structured result JSON |
| `-o`, `--output VALUE` | Choose an output path or filename template |

The installed CLI reports these default specific types:

```text
webp, avif, heic, jxl, bmp, tiff, png, jpeg, gif,
mov, mp4, webm, mkv, m2v, avi, m4v, mpg,
wav, aiff, mp3, flac, m4a, ogg, pdf
```

Generic values such as `image`, `video`, and `pdf` are also accepted. The help
text does not explicitly name an `audio` generic value, so the workflow should
not depend on it without a runtime probe.

## `optimise`

```text
clop optimise [options] [items...]
```

In addition to the shared options:

| Option | Meaning |
| --- | --- |
| `--playback-speed-factor NUMBER` | Change video speed; `2` is twice as fast, `0.5` is half speed |
| `--downscale-factor NUMBER` | Resize images/videos while optimizing |
| `--crop SIZE` | Crop images, videos, or PDFs while optimizing |

This combined command can perform optimization with resize, crop, video speed,
or audio removal in one Clop request. It does not expose image conversion to
AVIF/HEIC/WebP; that remains a separate `convert` command.

Examples:

```sh
clop optimise -g image.png
clop optimise -g -a --pdf-dpi adaptive document.pdf
clop optimise --downscale-factor 0.5 video.mp4
clop optimise --playback-speed-factor 2 --remove-audio video.mp4
clop optimise --crop 1200x630 --output '%P/%f_1200x630.%e' image.png
```

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

Additional option:

| Option | Meaning |
| --- | --- |
| `--factor NUMBER` | Scale factor, default `0.5`; must be greater than 0 and less than 1 |

For images and videos, the factor changes dimensions. For audio, it changes
bitrate.

```sh
clop downscale -g --factor 0.5 image.png video.mp4
clop downscale --factor 0.75 audio.m4a
```

## `convert`

```text
clop convert --format FORMAT [options] [images...]
```

| Option | Meaning |
| --- | --- |
| `-f`, `--format VALUE` | Required: `avif`, `heic`, or `webp` |
| `-q`, `--quality NUMBER` | Output quality from 0 to 100; default `60` |
| `-o`, `--output VALUE` | Output path or template |
| `--force` | Replace an existing output |

Conversion is image-only. It writes a new file by default rather than replacing
the source. The target extension is added automatically.

```sh
clop convert --format webp --quality 75 image.png
clop convert --format avif --output '%P/%f-converted-from-%e' image.png
```

There is no single CLI command for "convert plus optimize plus crop." The
workflow can expose a pipeline, but it must run `convert` and a processing
command in sequence and carefully pass the first output into the second.

## `crop-pdf`

```text
clop crop-pdf [options] [pdfs...]
```

Exactly one crop target is normally supplied:

| Option | Meaning |
| --- | --- |
| `--for-device VALUE` | Crop for a named Apple device |
| `--paper-size VALUE` | Crop for a named paper size |
| `--aspect-ratio VALUE` | Crop for dimensions such as `1640x2360` or a ratio such as `16:9` |
| `--page-layout VALUE` | `auto`, `portrait`, or `landscape`; default `auto` |
| `-r`, `--recursive` | Recurse into a folder |
| `-o`, `--output VALUE` | Output file or folder |
| `--list-devices` | Print accepted device names |
| `--list-paper-sizes` | Print accepted paper sizes |

This operation changes the PDF crop box and is non-destructive. `uncrop-pdf`
can reverse it.

Device families reported by the installed CLI:

- iPad generations 3 through 10
- iPad Air generations 1 through 5
- iPad mini generations 1 through 6
- iPad Pro generations 1 through 6 in supported sizes
- iPhone 4 through iPhone 15 families, including SE models
- iPod touch generations 4 through 7

Paper-size groups reported by the installed CLI:

- ISO A and B sizes
- US ANSI, architectural, letter, legal, ledger, and tabloid sizes
- photography sizes
- newspaper formats
- common book formats

The workflow should dynamically call the two list commands and cache the
results instead of hard-coding lists that can become stale.

Examples:

```sh
clop crop-pdf --for-device 'iPad Air 5' book.pdf
clop crop-pdf --paper-size A4 --page-layout portrait document.pdf
clop crop-pdf --aspect-ratio 16:9 slides.pdf
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

Despite the generic type list shown by help, this command is intended for
images and videos. PDFs are explicitly rejected.

## Output templates

Processing commands support filename templates. Available tokens vary by
command.

Common tokens:

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

Operation-specific tokens:

| Token | Commands | Value |
| --- | --- | --- |
| `%z` | `optimise`, `crop` | Crop size |
| `%s` | `optimise`, `downscale` | Scale factor |
| `%x` | `optimise` | Playback speed factor |
| `%q` | `convert` | Conversion quality |

Examples:

```text
%P/%f_optimised.%e
%P/%f_%z.%e
%P/%f_@_%sx.%e
~/Pictures/Clop/%y-%m-%d/%f_%i.%e
```

For multiple inputs, output generally needs to be a directory or a template
that produces distinct paths.

## Integration behavior

### Locate the CLI

Recommended lookup order:

1. User-configured override path.
2. `/Applications/Clop.app/Contents/SharedSupport/ClopCLI`.
3. `/Applications/Setapp/Clop.app/Contents/SharedSupport/ClopCLI`, if relevant
   after verification.
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
- request `--json` for `optimise`, `crop`, and `downscale`;
- inspect both termination status and decoded results.

`--async` should not be used when the workflow needs final status because it
returns before processing completes.

### Backups and output safety

Clop's in-place behavior and backup location are controlled by Clop itself.
The CLI has no explicit `--backup` or `--backup-directory` option.

The workflow therefore has three honest strategies:

1. Trust Clop's configured in-place backup behavior.
2. Preserve the source by supplying a distinct `--output` template.
3. Implement workflow-managed backup copies with Swift `FileManager` before
   invoking Clop.

The third option is needed if Alfred Clop promises a custom backup folder that
is independent of Clop's app settings.

## Known limitations and items to probe

- No CLI version flag exists.
- `convert` has no JSON output.
- `crop-pdf`, `uncrop-pdf`, and `strip-exif` have no JSON output.
- The documented public source can lag the installed beta.
- The exact JSON schema should be captured with fixture files before writing
  the result decoder.
- The behavior of mixed media batches needs integration tests.
- Whether generic `--types audio` is accepted needs a runtime test.
- Conversion pipelines need explicit temporary/output path handling.
- Clop must be running for commands that communicate with the app; the
  workflow should detect and explain connection failures.
