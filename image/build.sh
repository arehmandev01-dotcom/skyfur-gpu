#!/bin/bash
# Builds ghcr.io/<owner>/comfyui-flux-kontext on a GitHub Actions runner (run by .github/workflows/build-image.yml).
# No docker build: crane adds new layers on top of yanwk/comfyui-boot:cu128-slim (6.4 GB, the image the octopus
# server runs) straight in the registries. Each baked-in model is downloaded once, split into 4 GB parts (GHCR's
# limit is 10 GB per layer) and added one part per layer. A last layer adds our scripts and the links ComfyUI uses.
# Size: 6.4 + 17.2 (Flux Dev fp8) + 11.9 (Kontext fp8) = ~35.5 GB, under the 38.2 GB Valyrian image that Salad
# runs (Valyrian + Kontext, ~50 GB, was refused as "Image Too Large"). t5 + clip_l (5.4 GB) would push it to
# ~41 GB, so they download at start instead (~1 min).
set -euo pipefail
BASE=docker.io/yanwk/comfyui-boot@sha256:7b75f98c317b42490529502c781bb0a699c7ca2a909a0e9df6106de853cf8fb4  # cu128-slim (2026-05-18), linux/amd64
COMFY=default-comfyui-bundle/ComfyUI  # copied to /root/ComfyUI at start by the image's entrypoint
ARIA2_ZIP=https://github.com/abcfy2/aria2-static-build/releases/download/1.37.0/aria2-x86_64-linux-musl_static.zip
ARIA2_SHA256=e0a09b12ef67f35f8a8e4fdddbec851d235b7c31da549d0578bff459032b499a
OWNER=$(echo "$GITHUB_REPOSITORY_OWNER" | tr '[:upper:]' '[:lower:]')
DEST=ghcr.io/$OWNER/comfyui-flux-kontext
WORK=$DEST:build
TAG=${TAG:-slim}
MODELS=${MODELS:-flux1-dev-fp8.safetensors flux1-dev-kontext_fp8_scaled.safetensors}  # file names from the LIST in bootstrap_models.sh
HERE=$(cd "$(dirname "$0")" && pwd)
LIST=$(sed -n '/^LIST="/,/^"/p' "$HERE/../bootstrap_models.sh" | grep '|')

T=/mnt/skyfur  # the runner's biggest free disk
sudo mkdir -p "$T" && sudo chown "$(id -u)" "$T"
df -h / "$T"
FINAL=$T/final
rm -rf "$FINAL" && mkdir -p "$FINAL"

cur=$BASE
for name in $MODELS; do
  line=$(echo "$LIST" | grep -F "|$name|")
  IFS='|' read -r dir n path bytes <<< "$line"
  echo "=== $dir/$name ($bytes bytes)"
  mkdir -p "$T/dl"
  aria2c -q -c -x 16 -s 16 -k 20M --file-allocation=none --max-tries=5 -d "$T/dl" -o "$name" "https://huggingface.co/$path"
  got=$(stat -c %s "$T/dl/$name")
  [ "$got" = "$bytes" ] || { echo "size mismatch: $got != $bytes"; exit 1; }
  rm -rf "$T/parts" && mkdir -p "$T/parts"
  (cd "$T/parts" && split -b 4000M -d -a 2 "$T/dl/$name" "$name.part")
  rm -f "$T/dl/$name"
  for p in "$T/parts/$name".part*; do
    st=$T/stage
    rm -rf "$st" && mkdir -p "$st/models_baked/$dir"
    mv "$p" "$st/models_baked/$dir/"
    tar -C "$st" --owner=0 --group=0 -cf - models_baked | pigz -1 > "$T/layer.tgz"
    echo "  + layer $(basename "$p") ($(stat -c %s "$T/layer.tgz") bytes)"
    crane append -b "$cur" -f "$T/layer.tgz" -t "$WORK"
    cur=$WORK
    rm -rf "$st" "$T/layer.tgz"
  done
  mkdir -p "$FINAL/$COMFY/models/$dir"
  ln -s "/models_baked/$dir/$name" "$FINAL/$COMFY/models/$dir/$name"
done

# last layer: the image's entrypoint with our start-up block added (same CMD, so the start is otherwise the
# image's own), the part joiner, the model download script, a static aria2c (the image has none; one HF
# connection gets 3-6 MB/s, 16 get ~50) and the links from ComfyUI's model folders to /models_baked
cp "$HERE/skyfur_assemble.sh" "$HERE/../bootstrap_models.sh" "$FINAL/"
mkdir -p "$FINAL/runner-scripts" "$FINAL/usr/local/bin"
cp "$HERE/entrypoint.sh" "$FINAL/runner-scripts/entrypoint.sh"
chmod 755 "$FINAL"/*.sh "$FINAL/runner-scripts/entrypoint.sh"
curl -sSL -o "$T/aria2.zip" "$ARIA2_ZIP"
echo "$ARIA2_SHA256  $T/aria2.zip" | sha256sum -c -
unzip -o -q "$T/aria2.zip" aria2c -d "$FINAL/usr/local/bin" && chmod 755 "$FINAL/usr/local/bin/aria2c"
(cd "$FINAL" && tar --owner=0 --group=0 -cf - $(ls -A) | tar -tvf - | grep -v '^d')
(cd "$FINAL" && tar --owner=0 --group=0 -cf - $(ls -A)) | pigz -1 > "$T/layer.tgz"
crane append -b "$cur" -f "$T/layer.tgz" -t "$WORK"
crane mutate "$WORK" --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY" -t "$DEST:$TAG"
echo "Built $DEST:$TAG"
crane manifest "$DEST:$TAG" | python3 -c "import sys,json;m=json.load(sys.stdin);print(len(m['layers']),'layers,',round(sum(l['size'] for l in m['layers'])/1e9,1),'GB compressed')"
