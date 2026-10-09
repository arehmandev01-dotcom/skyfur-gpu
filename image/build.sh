#!/bin/bash
# Builds ghcr.io/<owner>/comfyui-flux-kontext on a GitHub Actions runner (run by .github/workflows/build-image.yml).
# No docker build: crane adds new layers on top of the Valyrian image straight in the registries, so its 38 GB are
# never stored on the runner. Each baked-in model is downloaded once, split into 4 GB parts (GHCR's limit is
# 10 GB per layer) and added one part per layer. A last layer adds our start scripts and the links ComfyUI uses.
set -euo pipefail
BASE=docker.io/valyriantech/comfyui-with-flux@sha256:6a92d069d85bd2b2e8b82900d1712f244836b8129163ee508894d6538752939c
OWNER=$(echo "$GITHUB_REPOSITORY_OWNER" | tr '[:upper:]' '[:lower:]')
DEST=ghcr.io/$OWNER/comfyui-flux-kontext
WORK=$DEST:build
TAG=${TAG:-kontext}
MODELS=${MODELS:-flux1-dev-kontext_fp8_scaled.safetensors}  # file names from the LIST in bootstrap_models.sh
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
  mkdir -p "$FINAL/ComfyUI/models/$dir"
  ln -s "/models_baked/$dir/$name" "$FINAL/ComfyUI/models/$dir/$name"
done

# last layer: our start script in place of the image's (which is kept as /start-valyrian.sh), the part joiner,
# the model download script, and the links from ComfyUI's model folders to /models_baked
cp "$HERE/start.sh" "$HERE/start-valyrian.sh" "$HERE/skyfur_assemble.sh" "$HERE/../bootstrap_models.sh" "$FINAL/"
chmod 755 "$FINAL"/*.sh
(cd "$FINAL" && tar --owner=0 --group=0 -cf - $(ls -A)) | pigz -1 > "$T/layer.tgz"
crane append -b "$cur" -f "$T/layer.tgz" -t "$WORK"
crane mutate "$WORK" --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY" -t "$DEST:$TAG"
echo "Built $DEST:$TAG"
crane manifest "$DEST:$TAG" | python3 -c "import sys,json;m=json.load(sys.stdin);print(len(m['layers']),'layers,',round(sum(l['size'] for l in m['layers'])/1e9,1),'GB compressed')"
