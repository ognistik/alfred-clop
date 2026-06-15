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

Crop / Resize requires `size`. It accepts the same values as the workflow menu:

```text
execute: Crop / Resize
size: 16:9
smart crop: true

finder
```

`smart crop` is Clop's optional feature for centering the crop around detected
image features. It defaults to `false`, which means Alfred Clop does not pass
Clop's `--smart-crop` option. Supported size examples include `1200x630`,
`16:9`, `1920`, `w128`, `h720`, `128x0`, and `0x720`.

### Current Grammar

This table is the complete shorthand execution grammar currently implemented:

| Action | Parameters | Omitted behavior |
| --- | --- | --- |
| `Optimize` | `aggressive` (optional boolean) | Standard optimization |
| `Crop / Resize` | `size` (required), `smart crop` (optional boolean) | Smart Crop disabled |
| `Uncrop PDF` | None | Uses workflow execution settings |
| `Strip Metadata` | None | Uses workflow execution settings |

The following shortcuts open their existing workflow menus, but their complete
execution syntax is intentionally unavailable until those parameter menus and
operations are implemented:

- `downscale:`
- `convert image:`
- `convert video:`
- `convert audio:`
- `crop pdf:`

Attempting `execute:` with one of those actions produces a visible error rather
than guessing at an unfinished parameter contract.

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
