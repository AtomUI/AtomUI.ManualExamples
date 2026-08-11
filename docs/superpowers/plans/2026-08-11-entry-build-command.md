# Entry Build Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a short repository-level command that resolves an entry by `EntryKey`, restores locked dependencies, publishes Release output, and shortens the root README.

**Architecture:** A focused Bash wrapper reads the authoritative `catalog.json`, validates the selected entry, changes to the repository root, and invokes the existing `dotnet` build contract. A shell contract test replaces `dotnet` with a recording fake for fast argument and error-path verification, while final verification performs one real build.

**Tech Stack:** Bash, jq, .NET 10 CLI, GitHub-flavored Markdown

## Global Constraints

- `catalog.json` remains the only authoritative entry index.
- The public command is exactly `./scripts/build-entry.sh <EntryKey>`.
- The command always runs locked restore followed by Release publish with `--no-restore`.
- No catalog schema changes, configurable build modes, or shared Browser host are introduced.
- Direct `dotnet` commands remain in detailed architecture documentation; only the root README quick start is shortened.

## File Structure

- Create `scripts/build-entry.sh`: resolve and build one entry by key.
- Create `scripts/test-build-entry.sh`: fast shell contract tests using a fake `dotnet` executable.
- Modify `scripts/verify-repository.sh`: require the new scripts and run their contract tests.
- Modify `README.md`: use a compact source link and the EntryKey build command.

---

### Task 1: EntryKey Build Script

**Files:**
- Create: `scripts/test-build-entry.sh`
- Create: `scripts/build-entry.sh`

**Interfaces:**
- Consumes: `catalog.json` entries with `key`, `directory`, and `projectFile`.
- Produces: executable command `./scripts/build-entry.sh <EntryKey>`.

- [ ] **Step 1: Write the failing shell contract test**

Create `scripts/test-build-entry.sh` with this content:

```bash
#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="${repository_root}/scripts/build-entry.sh"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

expect_failure() {
    local output_file="$1"
    shift
    if "$@" >"${output_file}" 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

[[ -x "${build_script}" ]] || fail "build script is not executable: ${build_script}"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

fake_bin="${temporary_directory}/bin"
dotnet_log="${temporary_directory}/dotnet.log"
mkdir -p "${fake_bin}"

cat >"${fake_bin}/dotnet" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s' "$1" >>"${DOTNET_LOG:?}"
shift
for argument in "$@"; do
    printf '\t%s' "${argument}" >>"${DOTNET_LOG}"
done
printf '\n' >>"${DOTNET_LOG}"
EOF
chmod +x "${fake_bin}/dotnet"

expect_failure "${temporary_directory}/missing.out" "${build_script}"
grep -Fq 'Usage: ./scripts/build-entry.sh <EntryKey>' "${temporary_directory}/missing.out" ||
    fail "missing-argument usage was not reported"

expect_failure "${temporary_directory}/extra.out" "${build_script}" Button_Basic extra
grep -Fq 'Usage: ./scripts/build-entry.sh <EntryKey>' "${temporary_directory}/extra.out" ||
    fail "extra-argument usage was not reported"

expect_failure "${temporary_directory}/unknown.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${dotnet_log}" "${build_script}" MissingEntry
grep -Fq 'unknown entry key: MissingEntry' "${temporary_directory}/unknown.out" ||
    fail "unknown key error was not reported"
grep -Fq 'Button_Basic' "${temporary_directory}/unknown.out" ||
    fail "available keys were not reported"

(
    cd "${temporary_directory}"
    PATH="${fake_bin}:${PATH}" DOTNET_LOG="${dotnet_log}" \
        "${build_script}" Button_Basic
)

expected_log="${temporary_directory}/expected.log"
printf '%s\n' \
    $'restore\tentries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj\t--locked-mode' \
    $'publish\tentries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj\t-c\tRelease\t--no-restore' \
    >"${expected_log}"

cmp -s "${expected_log}" "${dotnet_log}" || {
    diff -u "${expected_log}" "${dotnet_log}" >&2 || true
    fail "dotnet invocation did not match the build contract"
}

printf 'build-entry tests passed.\n'
```

Mark it executable with `chmod +x scripts/test-build-entry.sh`.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
./scripts/test-build-entry.sh
```

Expected: FAIL because `scripts/build-entry.sh` does not exist.

- [ ] **Step 3: Implement the minimal build wrapper**

Create `scripts/build-entry.sh` with this content and mark it executable:

```bash
#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog_file="${repository_root}/catalog.json"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: ./scripts/build-entry.sh <EntryKey>\n' >&2
}

is_safe_relative_path() {
    local path="$1"
    [[ -n "${path}" ]] &&
        [[ "${path}" != /* ]] &&
        [[ "${path}" != "." ]] &&
        [[ "${path}" != ".." ]] &&
        [[ "${path}" != ../* ]] &&
        [[ "${path}" != */../* ]] &&
        [[ "${path}" != */.. ]]
}

