#!/usr/bin/env bash
# The setup-sorus action (action.yml): install the Sorus client for this
# runner, checked against the release's SHA256SUMS, the `sha256` input when
# one is given, and the release's signed provenance attestation.
set -euo pipefail

readonly releases=https://github.com/sorus-run/sorus/releases
# The workflow that builds and signs every release, as its certificate names it.
readonly source_repository=LorenaLabs/lathe-app
readonly signer_workflow="$source_repository/.github/workflows/client-release.yml"

refuse() {
  echo "::error title=setup-sorus::$*"
  exit 1
}

version="${SORUS_VERSION:-latest}"
if [[ "$version" = latest ]]; then
  # The latest release's page is where releases/latest redirects.
  resolved="$(curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o /dev/null -w '%{url_effective}' "$releases/latest")" \
    || refuse "could not resolve the latest release"
  version="${resolved##*/tag/v}"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || refuse "version must be three numbers, such as 0.3.0, or latest; not '$version'"

case "${RUNNER_OS:-}/${RUNNER_ARCH:-}" in
  Linux/X64) target=x86_64-unknown-linux-musl ;;
  Linux/ARM64) target=aarch64-unknown-linux-musl ;;
  macOS/ARM64) target=aarch64-apple-darwin ;;
  macOS/X64) target=x86_64-apple-darwin ;;
  *) refuse "no release file for ${RUNNER_OS:-?} ${RUNNER_ARCH:-?}; files exist for Linux and macOS on X64 and ARM64" ;;
esac

file="sorus-$version-$target"
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/setup-sorus.XXXXXXXX")"
trap 'rm -rf "$scratch"' EXIT
fetch() {
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$scratch/$1" "$releases/download/v$version/$1" \
    || refuse "could not download $releases/download/v$version/$1"
}
fetch "$file"
fetch SHA256SUMS

if command -v sha256sum > /dev/null; then
  actual="$(sha256sum "$scratch/$file" | cut -d ' ' -f 1)"
else
  actual="$(shasum -a 256 "$scratch/$file" | cut -d ' ' -f 1)"
fi
expected="$(awk -v name="$file" '$2 == name { print $1 }' "$scratch/SHA256SUMS")"
[[ -n "$expected" ]] || refuse "SHA256SUMS of $version names no $file"
[[ "$actual" = "$expected" ]] || refuse "$file has sha256 $actual, SHA256SUMS says $expected"
pinned="$(printf '%s' "${SORUS_SHA256:-}" | tr '[:upper:]' '[:lower:]')"
if [[ -n "$pinned" && "$actual" != "$pinned" ]]; then
  refuse "$file has sha256 $actual, the sha256 input says $pinned"
fi
echo "setup-sorus: $file sha256 $actual matches SHA256SUMS${SORUS_SHA256:+ and the sha256 input}"

case "${SORUS_VERIFY_ATTESTATION:-true}" in
  true)
    command -v gh > /dev/null \
      || refuse "gh is not on this runner, so the attestation cannot be checked; set verify-attestation: false to rely on SHA256SUMS alone"
    fetch "sorus-$version.provenance.jsonl"
    gh attestation verify "$scratch/$file" --bundle "$scratch/sorus-$version.provenance.jsonl" \
      --repo "$source_repository" --signer-workflow "$signer_workflow" \
      --source-ref refs/heads/main --deny-self-hosted-runners > /dev/null \
      || refuse "the provenance attestation of $file did not verify"
    echo "setup-sorus: provenance attestation verified: built by $signer_workflow on refs/heads/main"
    ;;
  false) echo "setup-sorus: verify-attestation is false; the attestation was not checked" ;;
  *) refuse "verify-attestation is true or false, not '$SORUS_VERIFY_ATTESTATION'" ;;
esac

directory="${RUNNER_TEMP:?}/sorus-$version/bin"
mkdir -p "$directory"
install -m 0755 "$scratch/$file" "$directory/sorus"
ln -sf sorus "$directory/cargo-sorus"
printed="$("$directory/sorus" --version)"
[[ "$printed" == "sorus $version ("* ]] || refuse "sorus --version printed '$printed', expected sorus $version"
echo "$directory" >> "$GITHUB_PATH"
{
  echo "version=$version"
  echo "directory=$directory"
} >> "$GITHUB_OUTPUT"
echo "setup-sorus: installed $printed as sorus and cargo-sorus in $directory"
