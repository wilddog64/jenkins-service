# minimal-core.jq ──────────────────────────────────────────────────────────
def v: split(".") | map(tonumber);          # "2.361.4" → [2,361,4]

[ inputs                           # plugin IDs from stdin
  | sub("#.*$";"")                 # drop trailing comments
  | sub("^[[:space:]]+|[[:space:]]+$";"")
  | select(length>0)
] as $want
| ($mc | v)        as $cur
| ($uc[0].plugins) as $plugins
| reduce $want[] as $id
        ( {max:"0.0.0", culprit:""} ;
          ($plugins[$id]? // empty) as $m
          | select($m.requiredCore? and ($m.requiredCore|type=="string"))
          | if ($m.requiredCore | v) > (.max | v)
               then {max:$m.requiredCore, culprit:$id}
               else .
            end
        )
| { minimalCoreNeeded:    .max,
    pluginThatRequiresIt: .culprit,
    yourCore:             $mc,
    upgradeRequired:      ((.max|v) > $cur)
  }
