# Release Process

This project ships a native Swift executable inside an Alfred workflow archive.
The release flow keeps build, signing, packaging, notarization, and GitHub
publishing as separate steps so local testing does not require a full release.

## Local Secrets

Local release credentials live in `.release.env`. This file is ignored by git.
It may define:

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"
export NOTARYTOOL_PROFILE="notarytool-keychain-profile"
```

`DEVELOPER_ID_PROVISIONING_PROFILE` may also exist in older local signing files,
but Clop for Alfred does not currently use it. A plain command-line executable
distributed outside the Mac App Store normally needs Developer ID signing and
notarization, not an embedded provisioning profile. Provisioning profiles become
relevant for app bundles that use special capabilities.

## Build Only

```sh
./scripts/build.sh
```

This builds a universal macOS binary for Apple Silicon and Intel Macs, targeting
macOS 13 or newer, then copies it to `workflow/alfred-clop`.

## Build And Sign

```sh
./scripts/build.sh --sign
```

or sign an already-built binary:

```sh
./scripts/sign.sh
```

Signing uses the Developer ID Application identity from `.release.env`, enables
the hardened runtime, and requests a secure timestamp.

## Package

```sh
./scripts/package.sh
```

The package is written to:

```text
dist/Clop-<version>.alfredworkflow
```

The package excludes local Alfred state such as `prefs.plist`.

## Package, Sign, And Notarize

```sh
./scripts/package.sh --sign --notarize
```

This is the complete preparation command for a release. It performs a fresh
universal build, signs the executable, packages the workflow, and submits the
archive to Apple's notary service using `NOTARYTOOL_PROFILE`. You do not need to
run `./scripts/build.sh --sign` first.

The archive is a zip-based workflow package, so there is no stapling step in
this workflow.

## Release Checklist

For each release:

1. Change the version in `workflow/info.plist`.
2. Move the relevant entries from `UNRELEASED` into a versioned section in
   `CHANGELOG.md` and add the release date.
3. Run `./scripts/package.sh --sign --notarize`.
4. Test the freshly built workflow through the linked development workflow in
   Alfred. The release archive will be waiting in `dist/`.
5. Commit and push the release changes.
6. Run `./scripts/release.sh` to create a draft GitHub release.
7. Review the draft on GitHub, then publish it.

## GitHub Release

The repository must be public before distributing the workflow. Clop for Alfred's
update checker uses GitHub's unauthenticated latest-release endpoint; releases
in a private repository are visible to the signed-in maintainer but return 404
for workflow users.

Create a draft release for review:

```sh
./scripts/release.sh
```

Publish immediately:

```sh
./scripts/release.sh --publish
```

The release tag is derived from `workflow/info.plist`, for example `v0.1.0`.
Release notes are taken automatically from that version's section in
`CHANGELOG.md`; the `UNRELEASED` section and older versions are not included.
Use `--notes-file PATH` only when a release needs custom notes.
