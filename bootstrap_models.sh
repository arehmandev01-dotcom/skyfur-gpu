#!/bin/bash
# SKYFUR: put every model on a fresh GPU machine (~77 GB). Runs INSIDE the container.
#   bash bootstrap_models.sh [comfy_dir]      (default: /root/ComfyUI, else /workspace/ComfyUI, else /ComfyUI)
#   bash bootstrap_models.sh --bg             (run in background, output in /tmp/models.out)
#   bash bootstrap_models.sh --bg --wait      (at container start: first wait until the image's start script has
#                                              moved ComfyUI to /workspace, up to 30 min; used by the Salad Command)
# Safe to re-run: complete files are skipped, partial ones resume. Only needs curl.
# Only one copy downloads at a time: a second run (e.g. gpu_start.py over SSH) just shows the first one's progress.
if [ "$1" = "--bg" ]; then shift; setsid nohup bash "$0" "$@" > /tmp/models.out 2>&1 < /dev/null & echo "started in background: tail -f /tmp/models.out"; exit 0; fi
if [ "$1" = "--wait" ]; then
  shift
  # valyriantech/comfyui-with-flux moves (or copies) /ComfyUI to /workspace/ComfyUI at start, then links /ComfyUI to it
  for i in $(seq 180); do [ -L /ComfyUI ] && [ -d /workspace/ComfyUI/models ] && break; sleep 10; done
fi
LOCK=/tmp/skyfur_models.lock
running() { [ -f "$LOCK/pid" ] && kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; }
if ! mkdir "$LOCK" 2>/dev/null; then
  if running; then
    echo "Models are already downloading (started at boot). Progress from /tmp/models.out:"
    while running; do tail -n 1 /tmp/models.out 2>/dev/null; sleep 60; done
    tail -n 15 /tmp/models.out 2>/dev/null; exit 0
  fi
  echo "Taking over from an earlier download that stopped."  # its partial files resume
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT
DIR="$1"
[ -z "$DIR" ] && for d in /root/ComfyUI /workspace/ComfyUI /ComfyUI; do [ -d "$d/models" ] && DIR="$d" && break; done
M="${DIR:-/root/ComfyUI}/models"
HF=https://huggingface.co
LOG=/tmp/skyfur_models.log

# <folder under models/>|<file name ComfyUI workflows use>|<HF path>|<bytes>
LIST="
checkpoints/FLUX1|flux1-dev-fp8.safetensors|Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors|17246524772
text_encoders|clip_l.safetensors|comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors|246144152
text_encoders/t5|t5xxl_fp8_e4m3fn_scaled.safetensors|comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn_scaled.safetensors|5157348688
diffusion_models|flux1-dev-kontext_fp8_scaled.safetensors|Comfy-Org/flux1-kontext-dev_ComfyUI/resolve/main/split_files/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors|11904640136
diffusion_models|ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors|Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled_transformer_only_fp8_input_scaled_v3.safetensors|25016398672
text_encoders|ltx-2.3_text_projection_bf16.safetensors|Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors|2312149072
text_encoders|gemma_3_12B_it_fp8_scaled.safetensors|Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp8_scaled.safetensors|13205434827
vae|LTX23_video_vae_bf16.safetensors|Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors|1452258578
vae|LTX23_audio_vae_bf16.safetensors|Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_audio_vae_bf16.safetensors|364855188
"

size() { stat -c %s "$1" 2>/dev/null || echo 0; }

# Files some GPU images already have in another version (valyriantech/comfyui-with-flux ships Flux Dev as
# flux1-dev.sft + ae.sft, clip_l and t5xxl_fp8_e4m3fn in models/clip). The render tools use either (tools/comfy_models.py), so skip these.
built_in() {  # name -> prints the built-in file that replaces it, if there is one
  case "$1" in
    flux1-dev-fp8.safetensors) f="$M/diffusion_models/flux1-dev.sft"; [ -s "$M/vae/ae.sft" ] || f= ;;
    clip_l.safetensors) f="$M/clip/clip_l.safetensors" ;;
    t5xxl_fp8_e4m3fn_scaled.safetensors) f="$M/clip/t5xxl_fp8_e4m3fn.safetensors"; [ -s "$f" ] || f="$M/text_encoders/t5xxl_fp8_e4m3fn.safetensors" ;;
    *) f= ;;
  esac
  [ -n "$f" ] && [ -s "$f" ] && echo "$f"
}

fetch() {  # dir name path bytes
  local out="$M/$1/$2" part="$M/$1/$2.part"
  mkdir -p "$M/$1"
  if [ "$(size "$out")" = "$4" ]; then echo "ok    $2 (already here)"; return 0; fi
  if [ -n "$(built_in "$2")" ]; then echo "ok    $2 (skipped: the image has $(built_in "$2"))"; return 0; fi
  for try in 1 2 3 4 5; do
    curl -sSL --fail -C - --retry 5 --retry-delay 5 -o "$part" "$HF/$3" 2>>"$LOG"
    if [ "$(size "$part")" = "$4" ]; then mv "$part" "$out"; echo "ok    $2"; return 0; fi
    echo "retry $2 (attempt $try, have $(size "$part") of $4 bytes)"; sleep 5
  done
  echo "FAIL  $2 (see $LOG)"; return 1
}

# Image models first (Flux Dev + text encoders + Kontext, ~35 GB) so character and frame work can start,
# then the video models (LTX-2.3, ~42 GB) while images are already rendering.
IMAGE_MODELS="flux1-dev-fp8.safetensors clip_l.safetensors t5xxl_fp8_e4m3fn_scaled.safetensors flux1-dev-kontext_fp8_scaled.safetensors"
echo "Downloading SKYFUR models into $M ..."
for phase in images video; do
  echo "--- $phase models ---"
  while IFS='|' read -r dir name path bytes; do
    [ -z "$name" ] && continue
    case " $IMAGE_MODELS " in *" $name "*) group=images ;; *) group=video ;; esac
    [ "$group" = "$phase" ] && fetch "$dir" "$name" "$path" "$bytes" &
  done <<< "$LIST"
  wait
  echo "--- $phase models done ---"
done
echo "--- check ---"
while IFS='|' read -r dir name path bytes; do
  [ -z "$name" ] && continue
  if [ "$(size "$M/$dir/$name")" = "$bytes" ]; then echo "ok    $dir/$name"
  elif [ -n "$(built_in "$name")" ]; then echo "ok    $dir/$name (using $(built_in "$name"))"
  else echo "MISSING $dir/$name"; fi
done <<< "$LIST"
echo "Done. In ComfyUI press R (refresh) or reload the page so the new models appear."
