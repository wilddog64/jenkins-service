#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# 0. Decide where we keep the catalogue.
#    • default:  $HOME/.cache/jenkins-catalog
#    • you can override with  CATALOG=<path>  before running the script
###############################################################################
JSON=${CATALOG:-$HOME/.cache/jenkins-catalog/plugin-versions.json}
mkdir -p "$(dirname "$JSON")"

###############################################################################
# 1. Download once if the file is missing or empty (≈ 20 MiB)
###############################################################################
if [[ ! -s "$JSON" ]]; then               # -s  → file exists and not empty
  echo "⌛  Downloading plugin catalogue …" >&2
  curl -fsSL -o "$JSON" \
       https://updates.jenkins.io/current/plugin-versions.json \
  || { echo "❌  Catalogue download failed." >&2; exit 1; }
fi

###############################################################################
# 2. Capture the Jenkins version you want to check (default 2.346.1)
###############################################################################
core="${1:-2.346.1}"
echo "▸ Checking plugin list against Jenkins $core" >&2

while read -r id; do
  id=$(sed 's/#.*//' <<<"$id" | xargs)    # trim & skip comments / blanks
  [[ -z $id ]] && continue

  jq -r --arg id "$id" '
    def verArr: split(".") | map(tonumber);

    .plugins[$id]?                            # plugin map or null
    | to_entries
    | map(select(.key|test("^[0-9]+(\\.[0-9]+)*$")))   # numeric-ish keys
    | sort_by(.key|verArr) | last?                     # newest numeric or null

    # ------------------------------------------------------------------
    # If we found a numeric version →  "id:version"
    # otherwise just "id"  (let the CLI install whatever is latest)
    # ------------------------------------------------------------------
    | if . == null
         then $id
         else "\($id):\(.key)"
       end
  ' "$HOME/.cache/jenkins-catalog/plugin-versions.json"
done < SOURCES/plugins.txt
