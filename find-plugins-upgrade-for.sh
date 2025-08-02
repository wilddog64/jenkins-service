#!/usr/bin/env bash
set -euo pipefail

# if [ $# -lt 2 ]; then
#   echo "Usage: $0 <jenkins-core> <plugins.txt>" >&2
#   exit 1
# fi

CORE="${1:-2.346.1}"                # e.g. 2.346.1
PLUGINS="${2:-SOURCES/plugins.txt}" # one plugin ID per line, comments OK
CATALOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/jenkins-catalog"
CATALOG="$CATALOG_DIR/plugin-versions.json"
URL="https://updates.jenkins.io/current/plugin-versions.json.gz"

mkdir -p "$CATALOG_DIR"
if ! jq -e . "$CATALOG" &>/dev/null; then
  echo "⇣ Downloading plugin-versions.json…" >&2
  curl -fsSL "$URL" | gunzip > "$CATALOG"
  jq -e . "$CATALOG" &>/dev/null || { echo "✘ corrupt catalog"; exit 1; }
fi

echo "▸ Picking the newest plugin versions compatible with Jenkins $CORE" >&2

printf '# Compatible plugin versions for Jenkins %s\n' "$CORE" > install.list

while IFS= read -r raw; do
  line="${raw%%#*}"             # strip comments
  line="${line//[[:space:]]/}"  # trim whitespace
  [[ -z $line ]] && continue

  id="$line"
  vers=$(jq -r --arg id "$id" --arg core "$CORE" --slurpfile pv "$CATALOG" '
    def v: split(".")|map(tonumber);

    # list all numeric versions whose requiredCore ≤ core
    ($pv[0].plugins[$id] // {})
    | to_entries
    | map(select(
        (.key|test("^[0-9]+([.][0-9]+)*$")) and
        (.value.requiredCore|v) <= ($core|v)
      ))
    | sort_by(.key|v)
    | last?                         # pick the newest compatible
    | .key // ""                   # output the version string or "" if none
  ')

  if [[ -z $vers ]]; then
    echo "⚠️  $id: no compatible version found for Jenkins $CORE" >&2
  else
    echo "${id}:${vers}" >> install.list
  fi
done < "$PLUGINS"

echo
echo "✓  install.list generated—each line is the newest version your core can run."
echo "   $(wc -l < install.list) plugins listed."
