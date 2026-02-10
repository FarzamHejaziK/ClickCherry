#!/usr/bin/env bash
set -euo pipefail

WORKLOG_PATH="${1:-.docs/worklog.md}"
LEGACY_PATH="${2:-.docs/legacy_worklog.md}"
KEEP_ENTRIES="${KEEP_ENTRIES:-10}"

if ! [[ "$KEEP_ENTRIES" =~ ^[0-9]+$ ]] || [ "$KEEP_ENTRIES" -lt 1 ]; then
  echo "KEEP_ENTRIES must be a positive integer. Got: $KEEP_ENTRIES" >&2
  exit 1
fi

if [ ! -f "$WORKLOG_PATH" ]; then
  echo "Worklog file not found: $WORKLOG_PATH" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

entry_lines_file="$tmp_dir/entry_lines.txt"
if command -v rg >/dev/null 2>&1; then
  rg -n '^## Entry$' "$WORKLOG_PATH" | cut -d: -f1 > "$entry_lines_file"
else
  grep -n '^## Entry$' "$WORKLOG_PATH" | cut -d: -f1 > "$entry_lines_file"
fi

entry_count="$(wc -l < "$entry_lines_file" | tr -d '[:space:]')"
if [ "$entry_count" -eq 0 ]; then
  echo "No entries found in $WORKLOG_PATH"
  exit 0
fi

if [ "$entry_count" -le "$KEEP_ENTRIES" ]; then
  echo "No rotation needed: $entry_count entries <= keep limit $KEEP_ENTRIES"
  exit 0
fi

# Worklog entries are ordered newest first; keep the first N `## Entry` blocks.
first_entry_line="$(head -n 1 "$entry_lines_file")"
first_archived_index=$((KEEP_ENTRIES + 1))
first_archived_line="$(sed -n "${first_archived_index}p" "$entry_lines_file")"

header_file="$tmp_dir/header.md"
archived_entries_file="$tmp_dir/archived_entries.md"
recent_entries_file="$tmp_dir/recent_entries.md"

sed -n "1,$((first_entry_line - 1))p" "$WORKLOG_PATH" > "$header_file"
sed -n "${first_entry_line},$((first_archived_line - 1))p" "$WORKLOG_PATH" > "$recent_entries_file"
sed -n "${first_archived_line},\$p" "$WORKLOG_PATH" > "$archived_entries_file"

if [ ! -f "$LEGACY_PATH" ]; then
  cat > "$LEGACY_PATH" <<'LEGACY_HEADER'
---
description: Historical worklog entries archived from `.docs/worklog.md`.
---

# Legacy Worklog
LEGACY_HEADER
fi

if [ -s "$archived_entries_file" ]; then
  if [ -s "$LEGACY_PATH" ]; then
    printf "\n" >> "$LEGACY_PATH"
  fi
  cat "$archived_entries_file" >> "$LEGACY_PATH"
fi

cat "$header_file" "$recent_entries_file" > "$WORKLOG_PATH"

echo "Rotated worklog: kept latest $KEEP_ENTRIES entries in $WORKLOG_PATH and archived older entries to $LEGACY_PATH"
