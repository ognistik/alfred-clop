# Alfred Clop

An Alfred workflow for discovering and running Clop operations from a fast,
file-aware Script Filter.

The workflow is being designed around one native Swift executable. That
executable will:

- accept files from Alfred, Finder, the clipboard, and custom paths;
- inspect the selected media types;
- return context-aware Alfred Script Filter JSON;
- fuzzy-filter actions and presets;
- invoke the Clop CLI without shell interpolation;
- parse results and present useful feedback.

## Status

The Swift executable accepts files from Alfred Universal Actions, Finder, the
clipboard, Hotkeys, explicit paths and URLs, and the public `clop` External
Trigger. It normalizes those inputs into one context-aware action menu.
Optimize, Crop / Resize, Uncrop PDF, and Strip Metadata execute through the
discovered Clop CLI, and Crop / Resize supports reusable presets.

Type `:` in the action menu to replace processing actions with workflow
Configuration. `:template ` opens the live output-template editor; deleting
the namespace returns to the processing actions for the same input. Final
Configuration changes normally close Alfred, while Command-Return applies the
change and returns to `:`.

See the [project status](docs/project-status.md) for the current checkpoint and
next recommended task.

## Documentation

- [Clop CLI reference](docs/clop-cli-reference.md)
- [External Trigger reference](docs/external-trigger.md)
- [Workflow implementation plan](docs/project-plan.md)
- [Current project status](docs/project-status.md)

## Repository layout

The intended layout is:

```text
.
|-- docs/                 Research and design decisions
|-- src/                  Swift package and tests
|-- workflow/             Alfred workflow source assets and info.plist
|-- scripts/              Build, package, and release helpers
`-- dist/                 Generated workflow releases (ignored)
```

The Swift package lives under `src/`, and the current Alfred workflow source is
under `workflow/`.

## Development

To run the test suite:

```sh
./scripts/test.sh
```

To build the release executable:

```sh
./scripts/build.sh
```

The built binary is copied to:

```text
workflow/alfred-clop
```

The local Alfred development workflow is symlinked directly to `workflow/`, so
edits and rebuilt binaries are used in place. Restart Alfred after changing
workflow objects or connections so it reloads the topology.

## Requirements

- macOS
- Alfred with the Powerpack
- Clop installed in `/Applications/Clop.app`

The workflow should prefer Clop's bundled CLI at:

```text
/Applications/Clop.app/Contents/SharedSupport/ClopCLI
```

It may fall back to `clop` on `PATH`, but it should not require users to create
the `~/.local/bin/clop` symlink themselves.
