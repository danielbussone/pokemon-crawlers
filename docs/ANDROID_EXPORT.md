# Android Export Plan — sideloadable APK (Retroid Pocket 6 first)

> Status: **planned, not started.** Deferred to implement another day.

## Context

Pokémon Crawlers is a Godot 4.7 first-person crawler currently targeting desktop only: built with
the **Forward+ (desktop Vulkan)** renderer and **keyboard-only** (movement reads
`Input.is_action_just_pressed` on 6 actions defined in code; menus/combat are `Button` nodes).
Goal: an APK to **sideload onto a phone or Retroid Pocket 6**.

**Decisions locked with the user:**
- **Gamepad-first (Retroid).** Add joypad bindings to the 6 movement actions and make menus
  gamepad-navigable. No on-screen touch overlay yet (a phone would need a controller for now).
- **Mobile (Vulkan) renderer** — good visuals; works on the Retroid (Snapdragon/Adreno) and on
  desktop for testing.
- **Toolchain from scratch** — install JDK 17, Android SDK, Godot export templates, keystore.

Mostly low-risk: menus are already `Button`s (touch/gamepad friendly), and Godot's built-in
`ui_accept/ui_cancel/ui_up/down/left/right` already include joypad bindings, so menu navigation
works once a control grabs focus. The project has **no `[input]` section**, so those defaults
apply. The bulk of the effort is the Android toolchain, not code.

## Phase 1 — Project config (mobile settings)

Edit `godot/project.godot` (via the editor's Project Settings, or directly):
- **Renderer → Mobile:** set `rendering/renderer/rendering_method="mobile"` (and the `.mobile`
  override), and change `application/config/features` from `"Forward Plus"` to `"Mobile"`.
- **Orientation:** `display/window/handheld/orientation="landscape"` (first-person HUD is
  landscape; existing `stretch = canvas_items / expand` already scales to device screens).
- **Touch→mouse:** `input_devices/pointing/emulate_mouse_from_touch=true` (harmless now, makes
  menus tappable if a touch build is added later).
- **Mobile perf (optional):** drop `anti_aliasing/quality/msaa_3d` to 0/1 and tune directional
  shadow size if the Retroid frame-rate needs it (revisit after first on-device test).

## Phase 2 — Gamepad input (code, small)

- **Movement bindings** — `godot/scripts/core/run_manager.gd` `_setup_input()` (line ~304) already
  adds keyboard events per action via `InputMap.action_add_event`. Add joypad events to the same
  6 actions:
  - `move_forward`/`move_back` → `JOY_BUTTON_DPAD_UP`/`DOWN` + left-stick Y (`InputEventJoypadMotion`, `JOY_AXIS_LEFT_Y`).
  - `strafe_left`/`strafe_right` → left-stick X (`JOY_AXIS_LEFT_X`).
  - `turn_left`/`turn_right` → `JOY_BUTTON_DPAD_LEFT`/`RIGHT` + right-stick X (`JOY_AXIS_RIGHT_X`) + `L1`/`R1`.
  Discrete grid steps already use `is_action_just_pressed`, so buttons step once per press; sticks
  step once per push past the deadzone (auto-repeat-while-held is a later polish item).
- **Menu focus for gamepad** — combat/starter/shop UIs (`godot/scripts/ui/combat_ui.gd`,
  `starter_ui.gd`, `shop_ui.gd`) create `Button`s but rely on mouse clicks. When each screen
  appears, `grab_focus()` the first interactive control so the D-pad/A-button can navigate (Godot
  auto-computes focus neighbours; `ui_accept`/`ui_cancel` defaults already map to A/B).
- **Back button** — map Android back / gamepad B to the existing cancel/close paths where menus
  expect it (verify `ui_cancel` closes shop/overlays; wire if missing).

## Phase 3 — Android toolchain (from scratch, one-time)

1. **JDK 17** (Godot 4.7 Android builds require 17). Install and note the path.
2. **Android SDK** — Android Studio (simplest) or command-line tools; then via `sdkmanager`
   install `platform-tools` (gives `adb`), `platforms;android-34`, `build-tools;34.0.0`.
3. **Godot export templates** — editor → *Manage Export Templates* → download the 4.7 set.
4. **Editor Settings → Export → Android** — set **Android SDK Path** and **Java SDK/JDK Path**.
5. **Debug keystore** (fine for sideload):
   `keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12`
   then point Editor Settings → Export → Android → *Debug Keystore* at it.

## Phase 4 — Export preset + build the APK

- Create an **Android export preset** (Project → Export → Add → Android). Set: unique **package
  name** (e.g. `com.danny.pokecrawlers`), app name/icon, **Orientation = Landscape**,
  architectures **arm64-v8a** (Retroid + modern phones; add `armeabi-v7a` only for old devices).
  This writes `godot/export_presets.cfg`.
- **App icon** — generate mobile icons from the existing `res://icon.svg` (or a new 512² PNG).
- **Build** from the editor (*Export Project*, keep "debug"), or headless:
  `godot --headless --path godot --export-debug "Android" build/pokemon_crawlers.apk`

## Phase 5 — Sideload to device

- **Retroid Pocket 6 (or phone):** enable *Developer options* → *USB debugging*, connect USB, then
  `adb install -r build/pokemon_crawlers.apk`.
- **No cable:** copy the APK to the device, enable *Install unknown apps* for the file manager, tap
  to install.
- Launch, pick a starter with the gamepad, walk with the D-pad.

## Phase 6 — On-device test + polish

- Verify: renderer looks right, framerate smooth, gamepad moves/turns, A confirms cards, B backs
  out, combat fully playable without a mouse.
- Tune from findings: input feel, shadow/MSAA for perf, HUD/text scale on the Retroid screen, and
  **APK size** — `godot/art/creatures` (incl. the Gen-5 black-white scrape) is large; trim unused
  art or exclude it from the export filter if the APK is too big.

## Critical files

- `godot/project.godot` — renderer, orientation, touch-emulate (Phase 1).
- `godot/scripts/core/run_manager.gd` `_setup_input` — joypad bindings (Phase 2).
- `godot/scripts/ui/combat_ui.gd`, `starter_ui.gd`, `shop_ui.gd` — `grab_focus()` on show,
  back-button wiring (Phase 2).
- `godot/export_presets.cfg` (new) — Android preset (Phase 4).
- Editor/global (not in repo): JDK, Android SDK, export templates, debug keystore (Phase 3).

## Verification

1. Desktop still runs after the Mobile-renderer switch (`godot --path godot`), and a controller
   plugged into the PC moves the player + navigates menus (validates Phase 2 before building).
2. `--headless --export-debug "Android" …` produces an APK with no export errors.
3. `adb install -r …` succeeds; on the Retroid the game boots and a full run is playable end-to-end
   with only the gamepad (starter pick → walk → combat → shop → next area).

## Notes / non-goals

- **No on-screen touch controls** this pass (gamepad-first). A phone needs a controller until a
  touch D-pad overlay is added — the natural follow-up (`emulate_mouse_from_touch` is already on
  for menus, so only movement needs an overlay).
- Dev-only entry points (`--mapeditor`, `--simcheck`, `--visualcheck`) are cmdline flags never hit
  on device; no mobile handling needed.
- Runtime only *reads* bundled JSON/art from `res://`; settings/saves go to `user://` (app private
  storage), which works on Android.
- "Pokémon" naming is fine for personal sideload; rename before any public distribution.
