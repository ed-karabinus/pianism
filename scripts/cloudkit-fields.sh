#!/usr/bin/env bash
# Reduces a CloudKit schema export (`xcrun cktool export-schema`) to one sorted `RecordType.field TYPE` line
# per field, leaving out system fields, permissions and indexes, to diff with docs/cloudkit/schema-v1-fields.txt
# before the deploy (ADR 0008).
# Usage: scripts/cloudkit-fields.sh <export.ckdb>
set -euo pipefail

awk '
  /RECORD TYPE/ { type = $3; gsub(/"/, "", type); next }
  /^[[:space:]]*\)/ { type = ""; next }
  type == "" || $1 !~ /^"?[A-Za-z]/ || /^[[:space:]]*(GRANT|"___)/ { next }
  {
    line = $0
    gsub(/"|,[[:space:]]*$|[[:space:]]+(QUERYABLE|SORTABLE|SEARCHABLE)/, "", line)
    sub(/^[[:space:]]+/, "", line)
    field = line; sub(/[[:space:]].*/, "", field)
    kind = line; sub(/^[^[:space:]]+[[:space:]]+/, "", kind)
    print type "." field " " kind
  }
' "$1" | sort
