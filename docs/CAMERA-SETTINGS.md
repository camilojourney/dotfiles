# Camera settings (Sony A7 IV)

Camera: Sony A7 IV (ILCE-7M4), firmware 6.02, Sigma 24-70mm F2.8 DG DN Art.
Firmware 6.02 (May 2026) is the current release, so there is nothing to update.
OBS uses the camera directly over USB-C as a webcam (USB Streaming), with no
capture card. Related: [OBS configuration](../home/.config/obs-studio/README.md),
[`scripts/sony-camera.sh`](../scripts/sony-camera.sh).

## Already configured

### On the camera (remotely, 2026-11-03)

Set with `scripts/sony-camera.sh preset` while the camera was in PC Remote mode.
The settings from before are saved in
`~/Backups/camera/a7iv-settings-before-20261103.txt` (outside the repo).

| Setting | Before | Now | Why |
|---|---|---|---|
| White balance | Auto | 4000 K, fixed | Measured against the white pillar under the room lights: 3500 K looked blue, 4500 K orange, 4000 K neutral. A fixed value stops colour drifting mid-stream. |
| Focus mode | AF-A | AF-C | Continuous focus keeps you sharp as you move. |
| Focus area | Wide | Wide | Lets face and eye detection find you anywhere in frame. |
| ISO | Auto | Auto | Stays auto until there is enough light to fix it. |

Not changed remotely: shutter speed and aperture are read-only unless the camera
is in Movie mode with the dial on M. Picture Profile is exposed only as numbers
(0-11), so it is safer to set on the camera. Image stabilization is still On.

Caveat: these were applied while the camera was in **still photo** mode (dial
on P). USB Streaming always uses **movie** settings. If *Diff. Set for Still/Mv*
lists White Balance or Focus Mode as separate, they did not carry over. Check
them in movie mode, or rerun the preset after step 1 below.

### In OBS (saved in this repo)

| Setting | Value |
|---|---|
| Source | `Camera - Sony A7 IV` (device ILCE-7M4) |
| Format | 1920x1080, 30 fps, NV12, Rec. 709 |
| Main canvas | 1920x1080 at 30 fps; full frame in *Camera*, rounded corner box in *Screen + Camera* |
| Vertical canvas (Aitum) | 1080x1920; camera fills the frame, cropped at the sides |

### Camo

Not changed. OBS does not use Camo for the Sony; it reads the camera directly,
which is sharper. Camo is set to a 4K profile with a 1.46x digital zoom on the
Sony, which softens a 1080p feed. Use Camo only for video calls or for the
iPhone as a second camera.

## You still need to set (on the camera)

Menu names are from firmware 6.02. Paths can differ slightly; see the
[Sony help guide](https://helpguide.sony.net/ilc/2110/v1/en/index.html).

1. **Movie mode, manual exposure.** Still/Movie/S&Q switch to **Movie**, mode
   dial to **M**. Then, in PC Remote, run `scripts/sony-camera.sh preset` to set
   shutter 1/60 and the widest aperture (f/2.8). Or set them by hand:
   - Shutter **1/60**: double the 30 fps output, and no flicker under 60 Hz lights.
   - Aperture **f/2.8**: most light and the softest background.
2. **Picture Profile: PP11 (S-Cinetone).** Good skin tones and ready to stream.
   Do not use S-Log; it looks flat without grading.
3. **Face/Eye AF:** subject **Human**, Face/Eye priority **On**.
4. **USB Streaming → Output Res/Frame Rate: HD (1080p) 30p.** It must match
   OBS's 30 fps. Pick 60p only if OBS changes to 60 fps.
5. **USB Streaming → Movie Rec During Streaming: Disable.** OBS already records.
6. **Setup → USB → USB Connection Mode: Sel. When Connect.** On connect the
   camera then asks which mode you want: Remote Shooting to change settings from
   the Mac, or Live Stream (USB Streaming) to go live. One cable cannot do both
   at once.
7. **USB Power Supply: On** and **Auto Power OFF Temp.: High**, so long streams
   neither drain the battery nor shut down from heat. Plug the camera straight
   into the Mac's USB-C port (or use a dummy battery); the hub may not supply
   enough power.
8. **SteadyShot: Off** when on a tripod.
9. **Light.** The room is dim, so Auto ISO runs high and the image is noisy. A
   key light at 45 degrees helps more than any setting. Once lit, fix ISO
   (around 400-800) instead of Auto.

## Changing settings later

1. Pick **Remote Shooting** on the camera.
2. `scripts/sony-camera.sh status` shows the current values.
3. `scripts/sony-camera.sh preset [kelvin]` applies the streaming settings
   (default 4000 K). Use a different kelvin value if your lights change.
4. `scripts/sony-camera.sh preview frame.jpg` saves a live-view frame to check.
5. Reconnect and pick **Live Stream (USB Streaming)** before going live.

`gphoto2` is installed by `./rebuild-total.sh`; before that, run the script
through `nix shell nixpkgs#gphoto2 -c bash scripts/sony-camera.sh status`.

## Possible upgrade

An HDMI capture card (for example Elgato Cam Link 4K) carries video over HDMI
while USB stays in Remote Shooting, so settings can change during a stream. It
also allows clean 1080p60 or 4K30, versus USB Streaming's 1080p30 at full
quality.
