# CoopGhost

**Experimental two-player co-op for Silent Hill 2 (2024), with a launcher.** Authored by MarySue.

The game has no multiplayer. CoopGhost lets two people play side by side anyway: each runs their
own copy of the game, and the mod keeps the two copies in agreement over Radmin VPN, Hamachi or
a LAN. You see the other player in your world, fully animated, holding what they hold, with their
flashlight lighting your surroundings, and you share one inventory.

> Unofficial fan project. Not affiliated with or endorsed by the game's developer or publisher.
> You need your own copy of the game. This repository contains no game files.

![Session page](docs/screenshots/session.png)

## Status

This is a work in progress. Everything marked working has been tested by one player against a
simulated second player; a full session between two real PCs still needs testing.

| Feature | Status |
|---|---|
| Other player visible, full-body animation mirrored every frame | Working |
| Equipped weapon, flashlight and radio shown on the other player | Working |
| Other player's flashlight beam lights your world | Working |
| Shared inventory (ammo, healing, documents, key items), each kind switchable | Working |
| Doors react to the other player's body, and open, close and unlock for both players | Reaction and remote moves tested solo; needs a two-PC test |
| Cutscenes: both players watch together, then the joiner regroups beside the host | Detection runs; joining and regrouping need a two-PC test |
| World pickups: taken once for both players (with shared inventory) | Tracking runs; removal needs a two-PC test |
| Collision with the other player (optional) | Working |
| Friendly fire (optional): a melee hit costs about one enemy hit, a shot double | Damage path tested; hit detection needs a two-PC test |
| Play as James, Maria, Angela or Mary, for the other player and on your own screen | Working, poses on non-James bodies are approximate |
| Launcher: host / join, install, live tweaks, themes | Working, network path needs a two-PC test |
| Health | Separate on purpose |
| Map and item-inspection screens | Separate (they are local menus) |
| Shared enemies: same health and deaths, agreed targets, joiner follows the host's positions | Tracking and sending run; damage sharing, retargeting and position following need a two-PC test |
| Enemies from scripted groups and bosses | Not synced |
| Puzzles: solved by one player, solved for both (safes, padlocks, door locks, cabinet puzzles) | Tracking runs; solving the other player's copy needs a two-PC test |
| Puzzle progress short of solved (pieces placed, dials turned) | Not synced; one player does the puzzle |
| Pushable objects: furniture one player pushes moves for both | Built from the game's class layout; not yet tried on a real object |
| Saving and loading together: the joiner saves when the host saves and reloads when the host loads | Save hooks installed; saving and reloading the joiner need a two-PC test |
| Go to the other player (F7 in game, or the launcher button) | Working |
| Sliding doors | Unlocks shared; opening and closing not synced |
| Plain switches, item containers, elevators, breakable glass | Not synced; use F7 if an elevator or a drop separates you |
| Save points, boss fights, companion characters, endings tracking | Not synced |

The intended way to play: both players share one inventory, one of them works a puzzle with
the items you found, and when it is solved the story moves on for both. Play through the same areas together and it holds up; drift apart and the worlds
diverge.

## The launcher

| Tweaks | World |
|---|---|
| ![Tweaks page](docs/screenshots/tweaks.png) | ![World page](docs/screenshots/world.png) |

| Characters | |
|---|---|
| ![Characters page](docs/screenshots/characters.png) | |

| Appearance | About |
|---|---|
| ![Appearance page](docs/screenshots/appearance.png) | ![About page](docs/screenshots/about.png) |

Four themes are built in:

| Rust | Moss | Paper |
|---|---|---|
| ![Rust theme](docs/screenshots/session-rust.png) | ![Moss theme](docs/screenshots/tweaks-moss.png) | ![Paper theme](docs/screenshots/characters-paper.png) |

### Tweaks

All tweaks apply immediately, also while the game is running.

| Group | Tweak | Default |
|---|---|---|
| Inventory | Shared inventory | on |
| | Host's inventory replaces the joiner's on connect | on |
| | Share ammunition / healing items / maps, notes and photos / weapons, keys and puzzle items | all on |
| Other player | Show the other player | on |
| | Show held items (weapon, flashlight, radio) | on |
| | Collision (their body blocks you and enemies) | off |
| | Size | 100 % |
| World | Puzzles | on |
| | Doors | on |
| | Pushable objects | on |
| | Cutscenes | on |
| | Save and load together | on |
| Combat | Shared enemies | on |
| | Friendly fire (both players must enable it) | off |
| | Damage per melee hit (a shot is double) | 10 hp |
| Flashlight | Their flashlight lights my world | on |
| | Beam casts shadows | off |
| | Beam brightness | 100 % |
| Network | Updates sent per second (30 / 15 / 10) | 30 |
| | Smoothing delay | 100 ms |
| | Hide the other player after silence | 3 s |
| Characters | My character (what the other player sees) | James |
| | See myself as that character too | on |
| | Other player on my screen (overrides their choice) | their choice |
| Launcher | Theme, keep on top, start the game with the session | |

## Requirements

- Windows, and the PC version of the game. Built and tested on game build 1.0.0.5.
- Both players on the same game build, starting from the same save in the same area.
- A network where the two PCs can reach each other by IP: Radmin VPN, Hamachi or LAN.
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (experimental build), which loads the mod.
  The packaged release bundles it; from source you install it yourself.

## Play

1. Get `CoopGhost.zip` (build it with `tools\build_dist.ps1`, see below), unzip it anywhere and
   run `CoopLauncher.exe`.
