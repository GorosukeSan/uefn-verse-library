# Make the WidgetSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default, so they cannot be used from outside unless declared.
# Text, gauge and notification HUDs, and the part that hides the standard HUD
HudKit<public> := module {}
# Choice menus (text buttons, cards)
MenuKit<public> := module {}
# Cards (data for one card, look rules, a function that builds a pressable card, a component that holds card info)
CardKit<public> := module {}
# Connects the Virtual Pointer (PointerSelect of TouchMapping) to screen parts (experimental; presses the card at the pointed position)
PointerKit<public> := module {}
# Markers layered over the 3D view (world position -> screen ratio, a part that aims at a point, speech bubbles)
MarkerKit<public> := module {}
# Parts that decide who sees it (the item holder, etc.)
ShowKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
