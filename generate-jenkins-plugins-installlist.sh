#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <jenkins-version>" >&2
  exit 1
fi

CORE="$1"                                          # your current Jenkins
PLUGINS=SOURCES/plugins.txt

# cache location
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/jenkins-catalog"
JSON="$CACHE/plugin-versions.json"
URL="https://updates.jenkins.io/current/plugin-versions.json.gz"

mkdir -p "$CACHE"
if ! jq -e . "$JSON" &>/dev/null; then
  echo "⇣ downloading plugin-versions.json…" >&2
  curl -fsSL "$URL" | gunzip > "$JSON"
  jq -e . "$JSON" &>/dev/null || { echo "✘ corrupt catalogue"; exit 1; }
fi

echo "▸ Resolving latest plugin releases against $CORE" >&2

# Build <id>\t<version>\t<requiredCore>
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

while IFS= read -r raw; do
  id="${raw%%#*}"
  id="${id//[[:space:]]/}"
  [[ -z $id ]] && continue

  jq -r --arg id "$id" '
    def v: gsub("[^0-9\\.]";"") | split(".") | map(select(length>0)|tonumber);

    # pick newest numeric-keyed version, no core filter
    (.plugins[$id] // {})
    | to_entries
    | map(select(.key | test("^[0-9]+(\\.[0-9]+)*$")))
    | sort_by(.key | v)
    | last?
    | if . then
        "\($id)\t\(.key)\t\(.value.requiredCore)"
      else
        "\($id)\t\t"  # no numeric version
      end
  ' "$JSON" >>"$TMP"
done < "$PLUGINS"

# Compute the floor = maximum requiredCore
FLOOR=$(cut -f3 "$TMP" \
        | grep -E '^[0-9]' \
        | sort -V \
        | tail -1)
: "${FLOOR:=0.0}"    # fallback if no plugins at all

# If your current core is too low, abort
if ! printf '%s\n%s\n' "$CORE" "$FLOOR" \
     | sort -V \
     | head -1 >/dev/null 2>&1; then
  echo -e "\n✘ Jenkins $CORE is too old.  You must run at least Jenkins $FLOOR to install these latest plugins:" >&2
  awk -F'\t' '{print "   • "$1" (requires " $3 ")"}' "$TMP" >&2
  exit 1
fi

# Otherwise emit install.list
{
  echo "# minimal Jenkins core required to run all latest plugins: $FLOOR"
  awk -F'\t' '{print ($2=="" ? $1 : $1":"$2)}' "$TMP"
} | tee install.list

echo -e "\n✓ install.list written (compatible with Jenkins ≥ $FLOOR)"
