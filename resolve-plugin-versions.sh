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
  jq -r --arg id "$id" '
    # helper:  "2.361.4" → [2,361,4]  so sort_by() is semantic
    def verArr: split(".") | map(tonumber);

    .plugins[$id]?                       # object for this plugin (or null)
    | to_entries                         # → [{key, value}, …]
    | map(select(.key                    # keep only numeric keys 1.2.3
          | test("^[0-9]+(\\.[0-9]+)*$")))
    | sort_by(.key | verArr)             # oldest → newest
    | last?                              # newest numeric version (or null)

    | if . == null                       # none found?
         then "\($id)\tNO_NUMERIC_VERSION"
         else "\($id)\t\(.key)\t\(.value.requiredCore)"
       end
  ' "$HOME/.cache/jenkins-catalog/plugin-versions.json"
done < SOURCES/plugins.txt

