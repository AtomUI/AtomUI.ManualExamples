#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
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

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v rg >/dev/null 2>&1 || fail "ripgrep is required"

required_root_files=(
    "README.md"
    "global.json"
    "catalog.json"
    "AtomUI.ManualExamples.slnx"
    "docs/architecture.md"
)

for file in "${required_root_files[@]}"; do
    [[ -f "${file}" ]] || fail "missing root file: ${file}"
done

required_executables=(
    "scripts/build-entry.sh"
    "scripts/test-build-entry.sh"
)

for file in "${required_executables[@]}"; do
    [[ -x "${file}" ]] || fail "missing executable file: ${file}"
done

[[ ! -e "examples.manifest.json" ]] || fail "legacy examples.manifest.json is not allowed"
[[ ! -e "examples" ]] || fail "legacy examples directory is not allowed"
[[ -d "entries" ]] || fail "missing entries directory"
[[ ! -e "Directory.Packages.props" ]] || fail "root Directory.Packages.props is not allowed"

if find entries -type d \( -name bin -o -name obj \) -prune -o -name example.json -type f -print | grep -q .; then
    fail "legacy example.json is not allowed"
fi

jq -e '
    .schemaVersion == 1 and
    .productKey == "AtomUI" and
    .entriesRoot == "entries" and
    (.entries | type == "array" and length > 0) and
    (.entries | all(
        (.key | type == "string" and test("^[A-Za-z_][A-Za-z0-9_]*$")) and
        (.directory | type == "string" and startswith("entries/")) and
        .metadataFile == "metadata.json" and
        (.projectFile | type == "string" and test("^[^/]+\\.csproj$"))
    )) and
    (.sharedProjects | type == "array")
' catalog.json >/dev/null || fail "invalid catalog.json"

entry_count=0
seen_keys=""

