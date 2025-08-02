# compat.jq
# Needs:  --slurpfile pv plugin-versions.json
#         --arg id   <pluginId>
#         --arg core <jenkinsCore>

def v: gsub("[^0-9\\.]";"") | split(".") | map(tonumber);

($pv[0].plugins[$id] // {})        # full map for this plugin
| to_entries
| map(select(
    (.key | test("^[0-9]+([.][0-9]+)*$")) and            # numeric key
    ((.value.requiredCore|v) <= ($core|v))               # ≤ core
  ))
| sort_by(.key | v)
| (last?) as $sel                                          # ← pipe *included*
| if $sel
    then "\($id):\($sel.key) # \(
             $sel.value.releaseTimestamp/1000
             | strftime(\"%Y-%m-%d\")
         )"
    else empty
  end
