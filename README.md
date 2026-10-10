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

## Video images `ghcr.io/arehmandev01-dotcom/comfyui-flux-kontext:video` and `:video-full`

The same base and start-up, with the **LTX-2.3 video models** baked in instead of Flux. Salad bills only once the container is Running, so whatever is in the image downloads for free. Both start with `SKYFUR_MODELS=video`, so they never download the image models.

| Tag | Baked in | Downloads at start | Size |
|---|---|---|---|
| `:video-full` | everything LTX needs (transformer, gemma 3 12B, text projection, both VAEs) | nothing | ~48.8 GB, **may be refused by Salad as "Image Too Large"** (~50 GB was) |
| `:video` | transformer, text projection, both VAEs | gemma 3 12B text encoder only (13.2 GB, ~2–4 min) | ~35.5 GB, same as `:slim` |

Try `:video-full` first; if Salad refuses it, use `:video`. Salad settings are the same as for `:slim` (port `8188`, auth off, `CLI_ARGS` = `--listen ::`, no command). Set `SKYFUR_MODELS=all` to also download the image models.

All three tags are built by the one workflow. To rebuild only one, run it from the Actions tab with `only` = `slim`, `video` or `video-full`.
