# map の補助。

# Map から Key を除いた map を返す（Key が無ければ同じ中身）。Verse の map には 1 件を消す操作が無いので、残りを詰め直す
(Map:[k]v).RemoveKey<public>(Key:k where k:subtype(comparable), v:type)<transacts>:[k]v =
    var Result:[k]v = map{}
    for (Other -> Value : Map, Other <> Key):
        if (set Result[Other] = Value) {}
    Result
