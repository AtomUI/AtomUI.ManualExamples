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
