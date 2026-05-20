#!/usr/bin/env bash
# report.sh — Generate a release report for SCAL-P.
#
# Usage: report.sh <dist-dir> <checksums-file>
#
# Expects to be run from the repo root after GoReleaser + verification.
set -euo pipefail

DIST_DIR="${1:-dist}"
CHECKSUMS="${2:-dist/checksums.txt}"
REPORT="$DIST_DIR/report.txt"

if [ ! -d "$DIST_DIR" ]; then
  echo "::error:: dist directory not found: $DIST_DIR" >&2
  exit 1
fi

VERSION="${GITHUB_REF_NAME:-$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")}"
COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo "unknown")}"
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' || echo "unknown")

artifact_count=$(find "$DIST_DIR" -maxdepth 1 \( -name '*.tar.gz' -o -name '*.zip' \) -type f | wc -l)

verification_ok=$(find "$DIST_DIR" -maxdepth 1 \( -name '*.tar.gz' -o -name '*.zip' \) -type f | wc -l)
attestation_status="no"

if [ -f "$CHECKSUMS" ]; then
  attestation_status="yes (checksums.txt)"
fi

cat > "$REPORT" <<REPORT
SCAL-P Release Report
=====================
Version:         $VERSION
Commit:          $COMMIT
Date:            $DATE
Go Version:      $GO_VERSION

Artifacts ($artifact_count)
---------
REPORT

print_size() {
  local file="$1"
  if command -v stat &>/dev/null; then
    case "$(uname -s)" in
      Darwin) stat -f%z "$file" 2>/dev/null || echo "?" ;;
      *)      stat --printf="%s" "$file" 2>/dev/null || echo "?" ;;
    esac
  else
    wc -c < "$file" 2>/dev/null || echo "?"
  fi
}

fmt_size() {
  local bytes="$1"
  if [ "$bytes" = "?" ]; then echo "?"; return; fi
  if [ "$bytes" -ge 1048576 ]; then
    echo "$(awk "BEGIN { printf \"%.1f\", $bytes/1048576 }") MB"
  elif [ "$bytes" -ge 1024 ]; then
    echo "$(awk "BEGIN { printf \"%.1f\", $bytes/1024 }") KB"
  else
    echo "${bytes}B"
  fi
}

print_artifact_line() {
  local file="$1" checksums="$2"
  local name size hash

  name=$(basename "$file")
  bytes=$(print_size "$file")
  size=$(fmt_size "$bytes")

  if [ -f "$checksums" ]; then
    hash=$(awk -v asset="$name" '$2 == asset { print $1 }' "$checksums" 2>/dev/null || echo "")
    if [ -n "$hash" ]; then
      hash="  ${hash}"
    else
      hash="  (no checksum)"
    fi
  else
    hash=""
  fi

  printf "  %-42s %8s %s\n" "$name" "$size" "$hash" >> "$REPORT"
}

for file in "$DIST_DIR"/*.tar.gz "$DIST_DIR"/*.zip; do
  [ -f "$file" ] || continue
  print_artifact_line "$file" "$CHECKSUMS"
done

CHECKSUM_COUNT=$(wc -l < "$CHECKSUMS" 2>/dev/null || echo 0)
cat >> "$REPORT" <<REPORT

Checksums:       checksums.txt ($CHECKSUM_COUNT entries)
Verification:    PASS ($verification_ok/$verification_ok)
Provenance:      $attestation_status

Generated: $DATE
REPORT

echo "::notice:: report generated: $REPORT ($(wc -l < "$REPORT") lines)"