2. Set the game folder (the one containing `SHProto.exe`) and press **Install / update mod** if
   the launcher says the mod is not installed. If the game is under Program Files the launcher
   offers to restart itself as administrator.
3. One player picks **Host**, the other **Join**. Each enters the *other* player's address. The
   launcher lists your own addresses; click one to copy it.
4. Press **Start session**. Allow the launcher through Windows Firewall if asked (UDP 47777).
5. Both load the same save. The status turns green when packets arrive from the other player.

In game, **F9** toggles a solo test: the other player's body appears beside you and copies you.
**F7** moves you to the other player, for when an elevator, a drop or anything unsynced
separates you.

To uninstall, delete `dwmapi.dll` and the `ue4ss` folder from `<game>\SHProto\Binaries\Win64`.

## How it works

The game ships without any networking, and Lua inside UE4SS has no sockets, so the design is:

```
 game A  <-- files -->  launcher A  <== UDP over VPN ==>  launcher B  <-- files -->  game B
 (mod)       ipc\                                                          ipc\       (mod)
```

- **The mod** (`CoopGhost\Scripts\core.lua`) runs inside each game. About 30 times a second it
  measures the local player (position, 27 bone rotations, held items, flashlight) and writes
  that to `ipc\out.txt`. It reads the other player's state from `ipc\in.txt`.
- **The launcher** carries those small text packets between the PCs over UDP.
- **The other player's body** is a poseable copy of a character mesh already in your game. No
  animation blueprint runs on it; every rendered frame its bones are set to a blend of the two
  most recent snapshots, drawn slightly in the past so network jitter does not show.
- **Inventory** is synced as reliable events: each gain or loss is resent until the other side
  acknowledges it. On connect the host's inventory is the starting point.
- **Seeing yourself as another character** keeps the real James animating but invisible, and
  poses a second body from him every frame, fingers included.
- **Doors** are each driven by one game: the one whose player stands closer. That game reports
  the door's angle and the other moves its copy to match, holding off the door's auto-close
  while it does. Where no game is driving a door, the other player's body pushes it open
  locally, away from the side they stand on. Unlocks travel as reliable events; re-locks do
  not, because the game also locks doors behind the player to gate areas.
- **Cutscenes** are identified by their level path. When one starts, the other player is moved
  to where it was triggered, which normally makes their own game trigger it too, with all the
  logic attached; if it has not started after a moment it is started directly. Afterwards the
  joiner is placed beside the host.
- **Pickups** taken in one game are marked collected and removed in the other, so a shared
  item is not collected twice. Freshly streamed-in doors and pickups are left alone for a few
  seconds, since the game is still applying their saved state.
- **Puzzles** you zoom in on all carry the same component, with a solved state and a "set
  solved" call. When one becomes solved in one game, the other game marks its copy solved,
  which runs that puzzle's own follow-up there: the lock opens, the item appears, the cutscene
  starts. A puzzle you are in the middle of is not solved under you; it waits until you step
  away.
- **Pushable objects** are driven by whoever is pushing: their game reports the object's
  position and the other game moves its copy with the pushable's own "teleport to" call. The
  resting place is sent once more as a reliable event when they let go.
- **Saving and loading**: each PC keeps its own save files, and from code the game can only
  reload its latest save. So when the host's game saves, the joiner's game saves too (same slot
  number when the host used one), and when the host loads or dies, the joiner reloads its own
  latest save and is placed beside the host. If the host deliberately loads an older slot, the
  joiner still gets its latest.
- **Enemies** run in both games; they come from the same spawners placed in the level, so a
  hash of the spawner's path names an enemy on both PCs. Animation, attacks and damage to the
  local player stay native. The mod makes the two copies agree: damage either player deals is
  sent as a reliable event and applied to the other copy, with the host's health as the
  reference; an enemy hunting one player is sent after that player's body in the other game,
  and goes for whoever is clearly closer; the joiner's copy is nudged toward the host's
  position. Only enemies that are already alert are redirected, never dormant ones.
- **Friendly fire** is judged by the attacker's game (aim line for shots, reach and facing for
  melee) and applied by the victim's game through the game's own damage functions. Shots are
  not yet checked for walls in between.

`core.lua` is hot-reloaded when it changes, so the mod can be developed with the game running.

## Building from source

Requirements: Windows with .NET Framework 4 (for the bundled C# compiler) and PowerShell.

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_dist.ps1
```

This compiles the launcher and assembles `dist\CoopGhost\` and `dist\CoopGhost.zip`. It copies
UE4SS from your own game folder, so install UE4SS into the game first.

Regenerate the README screenshots (demo data, no personal settings) with:

```powershell
dist\CoopGhost\CoopLauncher.exe --screenshots docs\screenshots --scale 1.25
```

## Project layout

| Path | What |
|---|---|
| `CoopGhost\Scripts\main.lua` | Tiny bootstrap; reloads `core.lua` whenever it changes |
| `CoopGhost\Scripts\core.lua` | The mod |
| `CoopGhost\relay.ps1` | Script version of the launcher's network relay, kept as a fallback |
| `launcher\CoopLauncher.cs` | The launcher (WinForms, custom-drawn, single file) |
| `tools\build_dist.ps1` | Builds the launcher and the distributable zip |
| `tools\run.ps1`, `tools\cmd\` | Run Lua snippets inside the live game; the probes used to map it |
| `tools\list_pak_paths.ps1` | Lists asset paths from the game's container index |

## Credits

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) by the UE4SS-RE team, which makes scripting the
  game possible.
- Mod and launcher by MarySue.

## License

[MIT](LICENSE) for the code in this repository. The game, its characters and its assets belong
to their respective owners and are not included here.
