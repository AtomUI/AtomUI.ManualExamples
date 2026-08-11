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

expect_status() {
    local expected_status="$1"
    local output_file="$2"
    shift 2

    set +e
    "$@" >"${output_file}" 2>&1
    local actual_status=$?
    set -e

    [[ ${actual_status} -eq ${expected_status} ]] ||
        fail "expected exit ${expected_status}, got ${actual_status}: $*"
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
command_name="$1"
printf '%s' "${command_name}" >>"${DOTNET_LOG:?}"
shift
for argument in "$@"; do
    printf '\t%s' "${argument}" >>"${DOTNET_LOG}"
done
printf '\n' >>"${DOTNET_LOG}"
if [[ "${DOTNET_FAIL_COMMAND:-}" == "${command_name}" ]]; then
    exit "${DOTNET_FAIL_STATUS:-1}"
fi
EOF
chmod +x "${fake_bin}/dotnet"

create_fixture() {
    local name="$1"
    fixture_path="${temporary_directory}/fixtures/${name}"
    mkdir -p "${fixture_path}/scripts" "${fixture_path}/entries/example"
    cp "${build_script}" "${fixture_path}/scripts/build-entry.sh"
    chmod +x "${fixture_path}/scripts/build-entry.sh"
}

write_catalog() {
    local fixture="$1"
    local entry_directory="$2"
    local project_file="$3"
    jq -n \
        --arg directory "${entry_directory}" \
        --arg projectFile "${project_file}" \
        '{entries: [{key: "TestEntry", directory: $directory, projectFile: $projectFile}]}' \
        >"${fixture}/catalog.json"
}

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

outside_directory="${temporary_directory}/outside"
mkdir -p "${outside_directory}"
touch "${outside_directory}/Outside.csproj"

create_fixture "project-symlink"
write_catalog "${fixture_path}" "entries/example" "Test.csproj"
ln -s "${outside_directory}/Outside.csproj" "${fixture_path}/entries/example/Test.csproj"
expect_failure "${temporary_directory}/project-symlink.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/project-symlink.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'project must not be a symbolic link: entries/example/Test.csproj' \
    "${temporary_directory}/project-symlink.out" ||
    fail "project symlink error was not reported"

create_fixture "directory-symlink"
rm -rf "${fixture_path}/entries/example"
ln -s "${outside_directory}" "${fixture_path}/entries/example"
write_catalog "${fixture_path}" "entries/example" "Outside.csproj"
expect_failure "${temporary_directory}/directory-symlink.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/directory-symlink.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'entry directory resolves outside entries/: entries/example' \
    "${temporary_directory}/directory-symlink.out" ||
    fail "directory symlink error was not reported"

create_fixture "project-extension"
touch "${fixture_path}/entries/example/Test.txt"
write_catalog "${fixture_path}" "entries/example" "Test.txt"
expect_failure "${temporary_directory}/project-extension.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/project-extension.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'project file must be a .csproj filename: Test.txt' \
    "${temporary_directory}/project-extension.out" ||
    fail "project extension error was not reported"

create_fixture "malformed-catalog"
printf '{\n' >"${fixture_path}/catalog.json"
expect_failure "${temporary_directory}/malformed-catalog.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/malformed-catalog.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'invalid catalog.json' "${temporary_directory}/malformed-catalog.out" ||
    fail "malformed catalog error was not reported"

create_fixture "duplicate-key"
touch "${fixture_path}/entries/example/Test.csproj"
jq -n '{entries: [
    {key: "TestEntry", directory: "entries/example", projectFile: "Test.csproj"},
    {key: "TestEntry", directory: "entries/example", projectFile: "Test.csproj"}
]}' >"${fixture_path}/catalog.json"
expect_failure "${temporary_directory}/duplicate-key.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/duplicate-key.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'duplicate entry key: TestEntry' "${temporary_directory}/duplicate-key.out" ||
    fail "duplicate key error was not reported"

create_fixture "unsafe-directory"
write_catalog "${fixture_path}" "../outside" "Outside.csproj"
expect_failure "${temporary_directory}/unsafe-directory.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/unsafe-directory.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'unsafe entry directory: ../outside' "${temporary_directory}/unsafe-directory.out" ||
    fail "unsafe directory error was not reported"

create_fixture "unsafe-project"
write_catalog "${fixture_path}" "entries/example" "../Outside.csproj"
expect_failure "${temporary_directory}/unsafe-project.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/unsafe-project.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'unsafe project file: ../Outside.csproj' "${temporary_directory}/unsafe-project.out" ||
    fail "unsafe project file error was not reported"

create_fixture "missing-project"
write_catalog "${fixture_path}" "entries/example" "Missing.csproj"
expect_failure "${temporary_directory}/missing-project.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/missing-project.log" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
grep -Fq 'missing project: entries/example/Missing.csproj' "${temporary_directory}/missing-project.out" ||
    fail "missing project error was not reported"

create_fixture "restore-failure"
touch "${fixture_path}/entries/example/Test.csproj"
write_catalog "${fixture_path}" "entries/example" "Test.csproj"
expect_status 23 "${temporary_directory}/restore-failure.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/restore-failure.log" \
    DOTNET_FAIL_COMMAND="restore" DOTNET_FAIL_STATUS="23" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
[[ "$(wc -l <"${temporary_directory}/restore-failure.log" | tr -d ' ')" == "1" ]] ||
    fail "publish ran after restore failed"

create_fixture "publish-failure"
touch "${fixture_path}/entries/example/Test.csproj"
write_catalog "${fixture_path}" "entries/example" "Test.csproj"
expect_status 24 "${temporary_directory}/publish-failure.out" env PATH="${fake_bin}:${PATH}" \
    DOTNET_LOG="${temporary_directory}/publish-failure.log" \
    DOTNET_FAIL_COMMAND="publish" DOTNET_FAIL_STATUS="24" \
    "${fixture_path}/scripts/build-entry.sh" TestEntry
[[ "$(wc -l <"${temporary_directory}/publish-failure.log" | tr -d ' ')" == "2" ]] ||
    fail "publish failure did not preserve the command sequence"

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

grep -Fq './scripts/build-entry.sh Button_Basic' "${repository_root}/README.md" ||
    fail "README does not use the EntryKey build command"
grep -Fq '[`controls/button/basic`](entries/controls/button/basic/)' "${repository_root}/README.md" ||
    fail "README does not use the compact source link"
if grep -Fq 'dotnet restore entries/controls/button/basic/' "${repository_root}/README.md"; then
    fail "README still contains the long quick-start restore command"
fi

printf 'build-entry tests passed.\n'
