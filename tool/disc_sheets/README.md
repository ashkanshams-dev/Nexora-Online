# v11 disc sheets → assets/g/teams_v11

Pipeline used to cut the 2026-11 disc sheets (13 unique sheets out of 20 uploads; 7 uploads were the same
sheet twice — a transparent "Picsart" copy and the original — the original RGB file was used when both existed).

1. `detect.py` – distance-transform pre-pass (median radius per sheet)
2. `hough.py` – Hough circle detection around that radius
3. `crop.py` – de-duplicate, order circles row-major (`final.json` = exact centre/radius per disc)
4. `build.py` – square crop of the original pixels, 4× super-sampled circular alpha mask (1.5 px inset, no
   recolouring), LANCZOS downscale to 384 px only when the crop is larger (smaller crops keep native size —
   no upscaling), WebP q90 RGBA.

`v11_manifest.json` lists every disc: id, art key, category, name, price/stats, source sheet.
Skipped: the 20-logo car sheet (1655×950, 5×4 grid) is pixel-identical art to the existing `car14`–`car33`.
