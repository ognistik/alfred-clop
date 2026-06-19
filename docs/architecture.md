# Architecture

This document is the compact contributor reference for Alfred Clop. It replaces
the older project plan and checkpoint log, which were useful during discovery
but had become stale and expensive to navigate.

## Product shape

Alfred Clop is a Swift-based Alfred workflow that wraps Clop’s app-backed CLI.
The workflow collects input from Alfred, normalizes it, shows a context-aware
menu, and launches Clop with explicit process arguments.

The project optimizes for:

- a friendly Alfred UI for non-CLI users;
- accurate handling of selected, copied, and passed files;
- safe argument construction without shell interpolation;
- one public automation contract through the `clop` External Trigger;
- concise, current documentation.

## Repository layout

```text
.
|-- AGENTS.md            Agent/contributor operating rules
|-- README.md            User-facing workflow manual
|-- docs/
|   |-- architecture.md
|   |-- clop-cli-reference.md
|   |-- external-trigger.md
|   `-- release.md
|-- scripts/
|   |-- build.sh
|   |-- package.sh
|   |-- release.sh
|   |-- sign.sh
|   `-- test.sh
|-- src/                 Swift package, source, and tests
`-- workflow/            Alfred workflow plist and built executable
```

## Runtime shape

The workflow uses one Swift executable, `alfred-clop`, with explicit modes:

| Mode | Purpose |
| --- | --- |
| `menu` | Build the shared Script Filter menu. |
| `execute` | Execute an internal operation request. |
| `configure` | Apply or preview configuration menu mutations. |
| `request` | Parse a public External Trigger request and route it. |
| `route` | Return whether a public request should open a menu or execute headlessly. |
| `handoff` | Prepare a public menu request for the shared Script Filter. |
| `automate` | Run direct Hotkey/Universal Action optimize routes. |
| `pipeline-prompt` | Generate the local AI pipeline prompt text. |
| `diagnostics-report` | Generate the plain-text support report copied from Configuration. |
| `probe` | Return basic CLI discovery diagnostics as JSON. |

The Alfred canvas should remain thin. It handles input routing, native
notifications, and window behavior; the Swift executable owns parsing,
capabilities, validation, and command construction.

## Input routes

All user-facing input routes normalize into shared menu or execution models:

| Route | Source | Destination |
| --- | --- | --- |
| Universal Action `Clop Menu` | selected Alfred/Finder items | shared Script Filter |
| Keyword | clipboard, when enabled | shared Script Filter |
| Clipboard Hotkey | clipboard | shared Script Filter |
| Selected/Finder Hotkey | selection | shared Script Filter |
| Optimize Universal Action | selected input | direct optimize execution |
| Optimize Hotkeys | clipboard or selected input | direct optimize execution |
| Public External Trigger `clop` | line shorthand or typed JSON | menu or execute route |
| Internal External Trigger `mainMenu` | preserved menu state | shared Script Filter |

Fresh Universal Action and External Trigger menu routes must clear stale
`alfred_clop_input_json`. Script Filter reruns must preserve
`alfred_clop_input_context`, because it controls user-facing wording and some
fallback behavior.

## Core source areas

| Area | Responsibility |
| --- | --- |
| `Domain/` | Codable request models, action requests, settings, presets, pipeline syntax. |
| `Features/InputCollector.swift` | Normalize clipboard, Finder, explicit, folder, and URL input. |
| `Features/ActionMenu.swift` | Build the root action menu and route to submenus. |
| `Features/*ParameterMenu.swift` | Action-specific parameter menus and preset handling. |
| `Features/ConfigurationMenu.swift` | `:` namespace, output template, presets, pipelines, diagnostics, cache cleanup, settings affordances. |
| `Features/ClopRequestDispatcher.swift` | Convert normalized public/internal requests into menu or execution behavior. |
| `Clop/ClopCommand.swift` | Build Clop CLI argument arrays. |
| `Clop/ClopCLIDiscovery.swift` | Find and validate the Clop CLI. |
| `Clop/ClopProcessRunner.swift` | Launch Clop and capture results. |
| `Support/Environment.swift` | Read Alfred workflow variables and settings paths. |

## Action capability model

Available actions come from media capabilities, not from hard-coded menu
shortcuts. The menu should hide actions that clearly do not apply to the current
input while keeping URL and ambiguous-folder cases useful.

Current action families:

- Optimize
- Crop / Resize
- Downscale
- Convert Image
- Convert Video
- Convert Audio
- Crop PDF
- Uncrop PDF
- Strip Metadata
- Pipeline

Parameter-requiring actions should enter a parameter menu. Immediate actions may
execute directly once the user selects them.

## Settings and persistence

User-facing workflow configuration lives in Alfred workflow variables.

Workflow-owned data lives in `settings.json`, stored in Alfred’s workflow data
folder unless the user selects another Settings folder. The settings document
currently stores:

- schema version;
- action presets;
- output template.

The built-in output template is:

```text
%P/%f-clop
```

## Notifications

Workflow notifications should use Alfred’s native Post Notification object. The
notification title is `Clop`; the message is passed through
`alfred_clop_notification`.

Do not add new `osascript display notification` snippets to workflow objects.

Successful processing often remains quiet when Clop’s own result UI is shown.
Execution and configuration code decides whether feedback text exists; the
workflow canvas decides how to display it.

## External Trigger contract

The public automation contract is documented in
[`docs/external-trigger.md`](external-trigger.md). Keep that document in sync
when changing:

- accepted shorthand directives;
- action names and aliases;
- public parameters;
- typed JSON models;
- validation behavior that users can reasonably depend on.

## Clop CLI contract

Verified Clop CLI behavior is documented in
[`docs/clop-cli-reference.md`](clop-cli-reference.md). Keep that document about
confirmed behavior and current quirks, not historical investigation.

The workflow should:

- discover the CLI rather than assuming one path;
- build arguments as arrays;
- avoid shell interpolation and `eval`;
- prefer Clop’s app-backed commands over legacy local conversions;
- preserve raw Clop behavior unless the workflow has a clear UX reason to
  normalize it.

## Testing and validation

Run the complete test suite:

```sh
./scripts/test.sh
```

Build the workflow executable:

```sh
./scripts/build.sh
```

Build and sign the workflow executable:

```sh
./scripts/build.sh --sign
```

Package a signed and notarized release archive:

```sh
./scripts/package.sh --sign --notarize
```

Validate the Alfred workflow plist:

```sh
plutil -lint workflow/info.plist
```

Run all three before completing Swift or workflow-canvas changes. For
documentation-only changes, linting Markdown manually and checking links is
usually enough.

Tests should cover:

- filenames with spaces;
- multiple-file payloads;
- Universal Action, clipboard, Hotkey, and External Trigger flows;
- no real system clipboard;
- no real Clop process unless explicitly isolated outside unit tests.

## Current non-goals

Keep these out of the active product plan unless the scope is deliberately
reopened:

- legacy offline/local image conversion separate from Clop’s app-backed route;
- raw include/exclude type filter UI;
- `--async`/background submission as a workflow feature;
- a separate Alfred live progress UI;
- automatic update implementation in this cleanup pass.

## Diagnostics

The Configuration menu includes a small `Diagnostics` item for support and
GitHub issue reports. Return copies a plain-text report to the clipboard, and
Command-L previews the same report in Large Type.

The report includes:

- detected Clop CLI path and discovery source;
- executable status;
- app bundle version or build when available;
- workflow version and key workflow configuration values;
- settings schema, preset counts, and saved pipeline count when readable;
- command families needed by the workflow;
- discovery errors.

The report deliberately avoids selected input paths, clipboard contents, full
environment dumps, and unrelated private data.
