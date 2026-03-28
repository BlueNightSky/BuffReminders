#!/usr/bin/env bash
# Verify locale key sync:
# 1. All L["..."] keys used in source files must be defined in enUS.lua
# 2. All keys defined in enUS.lua must be used in source files
# 3. All keys in translation files must exist in enUS.lua (no typos/extras)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCALES_DIR="$ROOT/Locales"

# Collect keys
used=$(grep -rhoP 'L\["[^"]+"\]' "$ROOT" --include='*.lua' --exclude-dir=Locales --exclude-dir=Libs --exclude-dir=ignored | sed 's/L\["\(.*\)"\]/\1/' | sort -u)
defined=$(grep -oP 'english\["[^"]+"\]' "$LOCALES_DIR/enUS.lua" | sed 's/english\["\(.*\)"\]/\1/' | sort -u)

errors=0

# Check source usage vs enUS definitions
missing=$(comm -23 <(echo "$used") <(echo "$defined"))
unused=$(comm -13 <(echo "$used") <(echo "$defined"))

if [ -n "$missing" ]; then
    echo "USED IN SOURCE BUT NOT DEFINED in enUS.lua:"
    echo "$missing" | sed 's/^/  /'
    errors=1
fi

if [ -n "$unused" ]; then
    echo "DEFINED IN enUS.lua BUT NOT USED in source files:"
    echo "$unused" | sed 's/^/  /'
    errors=1
fi

# Check each translation file: must be empty (0 keys) or complete (all keys)
enUS_count=$(echo "$defined" | wc -l)
for file in "$LOCALES_DIR"/*.lua; do
    locale=$(basename "$file" .lua)
    [ "$locale" = "enUS" ] && continue
    trans_keys=$(grep -v '^\s*--' "$file" | grep -oP 'L\["[^"]+"\]' 2>/dev/null | sed 's/L\["\(.*\)"\]/\1/' | sort -u || true)
    count=$([ -n "$trans_keys" ] && echo "$trans_keys" | wc -l || echo 0)
    if [ "$count" -ne 0 ] && [ "$count" -ne "$enUS_count" ]; then
        echo "INCOMPLETE: $locale.lua has $count/$enUS_count keys (must be 0 or $enUS_count)"
        errors=1
    fi
    [ -z "$trans_keys" ] && continue
    extra=$(comm -23 <(echo "$trans_keys") <(echo "$defined"))
    if [ -n "$extra" ]; then
        echo "UNKNOWN KEYS in $locale.lua (not in enUS.lua):"
        echo "$extra" | sed 's/^/  /'
        errors=1
    fi
done

if [ "$errors" -eq 0 ]; then
    enUS_count=$(echo "$defined" | wc -l)
    echo "Locales OK ($enUS_count keys)"
fi

exit $errors
