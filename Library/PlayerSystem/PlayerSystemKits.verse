# PlayerSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
ConditionKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
# Fortnite のキャラクターの動き（ジャンプ・着地・しゃがみなど）に反応する部品
MotionKit<public> := module {}
