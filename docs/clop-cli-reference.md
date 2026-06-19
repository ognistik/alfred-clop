# Clop CLI reference

This is the verified Clop CLI behavior that Clop for Alfred relies on. Keep it
short and current. It is not a historical research log.

## CLI discovery

Clop for Alfred discovers the CLI in this order:

1. `ALFRED_CLOP_CLI_PATH`, when set.
2. `/Applications/Clop.app/Contents/SharedSupport/ClopCLI`.
3. `/Applications/Setapp/Clop.app/Contents/SharedSupport/ClopCLI`, after
   resolving the Setapp app location.
4. `clop` on `PATH`.

Do not assume a fixed user install path.

## Invocation rules

- Build process arguments as arrays.
- Do not use shell interpolation or `eval`.
- Prefer app-backed Clop commands.
- Use `--json` and `--no-progress` for commands where Clop for Alfred needs a
  structured result.
- Use `--skip-errors` for batch-friendly app-backed processing.
- Do not use `--async` in the workflow execution path; it prevents reliable
  final status and result handling.

## Command overview

| Workflow action | Clop command |
| --- | --- |
| Optimize | `optimise` |
| Media-specific Optimize | `optimise image`, `optimise video`, `optimise pdf`, `optimise audio` |
| Crop / Resize | `crop` |
| Downscale | `downscale` |
| Convert Image/Video/Audio | `convert <media> --to <format>` |
| Crop PDF | `crop-pdf` |
| Uncrop PDF | `uncrop-pdf` |
| Strip Metadata | `strip-exif` |
| Pipeline | `pipeline run` |

The Clop command spelling is `optimise`, not `optimize`.

## Shared execution flags

Clop for Alfred uses these flags where supported by the target command:

| Flag | Meaning |
| --- | --- |
| `--json` | Print structured result JSON. |
| `--no-progress` | Suppress progress output. |
| `--skip-errors` | Continue/return structured feedback for missing or unsupported inputs. |
| `--gui` | Show Clop’s floating result UI. |
| `--copy` | Ask Clop to copy the result. |
| `--recursive` | Include files in subfolders. |
| `--output VALUE` | Use an output path or template. |

The workflow’s `Floating Result`, `Copy`, `Recurse into folders`, and output
template settings map to these flags.

## Optimize

Generic Optimize:

```text
clop optimise --json --no-progress --skip-errors [options] [items...]
```

Common workflow-controlled options:

| Flag | Source |
| --- | --- |
| `--aggressive` | Aggressive optimization |
| `--pdf-dpi VALUE` | PDF DPI control for generic optimize |
| `--adaptive-optimisation` | Adaptive image optimization |
| `--no-adaptive-optimisation` | Explicitly disable adaptive optimization |
| `--gui` | Floating Result |
| `--copy` | Copy |
| `--recursive` | Recurse into folders |
| `--output VALUE` | Preserve originals/output template |

Media-specific Optimize:

```text
clop optimise image --json --no-progress --skip-errors --compression 70 photo.png
clop optimise video --json --no-progress --skip-errors --compression 70 --encoder software movie.mp4
clop optimise pdf --json --no-progress --skip-errors --dpi 150 book.pdf
clop optimise audio --json --no-progress --skip-errors --bitrate 128 audio.wav
```

Verified media controls:

| Media | Flags |
| --- | --- |
| image | `--compression VALUE`, including `adaptive` |
| video | `--compression VALUE`, `--encoder VALUE`, `--remove-audio`, `--playback-speed-factor VALUE` |
| pdf | `--dpi VALUE`, including `adaptive` |
| audio | `--compression VALUE`, `--bitrate VALUE` |

## Crop / Resize

```text
clop crop --size VALUE --json --no-progress --skip-errors [options] [items...]
```

Verified options:

| Flag | Meaning |
| --- | --- |
| `--size VALUE` | Required size, dimension, or ratio. |
| `--long-edge` | Treat a single number as long edge. |
| `--smart-crop` | Use Clop Smart Crop. |
| `--adaptive-optimisation` | Enable adaptive optimization. |
| `--no-adaptive-optimisation` | Explicitly disable adaptive optimization. |
| `--remove-audio` | Remove audio from video output. |
| `--aggressive` | Use aggressive optimization. |
| `--gui`, `--copy`, `--recursive`, `--output` | Workflow-controlled runtime flags. |

Known behavior: `crop --json` can exit with status `0` when every file is
skipped because the requested dimensions would enlarge the input. Clop for Alfred
must inspect the JSON result, not just the process status.

## Downscale

```text
clop downscale --factor VALUE --json --no-progress --skip-errors [options] [items...]
```

Verified options:

| Flag | Meaning |
| --- | --- |
| `--factor VALUE` | Required factor, such as `0.5` for 50%. |
| `--adaptive-optimisation` | Enable adaptive optimization. |
| `--no-adaptive-optimisation` | Explicitly disable adaptive optimization. |
| `--remove-audio` | Remove audio from video output. |
| `--gui`, `--copy`, `--recursive`, `--output` | Workflow-controlled runtime flags. |

