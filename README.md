# AtomUI Manual Examples

Official, independently buildable Avalonia Browser entries used by the AtomUI manual.

## Documentation

- [Documentation overview](docs/overview.md): maintenance entry point, reading order, ownership, invariants, and commands.
- [Repository architecture](docs/architecture.md): project structure, design rationale, catalog, metadata, dependencies, shared source, and build contract.
- [AtomIdea project preview architecture](docs/project-preview-architecture.md): WebOS synchronization, Docker build, Nginx artifacts, Markdown hydration, source display, and SPA shared Runtime.

## Repository rules

- `catalog.json` is the only authoritative index for entry discovery and project location.
- Every entry is an independent executable project with its own `.csproj`, `Program.cs`, `App.axaml`, dependencies, and lock file.
- The root solution is an IDE catalog only. Build an entry by targeting its project file directly.
- Entries do not share an executable Browser host. Shared class libraries are allowed only when registered in `catalog.json`.
- Every entry references `AtomUI.Fonts.AlibabaSans` and registers Alibaba Sans as its default Latin font.
- Entries must not reference Chinese font packages or Chinese system font families.
- Published artifacts are generated offline and loaded lazily by the manual application.

## Included entries

| Key | Project | AtomUI |
| --- | --- | --- |
| `Button_Basic` | `entries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj` | `6.1.2` |

## Build one entry

```bash
dotnet restore entries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj --locked-mode
dotnet publish entries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj -c Release --no-restore
```

## Verify the repository

```bash
./scripts/verify-repository.sh
```
