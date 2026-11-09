# 整数をそのまま表示用の message にする（text_block.SetText 用）
IntToMessage<public><localizes>(Value:int):message = "{Value}"
# 整数に % を付けた message にする（例 75 → "75%"）
PercentToMessage<public><localizes>(Value:int):message = "{Value}%"
# 文字列をそのまま表示用の message にする（text_block.SetText 用。実行時に作った文字列を出すとき）
StringToMessage<public><localizes>(Text:string):message = "{Text}"
