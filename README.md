# skyfur-gpu

GPU server setup for the SKYFUR film tools (ComfyUI on SaladCloud).

## `bootstrap_models.sh`

Downloads every model the render tools need into ComfyUI (Flux Dev, Kontext, LTX-2.3 video). Safe to re-run: complete files are skipped, partial ones resume. Uses aria2c with 16 connections per file when available.

## Image `ghcr.io/arehmandev01-dotcom/comfyui-flux-kontext:kontext`

`docker.io/valyriantech/comfyui-with-flux:05042026` with **Flux Kontext baked in**, built by GitHub Actions (`.github/workflows/build-image.yml`, `image/build.sh`) whenever `image/`, `bootstrap_models.sh` or the workflow changes, or by hand from the Actions tab.

At start the image:
1. joins the baked-in Kontext parts into one file (~1 min; GHCR allows at most 10 GB per layer, so the model is stored in 4 GB parts);
2. downloads the models that are not baked in (the LTX video models, ~42 GB) in the background with `bootstrap_models.sh` (log `/tmp/models.out`);
3. runs the Valyrian image's normal start (ComfyUI on port 8188, SSH when `PUBLIC_KEY` is set).

Salad settings: image `ghcr.io/arehmandev01-dotcom/comfyui-flux-kontext:kontext`, Container Gateway port `8188`, environment `PUBLIC_KEY` = your SSH public key, no command. Optional `SKYFUR_MODELS` = `all` (default), `images`, `video` or `none`.
