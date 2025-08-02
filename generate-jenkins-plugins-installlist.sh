#!/usr/bin/env bash
set -euo pipefail

# 1) cache & load full history
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/jenkins-catalog"
JSON="$CACHE/plugin-versions.json"
URL="https://updates.jenkins.io/current/plugin-versions.json.gz"

mkdir -p "$CACHE"
if ! jq -e . "$JSON" &>/dev/null; then
  echo "⇣ downloading plugin-versions.json…" >&2
  curl -fsSL "$URL" | gunzip > "$JSON"
  jq -e . "$JSON" &>/dev/null || { echo "✘ corrupt catalog"; exit 1; }
fi

# 2) build a small TSV: id<TAB>latestVersion<TAB>requiredCore
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

while IFS= read -r raw; do
  # strip comments & whitespace
  id="${raw%%#*}"
  id="${id//[[:space:]]/}"
  [[ -z $id ]] && continue

  jq -r --arg id "$id" '
    def v: split(".")|map(tonumber);
    .plugins[$id] // {}
    | to_entries
    | map(select(.key|test("^[0-9]+(\\.[0-9]+)*$")))
    | sort_by(.key | v)
    | last?                                  # newest numeric version
    | if . then
        "\($id)\t\(.key)\t\(.value.requiredCore)"
      else
        "\($id)\t\t"                        # no numeric tags
      end
  ' "$JSON" >>"$TMP"
done < SOURCES/plugins.txt

# 3) compute the floor = max(requiredCore)
FLOOR=$(cut -f3 "$TMP" | grep -E '^[0-9]' | sort -V | tail -1)
: "${FLOOR:=0.0}"

# 4) write install.list with a clear title
{
  echo "# minimal Jenkins core required to upgrade these plugins: $FLOOR"
  awk -F'\t' '{print ($2=="") ? $1 : $1":"$2}' "$TMP"
} | tee install.list

echo "✓  install.list written (requires Jenkins ≥ $FLOOR)"
