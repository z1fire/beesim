# Bee Sim 🐝

Fly through a sunny meadow as a honeybee. Sip nectar, gather pollen, pollinate flowers so new ones sprout, and bring it all home so the hive can make honey.

**[Download the latest APK](https://github.com/z1fire/beesim/releases/latest/download/BeeSim.apk)** (Android 7+, arm64/armv7)

## Features

- A fully 3D meadow: rolling hills, a lily pond, oaks and pines, swaying grass, and more than 600 flowers in six species
- First-person and third-person cameras that you can switch at any time
- Gameplay loop: collect nectar and pollen → deliver to the hive → nectar ripens into honey → spend honey on upgrades
- Pollination: carry pollen between flowers of the same species to pollinate them, which refills them and sometimes sprouts a new flower
- Worker bees you can raise to gather nectar for you
- Day/night cycle with sunsets, stars and fireflies
- Energy system: rest on flowers or at the hive to recover
- Touch controls (virtual joystick plus buttons), and keyboard and mouse on desktop
- Progress saves automatically

Every model, texture and sound is generated in code at startup, so the repo has no binary assets.

## Controls

| Action | Touch | Keyboard / mouse |
| --- | --- | --- |
| Fly | Left thumb joystick | WASD |
| Look | Drag with your right thumb | Mouse |
| Climb / dive | UP / DOWN | Space / Q |
| Boost | BOOST | Shift |
| Switch camera | CAM | V |
| Open the hive (when at the hive) | HIVE | H |
| Pause and settings | II / Back | Esc |

## Building

The game is made with [Godot 4.7](https://godotengine.org/). Open the folder in the Godot editor and press Play.

On every push, GitHub Actions (`.github/workflows/android.yml`) builds a signed APK and uploads it as a workflow artifact. Pushing a tag like `v0.2.0` also publishes a GitHub Release with the APK attached.

Signing uses these repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_ALIAS`.
