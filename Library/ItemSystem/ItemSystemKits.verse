# Make the ItemSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default; without this declaration they cannot be imported with using.
ExclusiveKit<public> := module {}
# Kit that grants items (item_grant_component / item_grant_entry_component)
GrantKit<public> := module {}
# Kit that adds rules for handling items (item_equip_lock_component)
RuleKit<public> := module {}
# Kit holding the descriptions (message) shown in the editor
TooltipKit<public> := module {}
