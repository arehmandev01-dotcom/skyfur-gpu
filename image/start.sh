#!/bin/bash
# Start of the SKYFUR GPU image (valyriantech/comfyui-with-flux + Kontext baked in).
# 1. join the baked-in model parts (/models_baked) into whole files, in the background (~1 min)
# 2. download every model that is not baked in (the LTX video models), in the background, with aria2c
#    SKYFUR_MODELS=all (default) | images | video | none
# 3. hand over to the image's own start script (SSH when PUBLIC_KEY is set, ComfyUI on port 8188)
nohup bash /skyfur_assemble.sh > /tmp/skyfur_assemble.log 2>&1 < /dev/null &
case "${SKYFUR_MODELS:-all}" in
  none) ;;
  images) bash /bootstrap_models.sh --images-only --bg --wait ;;
  video) bash /bootstrap_models.sh --video-only --bg --wait ;;
  *) bash /bootstrap_models.sh --bg --wait ;;
esac
exec bash /start-valyrian.sh
