# AGENTS.md

## Project

Alfred Clop is a native Swift Alfred workflow that presents context-aware Clop
actions for selected, copied, or passed files and URLs.

Read these files before making architectural changes:

1. `docs/architecture.md` for product scope, workflow topology, invariants, and
   non-goals.
2. `docs/clop-cli-reference.md` for verified Clop CLI behavior.
3. `docs/external-trigger.md` before changing public automation syntax.

## Repository layout

- `src/`: Swift Package, executable, and tests
- `workflow/`: Alfred workflow source and built executable
- `scripts/`: build and test entry points
- `docs/`: user-facing and contributor documentation

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
Documentation-only changes do not require the Swift test suite unless they also
change generated artifacts or examples that tests depend on.

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
- Route workflow notifications through Alfred’s native notification object.

## Workflow input routes

- Universal Action -> selected paths -> shared Script Filter
- Keyword -> current clipboard -> shared Script Filter
- Hotkeys -> selected, Finder, or clipboard input -> shared Script Filter or
  direct optimize execution
- Public External Trigger `clop` -> menu or execute route
- Internal External Trigger `mainMenu` -> shared Script Filter reruns

Fresh Universal Action and External Trigger routes clear stale
`alfred_clop_input_json` before entering the Script Filter.

Immediate actions leave the shared Script Filter through a Run Script action.
Successful execution is normally quiet while Clop’s own UI presents progress and
results. Visible workflow notifications are reserved for configured success
messages, configuration feedback, errors, and incomplete operations.

## Local Alfred development

The active development workflow is loaded in place through this symlink:

```text
~/Documents/Alfred/Alfred.alfredpreferences/workflows/com.aft.clop
  -> ../../../GitHubRepos/alfred-clop/workflow
```

- Edit `workflow/info.plist` and `workflow/alfred-clop` in this repository.
- Do not import or copy a separate `.alfredworkflow` for local testing.
- Alfred can cache workflow topology. Restart Alfred after adding, removing, or
  changing the type of workflow objects or connections.

## Testing rules

- Add focused tests for every behavior change.
- Inject clipboard and process dependencies; tests must not use the real system
  clipboard or launch the real Clop CLI.
- Use temporary files and directories for input fixtures.
- Cover filenames containing spaces and multiple-file payloads.
- Preserve the Universal Action, clipboard, Hotkey, and External Trigger flows.

## Scope discipline

- Keep documentation concise and current; avoid restoring historical plan/status
  logs.
- Do not implement unrelated parameter menus, Clop operations, update
  mechanisms, or diagnostics while working on a narrower task.
- If product scope changes, update `docs/architecture.md`.
- If public automation syntax changes, update `docs/external-trigger.md`.
- If verified Clop CLI behavior changes, update `docs/clop-cli-reference.md`.

## Generated and local files

- Do not commit `src/.build/`, `.DS_Store`, Python caches, Alfred preferences,
  logs, or exported `.alfredworkflow` files.
- `workflow/alfred-clop` is rebuilt by `scripts/build.sh`; keep it synchronized
  with the checked-in Swift source at project checkpoints.

