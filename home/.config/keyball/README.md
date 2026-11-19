# Keyball61+ configuration backup

The Keyball61+ (holykeebs, Vial firmware) stores its layout on the keyboard
itself. Nothing reads `~/.config/keyball`; this folder is a **git backup**,
same idea as Dato and Stream Deck.

`keyball61plus.vil` is a full Vial export: keymap (8 layers), wheels, macros,
lighting keys and QMK settings.

## Restore onto the keyboard

1. Open Vial with the keyboard plugged in.
2. **File -> Load saved layout...** and pick `keyball61plus.vil`.

Each half keeps its own copy of the layout, so restore with the USB cable in
the half you normally use.

## Refresh the backup

In Vial: **File -> Save current layout...** and overwrite `keyball61plus.vil`.

## What is configured

| Where | Setting |
|---|---|
| Left wheel, all layers | Macros M1/M0: quarter-line vertical scroll, phone (natural) direction |
| Right wheel, all layers | Macros M2/M3: quarter-line horizontal scroll |
| Macros M0-M3 | `Down(Mouse Accel 0); Tap(Mouse Wheel Down/Up/Right/Left); Up(Mouse Accel 0)` |
| QMK Settings -> Mouse keys | Maximum number of scroll steps per scroll action = 1 (sets the step for all four macros) |
| QMK Settings -> Tap-Hold | Permissive Hold on |
| Layer 0, left thumb Esc | `LT(2, Esc)`: tap for Esc, hold for layer 2 |
| Layer 2 (hold Esc) | H J K L = arrows; Q row = F1-F12; A = lights on/off, S/X = effect, D/C = color, F/V = brightness, G/B = animation speed; Z = Ctrl+Opt+Cmd+D; 1 = Ctrl+Opt+Cmd+B; right half: volume and browser back/forward |
| Layer 2, Enter position | `LCTL(KC_UP)`: hold Esc + tap Enter for Mission Control (all windows overview) |
| Layer 2, Backspace position | `MO(1)`: hold Esc + Backspace to reach layer 3 (trackball settings) |
| Layer 3 | Holykeebs pointer settings (Sens Set on A, HK Save on W, K/J up/down). The two Clear EEPROM keys are blanked so the layout cannot be wiped by accident; Bootloader keys remain on Tab and `\` |

Scroll step sizes: Accel 0 = 1/4 line, Accel 1 = 1/2 line, Accel 2 = 1 line
(with max steps 1); raising max steps to 2 or 4 doubles or quadruples every
macro's step.

## macOS side (not stored on the keyboard)

- System Settings -> Mouse: Tracking speed at maximum, Scrolling speed at the
  slowest. These apply to mice only, not the trackpad.
- Natural scrolling stays off for the trackpad; the wheel direction is set in
  the macros instead.
- Esc + Enter: **Mission Control**, using macOS's default Ctrl+Up shortcut.
  Keep it enabled under System Settings -> Keyboard -> Keyboard Shortcuts ->
  Mission Control -> **Mission Control**. Hold the left-thumb Esc key, tap
  Enter with the right thumb, then release Esc. This preserves normal Enter
  and uses both thumbs without replacing an existing layer-2 action.
- Esc + Z: System Settings -> Keyboard -> Keyboard Shortcuts -> Mission Control
  -> **Turn Do Not Disturb On/Off**, recorded as Ctrl+Opt+Cmd+D.
- Esc + 1: a Shortcuts app shortcut named **Baby Menu** with keyboard shortcut
  Ctrl+Opt+Cmd+B and one **Run AppleScript** action that toggles the menu bar
  popover (Shortcuts needs Accessibility permission):

  ```applescript
  tell application "System Events" to tell process "Baby Menu" to click menu bar item 1 of menu bar 2
  ```

macOS accelerates fast wheel spins, so quick turns jump further than slow
clicks; no built-in setting removes that, and firmware hi-res scrolling does not
change it on macOS.