[[ $# -eq 1 ]] || {
    usage
    exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v dotnet >/dev/null 2>&1 || fail "dotnet is required"
[[ -f "${catalog_file}" ]] || fail "missing catalog.json"

entry_key="$1"
entry_count="$(jq --arg key "${entry_key}" '[.entries[] | select(.key == $key)] | length' "${catalog_file}")" ||
    fail "invalid catalog.json"

if [[ "${entry_count}" == "0" ]]; then
    printf 'error: unknown entry key: %s\n' "${entry_key}" >&2
    printf 'Available entry keys:\n' >&2
    jq -r '.entries[].key | "  \(.)"' "${catalog_file}" >&2
    exit 1
fi

[[ "${entry_count}" == "1" ]] || fail "duplicate entry key: ${entry_key}"

entry_directory="$(jq -er --arg key "${entry_key}" '.entries[] | select(.key == $key) | .directory' "${catalog_file}")" ||
    fail "invalid entry directory: ${entry_key}"
project_file="$(jq -er --arg key "${entry_key}" '.entries[] | select(.key == $key) | .projectFile' "${catalog_file}")" ||
    fail "invalid project file: ${entry_key}"

is_safe_relative_path "${entry_directory}" || fail "unsafe entry directory: ${entry_directory}"
[[ "${entry_directory}" == entries/* ]] || fail "entry must remain under entries/: ${entry_directory}"
is_safe_relative_path "${project_file}" || fail "unsafe project file: ${project_file}"
[[ "${project_file}" != */* ]] || fail "project file must be a filename: ${project_file}"

project_path="${entry_directory}/${project_file}"
[[ -f "${repository_root}/${project_path}" ]] || fail "missing project: ${project_path}"

cd "${repository_root}"
dotnet restore "${project_path}" --locked-mode
dotnet publish "${project_path}" -c Release --no-restore
```

Run `chmod +x scripts/build-entry.sh`.

- [ ] **Step 4: Run the contract test to verify it passes**

Run:

```bash
./scripts/test-build-entry.sh
```

Expected: `build-entry tests passed.` and exit code 0.

- [ ] **Step 5: Commit the script and tests**

```bash
git add scripts/build-entry.sh scripts/test-build-entry.sh
git commit -m "feat: add entry build command"
```

### Task 2: Repository And README Integration

**Files:**
- Modify: `scripts/test-build-entry.sh`
- Modify: `scripts/verify-repository.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: `./scripts/build-entry.sh Button_Basic` from Task 1.
- Produces: repository verification that checks the command contract and root documentation that exposes the short command.

- [ ] **Step 1: Add failing documentation assertions**

Append these assertions before the final success message in `scripts/test-build-entry.sh`:

```bash
grep -Fq './scripts/build-entry.sh Button_Basic' "${repository_root}/README.md" ||
    fail "README does not use the EntryKey build command"
grep -Fq '[`controls/button/basic`](entries/controls/button/basic/)' "${repository_root}/README.md" ||
    fail "README does not use the compact source link"
if grep -Fq 'dotnet restore entries/controls/button/basic/' "${repository_root}/README.md"; then
    fail "README still contains the long quick-start restore command"
fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
./scripts/test-build-entry.sh
```

Expected: FAIL because the root README still contains the long direct build commands.

- [ ] **Step 3: Shorten the root README**

Change the included-entry table to:

```markdown
| Key | Source | AtomUI |
| --- | --- | --- |
| `Button_Basic` | [`controls/button/basic`](entries/controls/button/basic/) | `6.1.2` |
```

Replace the two direct build commands in `Build one entry` with:

```bash
./scripts/build-entry.sh Button_Basic
```

- [ ] **Step 4: Integrate contract tests into repository verification**

After `required_root_files`, add:

```bash
required_executables=(
    "scripts/build-entry.sh"
    "scripts/test-build-entry.sh"
)

for file in "${required_executables[@]}"; do
    [[ -x "${file}" ]] || fail "missing executable file: ${file}"
done
```

Then run this before the final verification message:

```bash
"${repository_root}/scripts/test-build-entry.sh"
```

before printing the final repository verification message.

- [ ] **Step 5: Run fast verification**

Run:

```bash
./scripts/test-build-entry.sh
./scripts/verify-repository.sh
```

Expected: both commands exit 0; the contract test prints `build-entry tests passed.` and repository verification prints `Verified 1 entry(s).`

- [ ] **Step 6: Run one real entry build**

Run:

```bash
./scripts/build-entry.sh Button_Basic
```

Expected: locked restore succeeds and Release publish exits 0.

- [ ] **Step 7: Commit documentation and verification integration**

```bash
git add README.md scripts/test-build-entry.sh scripts/verify-repository.sh
git commit -m "docs: simplify entry build instructions"
```

### Task 3: Final Verification

**Files:**
- Verify only; no planned changes.

**Interfaces:**
- Consumes: all changes from Tasks 1 and 2.
- Produces: fresh evidence that the branch is ready to push.

- [ ] **Step 1: Run the complete verification set**

```bash
./scripts/test-build-entry.sh
./scripts/verify-repository.sh
./scripts/build-entry.sh Button_Basic
git diff --check origin/release/6.0...HEAD
git status --short --branch
```

Expected: every command exits 0, the real Release publish succeeds, `git diff --check` is silent, and the working tree is clean.
