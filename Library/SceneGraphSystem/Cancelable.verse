# 役割：複数の cancelable をまとめて 1 つの cancelable として扱う。作るときに Cancelables に入れるか、あとから Add で足す。Cancel で全部まとめて Cancel する（2 回目以降は何もしない）
cancelable_group<public> := class(cancelable):

    # 作るときに渡す、まとめて Cancel するもの（あとから足すものは Add で）
    Cancelables<public>:[]cancelable = array{}

    var<private> Added:[]cancelable = array{}
    var<private> Canceled:logic = false

    # あとから 1 つ足す。もう Cancel 済みなら、足したものをその場で Cancel する
    Add<public>(Cancelable:cancelable)<transacts>:void =
        if (Canceled?):
            Cancelable.Cancel()
        else:
            set Added += array{Cancelable}

    Cancel<override>()<transacts>:void =
        if (Canceled?):
            return
        set Canceled = true
        for (Cancelable : Cancelables + Added):
            Cancelable.Cancel()

# 中身があれば Cancel する。false なら何もしない
(Subscription:?cancelable).CancelIfSet<public>()<transacts>:void =
    if (Active := Subscription?):
        Active.Cancel()
