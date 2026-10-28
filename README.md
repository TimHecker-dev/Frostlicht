# Frostlicht – Cozy Snow Adventure (Prototype)

A small 2D top-down game built with Godot 4. Explore a snowy forest at dusk, fight Frost Blobs and Snow Wraiths, and upgrade your **health, attack, and defense** through a skill tree. The campfire is your safe haven where you can recover.

## Getting Started

1. Download **Godot 4.7** (Standard version, not the .NET version) from [godotengine.org](https://godotengine.org/). Tested with version 4.7.2.
2. Launch Godot → click **Import** → select the `project.godot` file.
3. Press **F5** (or click the ▶ button in the top-right corner). Godot will briefly import the assets the first time you open the project.

## Controls

| Action | Key |
|---|---|
| Move | WASD or arrow keys (controller support is implemented but not yet tested) |
| Attack | Space, J, or left mouse button (aim with the mouse) |
| Skill tree | K |
| Pause (includes music and sound effect volume controls) | Esc or P |
| Toggle fullscreen | F11 |
| Test: instantly level up | F9 |

## Gameplay

- Defeated enemies grant experience. Each new **level** grants 1 **skill point** and fully restores your health.
- The skill tree (K) has three branches, each with four tiers that must be unlocked in sequence:
  - **Vitality:** increases maximum health.
  - **Might:** increases attack power.
  - **Fortitude:** increases defense.
  - **Reset:** refunds all skill points for free, allowing you to experiment with different builds.
- **Defense** reduces damage taken from each hit by a flat amount (at least 1 damage always gets through).
- Enemies telegraph their attacks with a yellow **"!"** indicator, giving you time to dodge or strike first. Enemies grow stronger as you level up.
- The **campfire** restores your health, and enemies will not enter its circle of light.
- If you are defeated, you wake up at the campfire without losing progress.

## Sound and Music

All audio is procedurally generated using code (no third-party samples or associated licensing concerns) and is stored in `audio/`.

- **Music** (`music_calm.ogg`, 1:56 loop): F major, slow tempo (66 BPM), soft chords with added tones, plucked harp, ambient textures, a music-box melody in the second repetition, and subtle sparkling snow sounds. The music fades in gently when the game starts.
- **Danger layer** (`music_alert.ogg`): When enemies are chasing you, a soft marimba pattern with a gentle pulse fades in. It uses the same chords as the main track, keeping the music harmonically consistent. It fades out again after combat.
- **Ambience:** Wind that becomes quieter near the campfire, where you are sheltered from the wind, and spatially positioned fire crackling.
- **Sound effects:** Footsteps in the snow, attacks, hits, enemy warnings, level-ups, skill unlocks, healing, death, waking up, and all menu sounds. Enemy sounds are spatially positioned, allowing you to hear whether they are to your left or right, and they become quieter with distance.
- **Menus:** When the game is paused or the skill tree is open, the music and wind are muffled, as if heard through the walls of a cabin.
- **Volume controls:** Adjustable sliders in the pause menu (Esc). Settings are saved to `user://settings.cfg`.

To generate or modify the audio, run:

`python3 tools/make_audio.py`

Requirements: `pip install numpy soundfile`

The key, tempo, chords, and melody are defined in the script's **Composition** section. If a melody note does not fit the underlying chord, the script raises an error.

Fine-tuning audio settings: see the constants at the top of `scripts/audio.gd`.

## Where to Make Changes

| File | Description |
|---|---|
| `scripts/game_state.gd` | Base stats, **skill tree** (names and bonuses), experience curve, key bindings |
| `scripts/player.gd` | Movement speed, attack range/angle/duration, invulnerability window |
| `scripts/enemy.gd` | Enemy types (`KINDS`: health, damage, speed, aggro range, etc.) |
| `scripts/world.gd` | Map size, number of trees and enemies, dusk colors |
| `scripts/campfire.gd` | Flames, healing (amount, interval, radius), crackling sound |
| `scripts/audio.gd` | **Audio manager:** volume levels, music layers, menu audio ducking, all sound names |
| `scripts/snowfall.gd` | Snowfall amount, size, and speed |
| `shaders/atmosphere.gdshader` | Vignette (darkened edges) and atmospheric haze |
| `scripts/ui.gd` | User interface: HUD, skill tree, pause menu, game-over screen |
| `scenes/*.tscn` | Player, enemies, campfire, and main scene (editable in the Godot editor) |

To add a new enemy type, add an entry to `KINDS` in `scripts/enemy.gd`, place its sprite in `art/`, and configure `world.gd` to select it in `_spawn_enemy`.

## Custom Graphics

All images in `art/` are placeholders generated programmatically by `tools/make_art.py` (requires `pip install pillow`).

You can replace any image with your own pixel art, as long as you keep the same filename. For characters and trees, the ground contact point should be at the bottom edge of the image. `player.png` is a sprite strip containing three frames (front, back, and side), each measuring 24 × 32 pixels.

## Ideas for Future Development

Real walking animations, loot and small collectible items, save/load functionality, additional enemies and areas, a day-night cycle, longer-lasting footprints in the snow, and a second music track for a new area (add new chords and a melody in `tools/make_audio.py`).

## License and Credits

**Font:** Nunito, licensed under the SIL Open Font License 1.1 (`fonts/OFL.txt`).

**Graphics, music, and sound effects:** Generated programmatically for this project using the tools in `tools/`.