while IFS=$'\t' read -r key entry_dir metadata_file project_file; do
    entry_count=$((entry_count + 1))

    printf '%s\n' "${seen_keys}" | grep -Fqx "${key}" && fail "duplicate entry key: ${key}"
    seen_keys="${seen_keys}${key}"$'\n'

    is_safe_relative_path "${entry_dir}" || fail "unsafe entry directory: ${entry_dir}"
    [[ "${entry_dir}" == entries/* ]] || fail "entry must remain under entries/: ${entry_dir}"
    [[ -d "${entry_dir}" ]] || fail "missing entry directory: ${entry_dir}"
    [[ "${metadata_file}" == "metadata.json" ]] || fail "metadataFile must be metadata.json: ${key}"
    [[ -f "${entry_dir}/${metadata_file}" ]] || fail "missing metadata: ${entry_dir}/${metadata_file}"
    [[ -f "${entry_dir}/${project_file}" ]] || fail "missing project: ${entry_dir}/${project_file}"

    metadata="${entry_dir}/${metadata_file}"
    metadata_key="$(jq -er '.key | select(test("^[A-Za-z_][A-Za-z0-9_]*$"))' "${metadata}")" ||
        fail "invalid metadata key: ${metadata}"
    [[ "${metadata_key}" == "${key}" ]] || fail "catalog and metadata key mismatch: ${key}"

    jq -e '
        .schemaVersion == 1 and
        (.title | type == "string" and length > 0) and
        (.description | type == "string") and
        (.entryControlType | type == "string" and length > 0) and
        (.preview.width | type == "number" and . > 0) and
        (.preview.height | type == "number" and . > 0) and
        (.preview.supportsDarkMode | type == "boolean") and
        (.sources | type == "array" and length > 0) and
        ([.sources[] | select(.primary == true)] | length == 1) and
        (.sources | all(
            (.path | type == "string" and length > 0) and
            (.displayName | type == "string" and length > 0) and
            (.language | type == "string" and length > 0) and
            (.primary | type == "boolean") and
            (.order | type == "number")
        )) and
        (.sourceArchive.includeProject | type == "boolean") and
        (.sourceArchive.includeSharedProjects | type == "boolean")
    ' "${metadata}" >/dev/null || fail "invalid metadata: ${metadata}"

    while IFS= read -r source_path; do
        is_safe_relative_path "${source_path}" || fail "unsafe source path: ${metadata}: ${source_path}"
        [[ -f "${entry_dir}/${source_path}" ]] || fail "missing source file: ${entry_dir}/${source_path}"
    done < <(jq -r '.sources[].path' "${metadata}")

    [[ -f "${entry_dir}/Program.cs" ]] || fail "missing Program.cs: ${entry_dir}"
    [[ -f "${entry_dir}/App.axaml" ]] || fail "missing App.axaml: ${entry_dir}"
    [[ -f "${entry_dir}/packages.lock.json" ]] || fail "missing packages.lock.json: ${entry_dir}"
    [[ -f "${entry_dir}/wwwroot/main.js" ]] || fail "missing Browser startup script: ${entry_dir}"
    grep -Fq "splash-close" "${entry_dir}/wwwroot/main.js" ||
        fail "Browser startup must close the splash after runtime initialization: ${entry_dir}"

    grep -Fq '<PackageReference Include="AtomUI.Fonts.AlibabaSans" Version="6.1.2" />' \
        "${entry_dir}/${project_file}" ||
        fail "entries must reference the Alibaba Sans Latin font package: ${entry_dir}"
    grep -Fq 'builder.UseAlibabaSansFont();' "${entry_dir}/App.axaml.cs" ||
        fail "entries must register Alibaba Sans: ${entry_dir}"
    grep -Fq 'builder.WithDefaultFontFamily("fonts:AlibabaSans#Alibaba Sans, $Default");' \
        "${entry_dir}/App.axaml.cs" ||
        fail "entries must use Alibaba Sans as the default font: ${entry_dir}"

    if rg -n 'AlibabaPuHuiTi|Noto[^"<]*CJK|Microsoft\.YaHei|Microsoft YaHei|PingFang' \
        "${entry_dir}/${project_file}" "${entry_dir}/"*.cs "${entry_dir}/"*.axaml >/dev/null; then
        fail "entries must not reference Chinese font packages or families: ${entry_dir}"
    fi

    project_count="$(find "${entry_dir}" -maxdepth 1 -name '*.csproj' -type f | wc -l | tr -d ' ')"
    [[ "${project_count}" == "1" ]] || fail "each entry must contain exactly one executable project: ${entry_dir}"
done < <(jq -r '.entries[] | [.key, .directory, .metadataFile, .projectFile] | @tsv' catalog.json)

[[ ${entry_count} -gt 0 ]] || fail "no entries found"

metadata_count="$(find entries -type d \( -name bin -o -name obj \) -prune -o -name metadata.json -type f -print | wc -l | tr -d ' ')"
[[ "${metadata_count}" == "${entry_count}" ]] || fail "catalog entries and metadata.json count differ"

while IFS=$'\t' read -r shared_key project_file; do
    [[ "${shared_key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "invalid shared project key: ${shared_key}"
    is_safe_relative_path "${project_file}" || fail "unsafe shared project path: ${project_file}"
    [[ "${project_file}" == shared/* ]] || fail "shared project must remain under shared/: ${project_file}"
    [[ -f "${project_file}" ]] || fail "missing shared project: ${project_file}"
    [[ ! -f "$(dirname "${project_file}")/Program.cs" ]] || fail "shared project cannot contain Program.cs: ${project_file}"
done < <(jq -r '.sharedProjects[] | [.key, .projectFile] | @tsv' catalog.json)

dotnet sln AtomUI.ManualExamples.slnx list >/dev/null
"${repository_root}/scripts/test-build-entry.sh"

printf 'Verified %d entry(s).\n' "${entry_count}"
