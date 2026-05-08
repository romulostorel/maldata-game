# Maldata

An inverted roguelike: you play the dungeon. Build a maze of monsters and walls, then watch a wave of heroes try to break through to the throne.

Built with [LÖVE 11.5](https://love2d.org). Pure Lua, deterministic procgen — every dungeon, sprite, animation, and sound effect is generated from a seed.

## Gameplay loop

1. **Build phase** — you have a budget. Spend it placing monsters and carving walls inside the dungeon to channel heroes into traps.
2. **Invasion phase** — heroes spawn at the entrance and pathfind toward the throne. Combat resolves turn-by-turn.
3. **Result** — if any hero reaches the throne, you lose. Wipe the wave to win, then play again with a new seed.

## Controls

### Build phase

| Input | Action |
|---|---|
| `1` / `2` / `3` | Select monster type (goblin / orc / slime) |
| `4` | Switch to wall tool |
| Left-click | Place monster / wall |
| Right-click | Remove monster / wall |
| `space` | Start invasion |

### Invasion phase

| Input | Action |
|---|---|
| `space` | Toggle auto-step |
| `.` or `→` | Step one tick |

### Always available

| Input | Action |
|---|---|
| `r` | New run (new seed) |
| `esc` | Quit |
| `F1` – `F4` | Toggle debug overlays (palette / sprite base / entities / audio) |

## Running from source

Requires LÖVE 11.5 on `$PATH`.

```bash
love .
# or
make run
```

## Tests

Tests run on LuaJIT under [busted](https://lunarmodules.github.io/busted/), matching the LÖVE runtime exactly.

```bash
make test
```

## Packaging for distribution

### `.love` (any OS with LÖVE installed)

```bash
zip -9 -r maldata.love conf.lua main.lua src
```

Then `love maldata.love`.

### macOS `.app`

```bash
# build the .love
zip -9 -r maldata.love conf.lua main.lua src

# get the official LÖVE macOS bundle
curl -L -o love-macos.zip \
  https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip
unzip love-macos.zip

# inject the game and rename
cp maldata.love love.app/Contents/Resources/
mv love.app Maldata.app

# zip for delivery
zip -9 -r --symlinks maldata-macos.zip Maldata.app
```

First-run on macOS: the bundle is unsigned, so Gatekeeper will block it. Either right-click → **Open**, or run `xattr -cr /path/to/Maldata.app` to clear the quarantine bit.

Equivalent recipes exist for Windows (concatenate `love.exe` with `maldata.love`, ship the resulting `.exe` next to the LÖVE DLLs) and Linux (concatenate the LÖVE AppImage with `maldata.love`).

## Project layout

```
main.lua            LÖVE entry point — wires callbacks
conf.lua            window, identity, version, module toggles
src/
  state.lua         game state machine (build / invasion / result)
  dungeon.lua       procedural dungeon layout
  grid.lua          tile ↔ pixel conversions
  hero.lua          hero classes, stats, AI hooks
  monster.lua       monster types and stats
  combat.lua        deterministic turn resolution
  ai.lua            hero pathfinding + targeting
  render.lua        world rendering
  ui.lua            HUD + result screen
  input.lua         mouse + keyboard routing
  effects.lua       transient visual effects
  audio.lua         SFX + ambient routing
  palette.lua       shared color palette
  rand.lua          seeded RNG
  assets.lua        runtime sprite/animation cache
  gen/              procedural generators (sprites, anims, SFX)
spec/               busted tests, mirrors src/
```