Clop for Alfred validates factors before launching Clop. Values must be greater
than `0` and less than `1`.

## Convert

```text
clop convert image --to webp --json --no-progress --skip-errors [options] [items...]
clop convert video --to webm --json --no-progress --skip-errors [options] [items...]
clop convert audio --to mp3 --json --no-progress --skip-errors [options] [items...]
```

Verified options:

| Flag | Meaning |
| --- | --- |
| `--to VALUE` | Required target format. |
| `--compression VALUE` | Image/video/audio compression where supported. |
| `--bitrate VALUE` | Audio bitrate. |
| `--gui`, `--copy`, `--recursive`, `--output` | Workflow-controlled runtime flags. |

Clop for Alfred normalizes `jpg` to `jpeg`.

Legacy local image conversion exists in Clop, but it is not a workflow product
goal. Clop for Alfred should prefer the app-backed `convert` route.

## Crop PDF

```text
clop crop-pdf [target] [options] [pdfs...]
```

Target flags:

| Flag | Meaning |
| --- | --- |
| `--aspect-ratio VALUE` | Crop to an aspect ratio. |
| `--for-device VALUE` | Crop for a named device. |
| `--paper-size VALUE` | Crop for a named paper size. |

Options:

| Flag | Meaning |
| --- | --- |
| `--page-layout portrait|landscape` | Target orientation. |
| `--extend` | Add empty paper instead of clipping content. |
| `--recursive` | Include files in subfolders. |
| `--output VALUE` | PDF-specific output value. |

`crop-pdf` changes the PDF crop box and is reversible with `uncrop-pdf`.

PDF output behavior differs from app-backed image/video/audio commands. Alfred
Clop translates common per-source templates to the concrete form that Clop’s
PDF commands accept.

## Uncrop PDF

```text
clop uncrop-pdf [--output VALUE] [--recursive] [pdfs...]
```

`uncrop-pdf` removes the reversible crop box added by `crop-pdf`. It has no
JSON result and no Clop GUI flag in the workflow integration.

## Strip Metadata

```text
clop strip-exif [--recursive] [items...]
```

`strip-exif` removes metadata from supported image/video inputs. It does not
expose `--output`, so Clop for Alfred must reject one-run output-template overrides
for this action before launching Clop.

## Pipeline

```text
clop pipeline run --json --no-progress --skip-errors [options] PIPELINE [items...]
```

Runtime options used by Clop for Alfred:

| Flag | Meaning |
| --- | --- |
| `--gui` | Show Clop result UI unless the workflow or pipeline says to hide it. |
| `--recursive` | Include files in subfolders. |
| `--json`, `--no-progress`, `--skip-errors` | Structured, quiet workflow execution. |

Inline pipelines run the written steps. If the workflow request says to optimize
first, Clop for Alfred prepends `optimise ->`.

Saved pipelines preserve Clop’s own saved settings. The workflow can list, run,
add, replace, and delete saved pipelines through Clop’s pipeline commands.

Useful Clop pipeline commands:

```text
clop pipeline list --json
clop pipeline show --json NAME
clop pipeline add [--file-type image|video|pdf|audio] [--skip-optimisation] [--hide-result] [--force] NAME STEPS
clop pipeline delete NAME
clop pipeline prompt [--copy] [TASK...]
```

Known pipeline step names tracked by the workflow include:

```text
optimise, downscale, lowerBitrate, convert, crop, extractPagesAsImages,
targetSize, stripExif, watermark, removeAudio, changeSpeed, capFps, normalize,
```

The `pipeline prompt` command prints a local reference prompt for an AI
assistant. Clop for Alfred exposes this in Configuration as `:pipelines prompt TASK`.

## Output behavior

The CLI has no explicit backup mode. Clop for Alfred’s “Preserve originals” behavior
means “supply a distinct output path/template where the command supports it.”
When output is disabled, the workflow omits `--output`.

Workflow output templates use these tokens:

| Token | Meaning |
| --- | --- |
| `%P` | Source folder |
| `%f` | Filename without extension |
| `%y`, `%m`, `%n`, `%d`, `%w` | Date parts |
| `%H`, `%M`, `%S`, `%p` | Time parts |
| `%r` | Random characters |
| `%i` | Incrementing number |

Clop adds the final extension for app-backed output.

## Known limitations

- `crop-pdf`, `uncrop-pdf`, and `strip-exif` do not provide the same JSON/GUI
  behavior as app-backed processing commands.
- `--async` is intentionally not used by the workflow.
- Raw `--types` and `--exclude-types` are Clop CLI concepts, not current Alfred
  Clop UI features.
- The exact Clop JSON result schema should continue to be covered through
  fixture-style tests as command support evolves.
