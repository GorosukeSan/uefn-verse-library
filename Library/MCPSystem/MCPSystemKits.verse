# MCPSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
# 直下（受け箱・命令の形・interface・タグ・Core ツールセット）はほかの System に依存しない。ほかの System を使うツールセットは Kit に分ける（使う System の Kit だけを取り込める）
# entity を探す・transform・有効 / 無効・タグ・起動の合図・component（SceneGraphSystem・ActivationSystem）
EntityKit<public> := module {}
# プレイヤーの一覧・位置・テレポート・agent のタグ・組（PlayerSystem）
PlayerKit<public> := module {}
# 独自キャラクターの入力・ジャンプ・ダッシュ・テレポート・速度、動きの再生 / 記録（CharacterSystem・PlayerSystem）
CharacterKit<public> := module {}
# 画面の一覧・ボタンを押す・出す / 閉じる。画面ごとのオプトイン（WidgetSystem・PlayerSystem）
WidgetKit<public> := module {}
# ゲームの流れ（GameSequence）のノードへ移る・止める（GameSequenceSystem・SceneGraphSystem）
GameSequenceKit<public> := module {}
# プレハブを出す・消す（SpawnSystem）
SpawnKit<public> := module {}
# 拾える物と効果（PickupSystem・PlayerSystem）
PickupKit<public> := module {}
# 動く物（MoverSystem）
MoverKit<public> := module {}
# カウントダウン（CountdownSystem）
CountdownKit<public> := module {}
# エネルギー（EnergySystem・PlayerSystem）
EnergyKit<public> := module {}
# 状態の書き出し・復元（直下の mcp_session_restorable を集める）
SessionKit<public> := module {}
# ログの詳しさ・状態のダンプ・長くかかるツールの見本（直下だけ）
DebugKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
