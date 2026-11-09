# WidgetSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
# 文字・ゲージ・通知の HUD と、標準 HUD を隠す部品
HudKit<public> := module {}
# 選択メニュー（文字のボタン・カード）
MenuKit<public> := module {}
# カード（1 枚分のデータ・見た目の決まり・押せるカードを作る関数・カードの情報を持つ component）
CardKit<public> := module {}
# Virtual Pointer（TouchMapping の PointerSelect）と画面の部品をつなぐ（実験的。押した位置のカードを押し込む）
PointerKit<public> := module {}
# だれに出すかを決める部品（アイテムの持ち手など）
ShowKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
