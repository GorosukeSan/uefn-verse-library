# PickupSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
# ステージへの影響（効果の中から、タグで探した相手へ起動・停止の合図を送る）
StageKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
# 拾った効果を画面に出す HUD（拾ったときの知らせと、続いている効果の一覧。WidgetSystem の部品で作る）
HudKit<public> := module {}
