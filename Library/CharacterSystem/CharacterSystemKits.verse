# CharacterSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
# 見た目・操作（向き・Fortnite のキャラクターとの連動・入力の割り当て）
BodyKit<public> := module {}
# バフ・能力の付与（起動の合図のあいだ、体に倍率・空中ジャンプ・ダッシュの許可を重ねる。PickupSystem の効果のプレハブに入れて使う）
BuffKit<public> := module {}
# 付いていくカメラ（@experimental のカメラ API を使う。VerseShare で「実験的を含む」のプロジェクトにだけ配る）
CameraExperimentalKit<public> := module {}
# 状態の条件
ConditionKit<public> := module {}
# 起きたことへの反応
EventKit<public> := module {}
# 動き（歩く・ジャンプ・ダッシュ）
MoveKit<public> := module {}
# 面に触れた・乗った（触れられる面・触れたことを決める部品・動く面に乗せる）
SurfaceKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
