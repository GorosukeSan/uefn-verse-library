# ModeSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
ConditionKit<public> := module {}
# エディターに出す説明（message）を置く Kit
TooltipKit<public> := module {}
# 多数決でモードを決める Kit（mode_vote_component）
VoteKit<public> := module {}
