#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BATS_VERSION="1.13.0"
BATS_ARCHIVE_SHA256="a85e12b8828271a152b338ca8109aa23493b57950987c8e6dff97ba492772ff3"
BATS_ARCHIVE_URL="https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz"

TOOLS_DIR="$ROOT_DIR/.tools"
BATS_INSTALL_DIR="$TOOLS_DIR/bats"
BATS_BIN="$BATS_INSTALL_DIR/bin/bats"
VERSION_MARKER="$BATS_INSTALL_DIR/.bats-version"

log() {
  printf '[ensure-bats] %s\n' "$1"
}

fail() {
  printf '[ensure-bats] ERROR: %s\n' "$1" >&2
  exit 1
}

sha256_file() {
  local file_path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return
  fi

  fail "Neither 'sha256sum' nor 'shasum' is available; cannot verify pinned Bats archive checksum."
}

download_archive() {
  local output_path="$1"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error \
      --connect-timeout 15 \
      --max-time 180 \
      --retry 3 \
      --retry-delay 1 \
      --output "$output_path" \
      "$BATS_ARCHIVE_URL"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=3 --timeout=30 --output-document="$output_path" "$BATS_ARCHIVE_URL"
    return
  fi

  fail "Neither 'curl' nor 'wget' is available; cannot download pinned Bats archive."
}

installed_version_matches_pin() {
  local detected_version
  local marker_version

  [[ -x "$BATS_BIN" ]] || return 1
  [[ -f "$VERSION_MARKER" ]] || return 1

  marker_version="$(<"$VERSION_MARKER")"
  [[ "$marker_version" == "$BATS_VERSION" ]] || return 1

  detected_version="$("$BATS_BIN" --version 2>/dev/null || true)"
  [[ "$detected_version" == "Bats ${BATS_VERSION}" ]]
}

main() {
  local tmp_dir
  local stage_dir
  local archive_path
  local extracted_dir
  local expected_dir_name
  local detected_sha
  local tar_roots
  local stage_version

  if installed_version_matches_pin; then
    log "Pinned Bats already available at $BATS_BIN (v$BATS_VERSION)."
    exit 0
  fi

  mkdir -p "$TOOLS_DIR"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ensure-bats.XXXXXX")"
  stage_dir="$TOOLS_DIR/.bats-stage.$$.$RANDOM"
  archive_path="$tmp_dir/bats-core-v${BATS_VERSION}.tar.gz"
  expected_dir_name="bats-core-${BATS_VERSION}"

  cleanup() {
    if [[ -n "${tmp_dir:-}" ]]; then
      rm -rf "$tmp_dir"
    fi
    if [[ -n "${stage_dir:-}" ]]; then
      rm -rf "$stage_dir"
    fi
  }
  trap cleanup EXIT

  log "Bootstrapping pinned Bats v$BATS_VERSION."
  log "Downloading archive: $BATS_ARCHIVE_URL"
  download_archive "$archive_path" || fail "Download failed for pinned Bats archive (v$BATS_VERSION)."

  detected_sha="$(sha256_file "$archive_path")"
  if [[ "$detected_sha" != "$BATS_ARCHIVE_SHA256" ]]; then
    fail "Checksum mismatch for v$BATS_VERSION archive (expected $BATS_ARCHIVE_SHA256, got $detected_sha)."
  fi
  log "Checksum verified: $detected_sha"

  tar_roots="$(tar -tzf "$archive_path" | awk -F/ 'NF { print $1 }' | sort -u)"
  if [[ "$tar_roots" != "$expected_dir_name" ]]; then
    fail "Unexpected archive layout for v$BATS_VERSION (expected root '$expected_dir_name', got '$tar_roots')."
  fi

  tar -xzf "$archive_path" -C "$tmp_dir" || fail "Failed to extract pinned Bats archive."
  extracted_dir="$tmp_dir/$expected_dir_name"

  [[ -d "$extracted_dir" ]] || fail "Extracted archive root not found: $extracted_dir"
  [[ -f "$extracted_dir/install.sh" ]] || fail "Extracted archive is missing install.sh: $extracted_dir/install.sh"

  bash "$extracted_dir/install.sh" "$stage_dir" || fail "Pinned Bats install script failed for v$BATS_VERSION."

  [[ -x "$stage_dir/bin/bats" ]] || fail "Installed stage is missing executable bats binary: $stage_dir/bin/bats"

  stage_version="$("$stage_dir/bin/bats" --version 2>/dev/null || true)"
  if [[ "$stage_version" != "Bats ${BATS_VERSION}" ]]; then
    fail "Installed bats version mismatch (expected 'Bats $BATS_VERSION', got '$stage_version')."
  fi

  printf '%s\n' "$BATS_VERSION" >"$stage_dir/.bats-version"

  rm -rf "$BATS_INSTALL_DIR"
  mv "$stage_dir" "$BATS_INSTALL_DIR"

  log "Pinned Bats installed to $BATS_BIN"
}

main "$@"
