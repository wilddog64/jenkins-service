# compat.jq
# Needs:  --slurpfile pv plugin-versions.json
#         --arg id   <pluginId>
#         --arg core <jenkinsCore>
def v: gsub("[^0-9\\.]";"") | split(".") | map(tonumber);

# helper: epoch-ms OR ISO string  →  YYYY-MM-DD
# helper: epoch-ms **or** ISO string  →  YYYY-MM-DD
def toDate($ts):
  if ($ts|type) == "number"                          # old epoch-ms style
     then ($ts/1000 | strftime("%Y-%m-%d"))
  else                                               # ISO string
     ($ts
      | gsub("\\.[0-9]+Z$"; "Z")                     # drop .123 or .123Z
      | fromdateiso8601
      | strftime("%Y-%m-%d"))
  end;

($pv[0].plugins[$id] // {})
| to_entries
| map(select(
    (.key | test("^[0-9]+([.][0-9]+)*$"))
    and ((.value.requiredCore|v) <= ($core|v))
  ))
| sort_by(.key | v)
| (last?) as $sel
| if $sel then
    "\($id):\($sel.key):\($sel.value.url) # Jenkins core: \($sel.value.requiredCore), release date: \(toDate($sel.value.releaseTimestamp))"
  else empty
  end

