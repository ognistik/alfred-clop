# AGENTS.md

## Project

Alfred Clop is a native Swift Alfred workflow that presents context-aware Clop
actions for files supplied from several input sources.

Read these files before making architectural changes:

1. `docs/project-status.md` for the current checkpoint and next task.
2. `docs/project-plan.md` for product scope and architecture.
3. `docs/clop-cli-reference.md` for verified Clop CLI behavior.

## Repository layout

- `src/`: Swift Package, executable, and tests
- `workflow/`: Alfred workflow source and built executable
- `scripts/`: build and test entry points
- `docs/`: plan, status, and CLI research

## Commands

Run the complete test suite:

```sh
./scripts/test.sh
```

Build the release executable into the workflow:

```sh
./scripts/build.sh
```

Validate the Alfred workflow plist:

```sh
plutil -lint workflow/info.plist
```

Run all three before completing a task that changes Swift code or the workflow.

## Architecture rules

- Keep one Swift executable with explicit modes.
- Keep one shared Alfred Script Filter for the action menu.
- Normalize every input source through `InputCollector`.
- Keep input-source wording accurate: selected, copied, or passed files.
- Preserve `alfred_clop_input_context` across Script Filter reruns.
- Treat `alfred_clop_input_json` as normalized menu state, not fresh input.
- Derive available actions from media capabilities in `ActionCatalog`.
- Build process arguments as arrays. Never use shell interpolation or `eval`.
- Use `ClopCLIDiscovery`; do not assume a fixed installation path.
- Keep parameter-requiring actions separate from immediate actions.

## Workflow input routes

- Universal Action -> selected paths -> shared Script Filter
- `clop` keyword -> current clipboard -> shared Script Filter
- `paths` External Trigger -> passed paths -> shared Script Filter

Fresh Universal Action and External Trigger routes clear stale
`alfred_clop_input_json` before entering the Script Filter.

## Testing rules

- Add focused tests for every behavior change.
- Inject clipboard and process dependencies; tests must not use the real system
  clipboard or launch the real Clop CLI.
- Use temporary files and directories for input fixtures.
- Cover filenames containing spaces and multiple-file payloads.
- Preserve the Universal Action, clipboard, and External Trigger flows.

## Scope discipline

- Follow the next bounded task in `docs/project-status.md`.
- Do not implement unrelated parameter menus or Clop operations early.
- Update `docs/project-status.md` after completing a meaningful checkpoint.
- Update `docs/project-plan.md` only when product scope or architecture changes.

## Generated and local files

- Do not commit `src/.build/`, `.DS_Store`, Python caches, Alfred preferences,
  logs, or exported `.alfredworkflow` files.
- `workflow/alfred-clop` is rebuilt by `scripts/build.sh`; keep it synchronized
  with the checked-in Swift source at project checkpoints.
