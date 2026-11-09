# Helpers for map.

# Returns Map without Key (same contents if Key is absent). Verse maps have no operation to remove one entry, so the rest is repacked
(Map:[k]v).RemoveKey<public>(Key:k where k:subtype(comparable), v:type)<transacts>:[k]v =
    var Result:[k]v = map{}
    for (Other -> Value : Map, Other <> Key):
        if (set Result[Other] = Value) {}
    Result
