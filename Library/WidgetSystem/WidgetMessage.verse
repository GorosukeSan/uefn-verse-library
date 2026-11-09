# Turn an integer into a message for display as is (for text_block.SetText)
IntToMessage<public><localizes>(Value:int):message = "{Value}"
# Turn an integer into a message with % appended (e.g. 75 -> "75%")
PercentToMessage<public><localizes>(Value:int):message = "{Value}%"
# Turn a string into a message for display as is (for text_block.SetText; for strings built at runtime)
StringToMessage<public><localizes>(Text:string):message = "{Text}"
