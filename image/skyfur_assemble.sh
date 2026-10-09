#!/bin/bash
# Join the model parts baked into this image (/models_baked/<dir>/<name>.part00, .part01, ...) into whole files.
# GHCR takes at most 10 GB per layer, so big models are stored in 4 GB parts. ComfyUI's models/<dir>/<name>
# is a link to /models_baked/<dir>/<name>, so the model appears as soon as its file is complete.
B=/models_baked
for first in $(find "$B" -name '*.part00' | sort); do
  out="${first%.part00}"
  if [ -s "$out" ]; then echo "ok    $out (already joined)"; continue; fi
  echo "join  $out"
  cat "$out".part?? > "$out.tmp" && mv "$out.tmp" "$out" && echo "ok    $out"
done
touch /tmp/skyfur_assemble.done
echo "done"
