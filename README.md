# skyfur-gpu

GPU server setup for the SKYFUR film tools (ComfyUI on SaladCloud).

## `bootstrap_models.sh`

Downloads every model the render tools need into ComfyUI (Flux Dev, Kontext, LTX-2.3 video). Safe to re-run: complete files are skipped, partial ones resume. Uses aria2c with 16 connections per file when available.

## Image `ghcr.io/arehmandev01-dotcom/comfyui-flux-kontext:slim`

`yanwk/comfyui-boot:cu128-slim` (the image the octopus server runs) with **Flux Dev fp8 and Flux Kontext fp8 baked in**, ~35.5 GB, built by GitHub Actions (`.github/workflows/build-image.yml`, `image/build.sh`) whenever `image/`, `bootstrap_models.sh` or the workflow changes, or by hand from the Actions tab. (The older `:kontext` tag, Valyrian + Kontext, is ~50 GB and Salad refuses it as "Image Too Large".)

At start the image runs yanwk's own entrypoint with one added block (`image/entrypoint.sh`), which:
1. joins the baked-in model parts into whole files (~2 min; GHCR allows at most 10 GB per layer, so models are stored in 4 GB parts);
2. downloads the models that are not baked in in the background with `bootstrap_models.sh` and a bundled aria2c (log `/tmp/models.out`): t5 + clip_l for Kontext (5.4 GB, about a minute), then the LTX video models (~42 GB).

ComfyUI then starts as usual on port 8188 (models in `/root/ComfyUI/models`).

Salad settings: image `ghcr.io/arehmandev01-dotcom/comfyui-flux-kontext:slim`, Container Gateway port `8188` with authentication off, environment `CLI_ARGS` = `--listen ::`, no command. Optional `SKYFUR_MODELS` = `all` (default), `images`, `video` or `none`.
