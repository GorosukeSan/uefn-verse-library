# Changelog

Versions follow `vA.B.C` (A: breaking change, B: new feature that may require changes on your side, C: bug fix). During 0.x a B bump may also change default behavior; every such change is listed under "Migration notes" in the System's README.

## v0.2.0 (2026-11-09) — UEFN v43.00
- **English only.** Every comment, editor tooltip, log message and README in the library is now in English (the repository used to be in Japanese). No identifiers or logic changed for this.
- **CharacterSystem** (see the "Migration notes (2026-11-09, …)" sections in `CharacterSystem/README.md`):
  - New Kits: `CellKit` (action cells shared by air jump / boost / wall kick), `ClingKit` (clinging to and crawling on walls and ceilings), `LookKit` (squash and stretch), `CameraExperimentalKit` (`player_orbit_camera`).
  - Side-input style (`character_side_style`: Turn / Strafe / TankTurn / toggle).
  - Feel changes with new defaults: fall gravity, ground snap, step-up, corner correction, turn-around, apex hang, air control split into acceleration / braking / turn-around, momentum kept in the air, riding moving floors rebuilt (ground sweep, inherited velocity), wall sticking fixed, dash rebuilt (speed, end speed, gravity scale, direction). Each note lists the values that restore the previous behavior.
  - Enumerators were appended: `character_action` gained `WallKicked`, `ClingStart`, `ClingEnd`; `character_motor_state` gained `Clinging`. Code that `case`s over every value without `_` must add them.
  - Fixed the two type errors listed as known issues in v0.1.0 (`MotorLedgeAssistToolTip`, `Distance` ambiguity in `CharacterMotorComponent.verse`).
- **PickupSystem**: `pickup_effect_stack_mode.Tier` (`MaxTier`, `GetTier`, `RaiseTier`, `TierChangedEvent`), persistent effects (`GrantPersistentPickupEffect`, `pickup_effect_grant_component.Persistent`), effects end when a part inside sends `activation_finished_event`. `case`s over `pickup_effect_stack_mode` must add `Tier`.
- **WidgetSystem**: `CardKit` (card views, buttons, grids, skins), `MenuKit/card_menu_component`, `PointerKit` (screen projection, pointer injection), `MarkerKit` (screen markers), `widget_view.AwaitButtonChoice`, text styles and panels on `text_hud_component`.
- **InputSystem**: `InputMappingLease` (leasing input mappings such as touch). **ActivationSystem**: `activation_finished_event`.
- **MCPSystem**: `widget.pointer` tool (114 tools in 13 toolsets); the tool table in the README is generated from the English tool descriptions; `CharacterKit` updated for the new enumerators.
- Removed: `MCPSystem/README.ja.md` (the repository is English only).

## v0.1.0 (2026-11-09) — UEFN v43.00
- First release (still being organized; the public API may change during 0.x).
- Known issues (real errors reported by the standalone type checker; not yet confirmed in a UEFN build):
  - `CharacterSystem/CharacterMotorComponent.verse`: `MotorLedgeAssistToolTip` is undefined (missing from TooltipKit).
  - `CharacterSystem/CharacterMotorComponent.verse`: `Distance` inside `StopDistance` is ambiguous with `Distance` from `/Verse.org/SpatialMath` (V3532 / V3588).
