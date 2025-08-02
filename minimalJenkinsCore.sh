#!/usr/bin/env bash
core="${1:-2.346.1}"                # ← pass the Jenkins version you plan to run
CATALOG_URL="https://updates.jenkins.io/current/update-center.actual.json"
# PLUGIN_FILE="plugins.txt"           # ← one ID per line, comments (# …) allowed
#
# jq -r \
#    --rawfile ids SOURCES/plugins.txt \
#    --arg mc "$core" \
#    -f minimal-core.jq \
#  update-center.actual.json

curl -sSL -O "$CATALOG_URL"
jq -R -r \
   --slurpfile uc update-center.actual.json \
   --arg mc "$core" \
   -f minimal-core.jq < SOURCES/plugins.txt
