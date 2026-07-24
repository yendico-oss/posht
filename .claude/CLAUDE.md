# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Posht is a PowerShell module (published to the PowerShell Gallery as `posht`) that wraps `Invoke-WebRequest` for testing HTTP APIs directly from a PowerShell terminal — "Postman, but integrated into PS with no GUI." Every call made through `Invoke-ApiRequest` is persisted to a JSON file, grouped by base URI, and can be browsed/replayed via a CLI menu or re-run through the pipeline.

Requires **PowerShell >= 7.2** (Windows, Linux, macOS).

## Working with the module locally

There is no build step. To load your working copy into a session:

```powershell
Import-Module ./Posht/Posht.psd1 -Force   # -Force to reload after edits
```

Validate the manifest (this is what CI checks — there is **no unit test suite**):

```powershell
Test-ModuleManifest -Path ./Posht/Posht.psd1
```

To exercise changes, point the module at a throwaway config so you don't touch `~/.posht/posht.json`: `cd` into a temp directory and run `New-ApiConfig -Local`, which creates a `posht.json` in the current directory. Config resolution always prefers a `posht.json` in the current working directory over `$HOME/.posht/posht.json`.

## Release / CI flow

- `.github/workflows/test-and-tag.yml` runs on every push: validates the `.psd1`, enforces that `ModuleVersion` is SemVer and does not already exist as a git tag or on PSGallery, and — only on `main` — creates a git tag matching `ModuleVersion`.
- `.github/workflows/publish.yml` runs when a GitHub **release** is created and publishes to PSGallery.
- **Bump `ModuleVersion` in `Posht/Posht.psd1` for every change destined for `main`**, otherwise the tag step fails on the duplicate-version check. Add a matching entry to `RELEASE_NOTES.md`.

## Architecture

Nearly everything lives in the single module file `Posht/Posht.psm1`, organized by `#region` blocks (variables, classes, private functions, public functions, schema migrations, aliases). The only sourced dependency is `Posht/Functions/ConvertTo-Expression.ps1` (third-party, from iRon7 — do not modify; it reconstructs an `Invoke-ApiRequest` command string for the menu's "Clipboard" action).

### Data model (classes)

- `ApiConfig` — the whole persisted document: `DefaultHeaders`, a `Collections` hashtable, `Version`, and `Id`. Has a from-JSON constructor and an empty constructor.
- `ApiCollection` — all requests sharing one base URI (e.g. `https://foo.bar:443`). Holds collection-level `Headers` and a `Requests` hashtable.
- `ApiRequest` — a single call. Keyed within a collection by `GetCollectionKey()` = `method_path` (lowercased), so **method + path uniquely identifies a request inside a collection**; re-running an identical call increments `UsageCount` rather than duplicating.
- `CliMenuItem` — a `{ Label, Data }` pair wrapping any object for the menu.

Each JSON-hydrating class has a dedicated constructor that walks the raw hashtable and rebuilds typed child objects — when you add a field to a class, update **both** constructors and the migration logic.

### Header resolution (important)

`Invoke-ApiRequest` merges headers in three layers, later overriding earlier: (1) `ApiConfig.DefaultHeaders`, (2) collection `Headers`, (3) request `Headers`. `-SaveHeadersOnCollection` promotes a request's headers up to its collection so future requests inherit them. `-BearerToken` sets an `Authorization` header at request time.

### Persistence

There is no in-memory cache: `Get-ApiConfig` reads and re-parses the JSON file on **every** call, and every mutating public function ends by calling `Save-ApiConfig`. Config path resolution is in `Resolve-ApiConfigFilePath` (local dir wins over `$HOME/.posht/`). Session cookies live in the script-scoped `$Script:ApiSession` and are **not** persisted to disk; only one active session is supported at a time.

### Schema migrations

`Start-Migrations` runs on every read via `Read-ApiConfig`. It steps a config's `Version` up to `$Script:ApiConfigFileVersion` (currently 2), saving after each step. When you change the on-disk schema: bump `$Script:ApiConfigFileVersion`, add a `if ($ApiConfig.Version -lt N)` block, and remember old files on disk may be any prior version (or version 0 = pre-versioning).

### CLI menu

`Show-CliMenu` / `Build-CliMenu` implement an interactive arrow-key menu (also `j`/`k`, Home/End, space for multiselect) with windowed paging based on console height. `Show-ApiRequest` drives a three-level flow: collections → requests → per-request actions (Run / Clipboard / Details / Remove / Cancel), where Esc navigates back up. Colors use explicit `[System.ConsoleColor]` values — a past bug (v2.0.2) was relying on `$Host.UI.RawUI.ForegroundColor`, which is unavailable on macOS.

### Exports & completion

Only functions listed in `FunctionsToExport` in the `.psd1` are public — add new public functions there. Aliases: `iar` → `Invoke-ApiRequest`, `sar` → `Show-ApiRequest`. Tab completion for `-Uri` / `-BaseUri` params is wired via `Register-ArgumentCompleter` using the `*ArgCompleter` functions; those completers may only call **exported** functions.
