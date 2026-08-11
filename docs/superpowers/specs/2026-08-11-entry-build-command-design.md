# Entry Build Command Design

## Summary

Add a repository-level command that builds one manual entry by its catalog key:

```bash
./scripts/build-entry.sh Button_Basic
```

The command resolves the project through `catalog.json`, restores locked dependencies, and publishes a Release build. The root README will use this command instead of repeating the full project path.

## Goals

- Keep entry build commands short and stable as the repository grows.
- Preserve `catalog.json` as the authoritative source for entry discovery.
- Use the same entry identifier in documentation, local development, and CI.
- Fail with a clear message when the key or catalog data is invalid.

## Non-Goals

- No new catalog fields or schema changes.
- No configurable build mode in the initial version.
- No shared Browser host or cross-entry build orchestration.
- No replacement for `scripts/verify-repository.sh`.

## Command Interface

The script accepts exactly one positional argument:

```text
./scripts/build-entry.sh <EntryKey>
```

The initial command always performs these operations in order:

```bash
dotnet restore <project-file> --locked-mode
dotnet publish <project-file> -c Release --no-restore
```

Additional arguments are rejected with usage text. Debug builds and individual restore or publish subcommands can be added later only when a concrete use case requires them.

## Project Resolution

The script reads the entry whose `key` exactly matches the supplied EntryKey. It combines that entry's `directory` and `projectFile` values to form a repository-relative project path.

For `Button_Basic`, the resolved path is:

```text
entries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj
```

The script resolves paths from the repository root, regardless of the caller's current working directory.

## Validation And Errors

The script uses `set -euo pipefail` and checks:

- `jq` and `dotnet` are available.
- Exactly one EntryKey argument was provided.
- The key exists exactly once in `catalog.json`.
- The catalog directory and project filename produce a safe relative path.
- The resolved project file exists.

An unknown key reports the error and prints the available entry keys. Invalid or unsafe catalog data stops before invoking `dotnet`.

Failures from restore or publish retain their original exit code and output.

## README Changes

The included-entry table will display a compact source link rather than the full `.csproj` path:

```markdown
| Key | Source |
| --- | --- |
| `Button_Basic` | [`controls/button/basic`](entries/controls/button/basic/) |
```

The build section will become:

```bash
./scripts/build-entry.sh Button_Basic
```

The existing direct `dotnet` commands will remain in detailed architecture documentation where the full build contract is relevant. Only the root README quick-start path is shortened.

## Verification

Verification will cover:

- Repository structure validation through `./scripts/verify-repository.sh`.
- Successful resolution and build of `Button_Basic`.
- Usage failure when the argument is missing or extra arguments are supplied.
- Unknown-key failure that lists `Button_Basic` as an available key.
- Confirmation that the README no longer repeats the full project path in its quick-start build section.
