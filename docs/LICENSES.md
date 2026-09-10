# Third-party notices

The Windows game includes the Godot Engine runtime. Keep this file and the accompanying `licenses` folder with redistributed builds. The original game and server source have their own license in the source package's root `LICENSE` file.

## Godot Engine 4.6.1

Godot Engine is used under the MIT/Expat license. Its complete copyright and permission notice is included in [licenses/GODOT-LICENSE.txt](licenses/GODOT-LICENSE.txt).

- [Official Godot license page](https://godotengine.org/license/)
- [Godot 4.6.1 source](https://github.com/godotengine/godot/tree/4.6.1-stable)
- [Godot contributor list](https://github.com/godotengine/godot/blob/4.6.1-stable/AUTHORS.md)
- [Upstream copyright inventory](https://github.com/godotengine/godot/blob/4.6.1-stable/COPYRIGHT.txt)

Godot also includes third-party components with their own notices. [licenses/GODOT-THIRD-PARTY-NOTICES.txt](licenses/GODOT-THIRD-PARTY-NOTICES.txt) contains the engine's embedded copyright inventory and full license texts: 99 copyright groups and 19 license texts. These were extracted from the locally available official Godot `4.6.1.stable.official.14d19694e` using `Engine.get_copyright_info()` and `Engine.get_license_info()`. The main MIT notice was extracted using `Engine.get_license_text()`.

The inventory is retained in full, including components that may be used only by other engine features or export targets. No engine library notices have been intentionally removed.

## ws 8.21.0

The Node.js room server depends on the `ws` WebSocket library under the MIT license. Its complete notice is included in [licenses/WS-LICENSE.txt](licenses/WS-LICENSE.txt), copied from the installed, locked package.

- [ws source and license](https://github.com/websockets/ws)
- The exact dependency version is recorded in `server/package-lock.json` in the source package.

Node.js is a separate development or hosting prerequisite and is not bundled with the player game or source ZIP. Any redistribution of Node.js itself should retain the notices supplied with that runtime.

## Project assets

The prototype's neutral arena and health interface are drawn in code. Its two music tracks and nine sound effects are original synthesized WAV assets with no external samples or recordings, covered by the project's MIT license. Their source generator and provenance are included in `game/assets/audio` in the source ZIP. It includes no purchased asset packs. Godot's built-in font and runtime components are covered by the engine notices above.
