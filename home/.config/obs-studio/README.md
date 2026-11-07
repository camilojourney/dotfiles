# OBS Studio configuration

`nix/camilo-extra.nix` links only the declared scene/profile files from `basic/`
into `~/Library/Application Support/obs-studio/basic`. The app directory remains
local, so backups, other profiles and runtime data do not enter the checkout.
Applied by `./rebuild-total.sh` (personal apps). See
[configuration/state separation](../../../docs/CONFIGURATION.md).

| Path | Purpose |
|------|---------|
| `basic/profiles/Streaming/basic.ini` | Video 1920x1080@30, Apple VT H.264 stream encoder, HEVC hybrid-MP4 recording, 30 s replay buffer |
| `basic/profiles/Streaming/streamEncoder.json` | CBR 6000 kbps, 2 s keyframes, High profile |
| `basic/profiles/Streaming/recordEncoder.json` | HEVC constant quality 65 |
| `basic/scenes/Streaming.json` | Scenes, sources, mic filter chain, Aitum vertical canvas and its scenes |
| `basic/profiles/Streaming/aitum.json` | Aitum Stream Suite: outputs (destinations), vertical canvas, dock layout |

`service.json` is host-local, not linked into the checkout: configure the main
stream platform and server in OBS Settings > Stream on each machine.

## Stream keys (public repo)

Enter keys in OBS (Settings > Stream) and Aitum's Outputs dock as usual. They stay
in the files on this Mac. `service.json` stays local; `.gitattributes` sends the
linked `aitum.json` and `basic.ini` through `scripts/obs-strip-keys.sh`, so commits carry every
setting with keys and login tokens blank. `rebuild-total` registers that filter.
On a new Mac everything comes back except the keys: paste them again (keep them
in your password manager). After rotating only a key, `git status` can list the
file until `git add`, which then stages nothing.

## Scenes

| Main (16:9) | Vertical (9:16, Aitum) follows it automatically |
|-------------|----------------|
| Starting Soon | Starting Soon (V) |
| Camera | Camera (V) |
| Screen + Camera | Screen + Camera (V) |
| Screen | Screen + Camera (V) |
| Be Right Back | Be Right Back (V) |
| Ending | Ending (V) |

Mic chain on `Mic - Scarlett Solo` (forced mono, input 1): gain +6 dB, RNNoise
suppression, expander, compressor 4:1 at -20 dB, limiter at -3 dB.
The Stream Deck **OBS** folder switches these scenes; see `../streamdeck/`.

## New Mac

1. `./rebuild-total.sh` (installs OBS and creates the config-only links).
2. Quit OBS, then `bash scripts/install-obs-plugins.sh` (pinned versions, checksummed).
3. Grant OBS **Screen & System Audio Recording** and **Camera**/**Microphone** in
   System Settings > Privacy & Security.
4. Paste the stream keys back into Settings > Stream and each Aitum output.

## Camera control

What is set on the camera and what to set by hand: [Camera settings](../../../docs/CAMERA-SETTINGS.md).

`scripts/sony-camera.sh status|preset|preview` reads and sets the A7 IV over USB
(gphoto2, from `nix/camilo-extra.nix`). It needs the camera in PC Remote mode,
in which it is not a webcam: run the preset, then switch the USB connection back
to USB Streaming before going live.

Devices are matched by hardware ID (Sony ILCE-7M4 over USB, Focusrite Scarlett Solo);
reselect them in the source properties if they differ.
