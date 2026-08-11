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
entry_count="$(jq --arg key "${entry_key}" \
    '[.entries[] | select(.key == $key)] | length' "${catalog_file}")" ||
    fail "invalid catalog.json"

if [[ "${entry_count}" == "0" ]]; then
    printf 'error: unknown entry key: %s\n' "${entry_key}" >&2
    printf 'Available entry keys:\n' >&2
    jq -r '.entries[].key | "  \(.)"' "${catalog_file}" >&2
    exit 1
fi

[[ "${entry_count}" == "1" ]] || fail "duplicate entry key: ${entry_key}"

entry_directory="$(jq -er --arg key "${entry_key}" \
    '.entries[] | select(.key == $key) | .directory' "${catalog_file}")" ||
    fail "invalid entry directory: ${entry_key}"
project_file="$(jq -er --arg key "${entry_key}" \
    '.entries[] | select(.key == $key) | .projectFile' "${catalog_file}")" ||
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
