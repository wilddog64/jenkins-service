#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# Usage:   ./find-plugins-upgrade.sh 2.346.1 plugins.txt
#
#   1st arg  = your running Jenkins core
#   2nd arg  = file with plugin IDs (one per line, "#…" comments allowed)
#
# Output:   install.list   (and echoed to console via tee)
##############################################################################

if [[ $# == 'help' ]]; then
  echo "Usage: $0 <jenkins-core> <plugins-file>" >&2
  exit 1
fi

CORE="${1:-2.346.1}"
LIST="${2:-SOURCES/plugins.txt}"
OUT="install.list"

# ── download / cache full catalogue once ────────────────────────────────────
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/jenkins-catalog"
CATALOG="$CACHE/plugin-versions.json"
URL="https://updates.jenkins.io/current/plugin-versions.json.gz"

mkdir -p "$CACHE"
if ! jq -e . "$CATALOG" &>/dev/null; then
  echo "⇣  downloading plugin catalogue…" >&2
  curl -fsSL "$URL" | gunzip > "$CATALOG"
  jq -e . "$CATALOG" &>/dev/null || { echo "✘ corrupt catalogue"; exit 1; }
fi

echo "▸ Calculating newest plugin versions compatible with Jenkins $CORE"

> "$OUT"   # truncate
while IFS= read -r raw; do
  # clean input line (remove comments & whitespace)
  id="${raw%%#*}"
  id="${id//[[:space:]]/}"
  [[ -z $id ]] && continue

  jq -n -r \
     --slurpfile pv "$CATALOG" \
     --arg id "$id" \
     --arg core "$CORE" \
     -f compat.jq
done < "$LIST" | tee "$OUT"

echo
echo "✓  Saved compatible list to $OUT"
