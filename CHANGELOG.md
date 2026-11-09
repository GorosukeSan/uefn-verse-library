# 変更履歴

バージョンは `vA.B.C`（A: 破壊的変更、B: 新機能の追加（場合によっては利用側のコードの修正が必要）、C: バグ修正）。

## v0.1.0（2026-11-09）— UEFN v43.00
- 初回公開（整理中。0.x のあいだは公開 API が変わることがある）。
- 既知の問題（standalone の型チェッカーで出る本当のエラー。UEFN でのビルドは未確認）:
  - `CharacterSystem/CharacterMotorComponent.verse`: `MotorLedgeAssistToolTip` が未定義（TooltipKit に無い）。
  - `CharacterSystem/CharacterMotorComponent.verse`: `StopDistance` の中の `Distance` が `/Verse.org/SpatialMath` の `Distance` と曖昧（V3532 / V3588）。
