#!/usr/bin/env bash
# Read and set the Sony A7 IV streaming settings over USB with gphoto2.
# The camera must be in PC Remote mode; in that mode it is not a webcam, so
# switch the USB connection back to USB Streaming before going live.
#   sony-camera.sh status
#   sony-camera.sh preset [kelvin]   default 4000 K (measured for the studio lights)
#   sony-camera.sh preview <file.jpg>
set -euo pipefail

get() { gphoto2 --get-config "$1" | sed -n 's/^Current: //p'; }
set_cfg() { gphoto2 --set-config "$1=$2" >/dev/null && echo "set $1 = $2"; }
writable() { gphoto2 --get-config "$1" | grep -q '^Readonly: 0'; }

status() {
  for key in cameramodel expprogram shutterspeed f-number iso whitebalance colortemperature \
    focusmode focusarea imagestabilization batterylevel; do
    printf '%-20s %s\n' "$key" "$(get "$key")"
  done
}

preset() {
  local kelvin=${1:-4000}
  set_cfg whitebalance "Choose Color Temperature"
  set_cfg colortemperature "$kelvin"
  set_cfg focusmode AF-C
  set_cfg focusarea Wide
  set_cfg iso "Auto ISO"
  # Shutter and aperture are writable only when the dial is on M; USB
  # Streaming always records in movie mode, so set them from Movie (M).
  if [[ $(get expprogram) == "Movie (M)" ]] && writable shutterspeed; then
    set_cfg shutterspeed 1/60 # 2x the 30 fps output; flicker-free under 60 Hz lights
    set_cfg f-number "$(gphoto2 --get-config f-number | sed -n 's/^Choice: 0 //p')" # widest
  else
    echo "skipped shutter/aperture: put the Still/Movie switch on Movie and the dial on M, then rerun" >&2
  fi
  status
}

preview() {
  local out=${1:?usage: sony-camera.sh preview <file.jpg>}
  local dir
  dir=$(mktemp -d)
  (cd "$dir" && gphoto2 --capture-preview --filename preview.jpg --force-overwrite >/dev/null)
  mv "$dir"/*.jpg "$out"
  rmdir "$dir"
  echo "$out"
}

case ${1:-status} in
  status) status ;;
  preset) preset "${2:-}" ;;
  preview) preview "${2:-}" ;;
  *) echo "usage: sony-camera.sh status|preset [kelvin]|preview <file.jpg>" >&2; exit 2 ;;
esac
