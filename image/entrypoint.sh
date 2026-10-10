#!/bin/bash
# Start of the SKYFUR GPU image: yanwk/comfyui-boot:cu128-slim's own /runner-scripts/entrypoint.sh, unchanged
# except for the "SKYFUR" block, which starts two background jobs before ComfyUI:
# 1. join the baked-in model parts (/models_baked) into whole files (~2 min)
# 2. download every model that is not baked in (t5 + clip_l for Kontext, then the LTX video models), with aria2c
#    SKYFUR_MODELS=all (default) | images | video | none; progress in /tmp/models.out

set -e

echo "########################################"

# Run user's set-proxy script
cd /root
if [ ! -f "/root/user-scripts/set-proxy.sh" ] ; then
    mkdir -p /root/user-scripts
    cp /runner-scripts/set-proxy.sh.example /root/user-scripts/set-proxy.sh
else
    echo "[INFO] Running set-proxy script..."

    chmod +x /root/user-scripts/set-proxy.sh
    source /root/user-scripts/set-proxy.sh
fi ;

# Copy ComfyUI from cache to workdir if it doesn't exist
cd /root
if [ ! -f "/root/ComfyUI/main.py" ] ; then
    mkdir -p /root/ComfyUI
    # 'cp --archive': all file timestamps and permissions will be preserved
    # 'cp --update=none': do not overwrite
    if cp --archive --update=none "/default-comfyui-bundle/ComfyUI/." "/root/ComfyUI/" ; then
        echo "[INFO] Setting up ComfyUI..."
        echo "[INFO] Using image-bundled ComfyUI (copied to workdir)."
    else
        echo "[ERROR] Failed to copy ComfyUI bundle to '/root/ComfyUI'" >&2
        exit 1
    fi
else
    echo "[INFO] Using existing ComfyUI in user storage..."
fi

# SKYFUR: the bundle's model folders hold links to /models_baked, copied above with the rest of ComfyUI
echo "[INFO] SKYFUR: joining baked-in models (/tmp/skyfur_assemble.log), downloading the rest (/tmp/models.out)"
setsid nohup bash /skyfur_assemble.sh > /tmp/skyfur_assemble.log 2>&1 < /dev/null &
case "${SKYFUR_MODELS:-all}" in
  none) ;;
  images) bash /bootstrap_models.sh --images-only --bg || true ;;
  video) bash /bootstrap_models.sh --video-only --bg || true ;;
  *) bash /bootstrap_models.sh --bg || true ;;
esac

# Run user's pre-start script
cd /root
if [ ! -f "/root/user-scripts/pre-start.sh" ] ; then
    mkdir -p /root/user-scripts
    cp /runner-scripts/pre-start.sh.example /root/user-scripts/pre-start.sh
else
    echo "[INFO] Running pre-start script..."

    chmod +x /root/user-scripts/pre-start.sh
    source /root/user-scripts/pre-start.sh
fi ;

echo "[INFO] Starting ComfyUI..."
echo "########################################"

# Let .pyc files be stored in one place
export PYTHONPYCACHEPREFIX="/root/.cache/pycache"
# Let PIP install packages to /root/.local
export PIP_USER=true
# Add above to PATH
export PATH="${PATH}:/root/.local/bin"
# Suppress [WARNING: Running pip as the 'root' user]
export PIP_ROOT_USER_ACTION=ignore

cd /root

python3 ./ComfyUI/main.py --listen --port 8188 ${CLI_ARGS}
