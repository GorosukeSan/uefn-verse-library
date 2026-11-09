# UEFN Verse Library — Scene Graph building blocks

English | [日本語](README.ja.md)

A collection of Verse building blocks for UEFN (Fortnite Creative) Scene Graph (entity / component) that you combine on your own entities. Each `<Name>System/` folder holds one mechanism — countdowns, game flow, abilities, pickups, custom characters, HUD, live editing through MCP, and more — and swappable parts are added as `Kit`s. Targets UEFN **v43.00** or later.

- Library version: **0.1.0** (`VERSION`, `CHANGELOG.md`)
- The library itself lives in [`Library/`](Library/). What is inside, the design rules and how to verify it are in [Library/README.md](Library/README.md); each System has its own `README.md` with usage notes.
- **Language note:** the top-level files are in English and Japanese. Inside `Library/`, [MCPSystem](Library/MCPSystem/README.md) has an English README (the Japanese one is `README.ja.md`); the other Systems' `README.md` files and the header comments in each `.verse` file are currently written in **Japanese** only.

> This is an **unofficial** project. It is not affiliated with or endorsed by Epic Games (Verse, Unreal Engine, UEFN and Fortnite are the property of Epic Games).

## Installation

1. Put the `Library/` folder in the Verse folder of your UEFN project (the author keeps it at `Content\VerseCode\Library`).
2. Build Verse in UEFN. `LibraryModules.verse` declares the `module` of every System.
3. Attach the components of the Systems you need to your entities. Where to place each component is described in the System's `README.md` and in the header comment of the component (role / placement / parent / children / same entity / requirements).

- Folders whose name ends in `ExperimentalKit` use `@experimental` APIs. These cannot be used on a published island; delete them if you do not need them.
- `_Test/` contains in-editor tests and `_Samples/` contains ready-to-place examples. Both use only the public API, so they double as usage examples.

## Status

During 0.x the library is still being organized and the public API may change. Known issues are listed in [CHANGELOG.md](CHANGELOG.md).

## Versioning

Versions follow `vA.B.C` (git tags use the same form).

| Digit | Bumped when |
|---|---|
| A | A breaking change: a public API name, type or behavior changes and your code needs to be updated |
| B | A new feature: a System, Kit or public API is added (may require changes on your side) |
| C | A bug fix |

## License

[MIT License](LICENSE). Verse, Unreal Engine, UEFN and Fortnite are trademarks or registered trademarks of Epic Games, Inc.
