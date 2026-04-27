# Grainient.supply — Competitive Analysis

**Crawled:** 2026-04-27 · **Source:** https://grainient.supply/collections · **Method:** scraped 50 collection pages, downloaded 42 preview thumbnails (325×238 from Framer CDN), classified visually.

> **TL;DR.** Grainient sells **static** PNG/JPG/WEBP assets bucketed into ~55 themed *collections* (mostly 12–60 assets each). Roughly **half** of their catalog is AI-generated 3D/glass renders we cannot produce procedurally without 3D rendering or an image-generation pipeline. The **other half** — soft hero blurs, mesh gradients, grainy/noisy gradients, smoke clouds, simple radial blooms — overlaps directly with what GradientStudio already does or can do with **2–3 small additions**. We also have a structural advantage they lack: **animated, exportable video output**.
>
> **Net position:** we cover ~30% of their visual surface today; with ~5 small/medium additions (radial-bloom layer, heavier grain, halftone, light-streak, noise-driven liquid metal) we get to ~55%; the remaining ~45% (true 3D glass, fractal stripes, AI-themed scenes) is out of scope for a procedural shader app.

---

## 1. Product taxonomy (what they actually ship)

Their catalog clusters into **9 visual techniques**. The 55 collections are mostly re-skins of these same 9 techniques on different palettes.

| # | Technique cluster | Example collections | What's actually rendering |
|---|---|---|---|
| **A** | **Soft hero blur** (2-color radial/linear bloom on dark) | Hero V1/V2/V3, Darkmists, Mistmusks, Dramatic, Gradient Burst, Syntone, Ultravibe, Moon, SwiftGlow, LightGlow, Apple GIOS18 | Photoshop-style large gaussian blur over a 2-color gradient; sometimes a single bright orb. Static. |
| **B** | **Mesh / aurora cloud** | Shadeshifter, Galactic | Multi-stop mesh gradient, often with smoke noise. |
| **C** | **3D rendered glass / liquid** | Cubic Glass, Luma, Lavendery, Nova, Glossy Backgrounds, Darkshells, Mandrillians, Phantom, Inflated | True 3D render (C4D/Octane/AI) with normals, refraction, specular, caustics. |
| **D** | **Iridescent / spectral curve** | Chroma, Nova, Redilliums | Curved color-band sweep mimicking dispersion. |
| **E** | **Sparkle / vertical light beams** | Sparkles, Fractal Walls | Single bright vertical beam with bloom + particle dots. |
| **F** | **Fractal / fine stripe ribbons** | Fractal Maze a/b/c, Fractal Nights | Parallel iridescent strands, often warped. |
| **G** | **Heavy grain / halftone** | Spectral Gradient (Darks/Lights), Japaneasy, Chaotic Gradients a–d, Adamantiums | Color blob + very heavy 35mm grain or halftone overlay. |
| **H** | **Liquid / fluid 3D** | Lemonade, Glass Sands, Tangerines, Cold Oceans, Oceanics, Serenmists, Celestials, Mistnova, Franciums | Volumetric liquid render with caustics. |
| **I** | **Themed / AI-generated scenes** | Apple GIOS18, BlueRays, Fuchsia, Ruby, Shockwave, Galactic Rings, Dreamy Fabrica | Subject-specific AI image gens (rings, orbs, Apple-iPhone homages). |

---

## 2. Collection matrix (one row per collection)

**Legend** — *Status:* ✅ done · 🟡 partial · ❌ missing. *Complexity to close:* **S** ½-day shader, **M** 1–2 day layer kind + UI, **L** 1–2 wk multi-pass, **XL** out of scope (3D / AI).

| # | Collection | Count | Description (theirs) | Cluster | Visual technique I observed | Our status | Complexity |
|---|---|---|---|---|---|---|---|
| 1 | **Hero Gradients V3** | 48 | Ultra creative Hero gradient designs | A | Orange→black radial bloom, large gaussian | 🟡 close | S — add radial-falloff to linear |
| 2 | **Cubic Glass** | 20 | Smooth blend cubic textured gradients | C | Pixelated 3D Lego/voxel cubes refracting | ❌ | XL — 3D render |
| 3 | **Hero Gradients V2** | 32 | Smooth blurry gradients for landing pages | A | Vinyl-record concentric blue blur on black | 🟡 | S — radial bands shader |
| 4 | **Shadeshifter** | 28 | 6K mesh gradients & backgrounds | B | Diagonal navy mesh sweep | ✅ | — (mesh.grid does this) |
| 5 | **Galactic** | 28 | Universal & galactic art gradients | B | Cosmic blue smoke cloud | ✅ | — (mesh.smoke + grain) |
| 6 | **SwiftGlow Gradients** | 12 | Light-mode gradients | A | Pastel pink/blue radial bloom | 🟡 | S — radial primitive |
| 7 | **Lemonade** | 7 | Abstract liquify AI background | H | Green 3D glass refraction | ❌ | XL — 3D fluid |
| 8 | **Fractal Walls** | 8 | Customized fractal glass | E/F | Vertical green light beam + glow | ❌ | M — beam shader |
| 9 | **Dreamy Fabrica** | 12 | AI-Generated artistic | I | (no static thumb; AI scenes) | ❌ | XL |
| 10 | **LightGlow Gradients** | 12 | Light mode gradients | A | Bokeh-style multi-orb soft circles | 🟡 | M — bokeh/orb layer |
| 11 | **BlueRays** | 12 | Blue 3D rendered backgrounds | C | Stacked blue glass shells | ❌ | XL — 3D render |
| 12 | **Syntone** | 24 | Hero-section gradients | A | Horizontal blue light beam on black | 🟡 | S — godray shader |
| 13 | **Luma** | 16 | 12K iridescent glass liquid | C | 3D glass tube with refraction | ❌ | XL |
| 14 | **Sparkles** | 32 | Lighting glass textured | E | Vertical green stripes + spectral curve | ❌ | M — stripe + bloom |
| 15 | **Ultravibe** | 20 | Hero-section gradients | A | Orange wave-shaped blur on black | 🟡 | S — wave-shaped bloom |
| 16 | **Moon** | 12 | Moon crescent gradients | A | Pure 2-color radial bloom (Mac-OS-style) | 🟡 | S — radial primitive |
| 17 | **Lavendery** | 12 | 3D abstract liquid glass | C | Purple 3D ribbon w/ specular | ❌ | XL |
| 18 | **Chroma** | 20 | Chromatic light gradients | D | Curved spectral red/blue/orange band | ❌ | M — spectral curve |
| 19 | **Phantom** | 16 | Abstract 3D glass | C | (no thumb — 3D glass) | ❌ | XL |
| 20 | **Nova** | 12 | Spectrum lighting 3D glass | C/D | 3D liquid-metal black ribbon | ❌ | XL |
| 21 | **Dramatic Gradients** | 34 | Beautiful gradient backgrounds | A | Pink/red bloom on black | 🟡 | S — radial primitive |
| 22 | **Gradient Burst** | 30 | 12K AI gradients | A | Navy + red horizontal blur | 🟡 | S |
| 23 | **Ruby Gradients** | 12 | AI flowing gradients | A | Red wave on black | 🟡 | S — wave-shaped bloom |
| 24 | **Glossy Backgrounds** | 16 | 3D ethereal liquid darkmode | C | Pink/blue/orange 3D glass ribbon | ❌ | XL |
| 25 | **Franciums** | 20 | 3D ethereal liquid | H | Gold/silver 3D ribbon | ❌ | XL |
| 26 | **Japaneasy** | 20 | Noisy & abstract textured | G | Pink+green halftone-grain blob | 🟡 | S — heavier grain + halftone |
| 27 | **Adamantiums** | 20 | Noisy & abstract textured | G | (no thumb — same family as Japaneasy) | 🟡 | S |
| 28 | **Shockwave** | 15 | 3D abstract | C | Dark glass tube + orange rim | ❌ | XL |
| 29 | **Hero Gradients** | 36 | Smooth blurry hero | A | Orange→black radial bloom | 🟡 | S |
| 30 | **Chaotic Gradients (a–d)** | 25×4 | Noisy flower & dreamy | G | Heavy 35mm grain over orange/blue cloud | 🟡 | S — heavier grain |
| 31 | **Fuchsia** | 18 | 3D abstract | C | Purple/orange 3D neon ring | ❌ | XL |
| 32 | **Apple GIOS18** | 12 | Apple iPhone-16 inspired | I | Glass orbs on black | ❌ | XL — themed AI |
| 33 | **Fractal Maze (a–c)** | 19–20×3 | Fractal glass texture | F | Iridescent rainbow stripe ribbons | ❌ | M — stripe-warp shader |
| 34 | **Spectral Gradient (Darks)** | 50 | Noise textured darkmode | G | Near-black with diagonal grain bloom | 🟡 | S — heavier grain |
| 35 | **Spectral Gradient (Lights)** | 50 | Noise textured lightmode | G | Pink very-grainy soft blob | 🟡 | S |
| 36 | **Darkmists** | 60 | Smooth blurry darkmode | A | Dark navy + green diagonal sweep | 🟡 | S |
| 37 | **Mistmusks** | 60 | Smooth blurry lightmode | A | Pastel teal/orange soft blend | 🟡 | S |
| 38 | **Redilliums** | 28 | Red+blue metallic | C/D | (no thumb) | ❌ | XL |
| 39 | **Darkshells** | 12 | Dark glass material | C | Soft 3D dark shell render | ❌ | XL |
| 40 | **Fractal Nights** | 12 | Colorful metallic turbulent | F | Iridescent thin-strand pattern | ❌ | M |
| 41 | **Serenmists** | 16 | Galactic glassy fusion rings | H | Pink/orange 3D silk fabric | ❌ | XL |
| 42 | **Galactic Rings** | 16 | Galactic glassy rings | I | (no thumb — themed rings) | ❌ | XL |
| 43 | **Cold Oceans** | 22 | Twilight chaotic ocean | H | Blue/red 3D water ripple | ❌ | XL |
| 44 | **Celestials** | 21 | Silky colorful | H | Pink/blue 3D silk fabric | ❌ | XL |
| 45 | **Oceanics** | 21 | Melting glass liquid | H | (no thumb — 3D liquid) | ❌ | XL |
| 46 | **Mistnova** | 20 | Lavender ocean vibes | H | Orange/blue calm 3D dunes | ❌ | XL |
| 47 | **Mandrillians** | 21 | Shiny fire glass | C | (no thumb — 3D glass fire) | ❌ | XL |
| 48 | **Glass Sands** | 22 | Colorful glass desert | F | Rainbow ribbon strands | ❌ | M |
| 49 | **Inflated** | 9 | Inflated blending | C | (no thumb) | ❌ | XL |
| 50 | **Tangerines** | 20 | Orange silky infinite fusion | H | Pink/orange 3D silk fabric | ❌ | XL |

*8 collections (rows 9, 19, 27, 38, 42, 45, 47, 49) only ship images via client-side JS; classified from descriptions + sister collections.*

---

## 3. Capability comparison (rolled up)

| Capability | Grainient | GradientStudio (today) | Coverage |
|---|---|---|---|
| 2-color linear gradient | implicit base | ✅ `linear` layer | full |
| Mesh gradient (multi-stop blob blend) | Shadeshifter, Galactic | ✅ `mesh.grid` (4×4) | full |
| Smoke / cloud noise | Galactic, hero blurs | ✅ `mesh.smoke` | full |
| Discrete blob/orb | LightGlow, Apple GIOS18 | ✅ `mesh.blobs` (positional) | most |
| Wave / UV distortion | implicit (blurs are static) | ✅ `wave` (noise-based) | we exceed |
| Chromatic aberration | rare | ✅ `glass.aberration` | we exceed |
| Blur post | core to ~half catalog | ✅ `glass.blurRadius` | full |
| Film grain | post-fx on most | 🟡 `globals.grainAmount` 0–0.3 — too subtle for their G-cluster | partial |
| Vignette | implicit | ✅ `globals.vignetteAmount` | full |
| **Animated loopable output** | ❌ static only | ✅ `loopDuration` + MP4 export | **we exceed** |
| **Programmatic preset / API** | ❌ download asset | ✅ JSON v2 preset, headless export | **we exceed** |
| Radial bloom primitive (single bright spot, smooth falloff) | core to A-cluster (~25 collections) | ❌ workaround via mesh.blobs | **gap** |
| Light-beam / godray (single elongated streak) | Syntone, Sparkles, Fractal Walls | ❌ | **gap** |
| Spectral curve (dispersion-style band) | Chroma, Nova | ❌ | **gap** |
| Halftone overlay | Japaneasy, Chaotic | ❌ | **gap** |
| Stripe / fractal-strand pattern | Fractal Maze, Glass Sands | ❌ | **gap** |
| 3D normal-mapped glass / liquid | C + H clusters (~40% of catalog) | ❌ flat shader only | **out of scope** |
| AI image generation | I cluster (~10%) | ❌ | **out of scope** |
| Color palette extraction from image | (no equivalent) | ✅ k-means over imported image | **we exceed** |

---

## 4. Gap roadmap (ranked by ROI)

ROI = catalog coverage gained / engineering complexity. Top of list closes the most ground for the least work.

| Rank | Add | Closes (collections) | New layer? | Complexity | Est. effort |
|---|---|---|---|---|---|
| 1 | **`radial` layer kind** — single bright spot at (cx,cy) with falloff exponent + 2 colors. Animate cx/cy + radius. | ~25 (Hero V1/V2/V3, Moon, SwiftGlow, Dramatic, Gradient Burst, Ruby, Ultravibe, Mistmusks, Darkmists, …) | yes | S | ½–1 day |
| 2 | **Heavier grain + halftone option** — extend `globals.grainAmount` cap to 1.0; add `grainStyle: { film, halftone-dots, halftone-lines }` | ~10 (all chaotic/spectral/Japaneasy) | no — extend post-fx | S | ½ day |
| 3 | **`beam` layer kind** — elongated 1-D bloom (godray) with angle, length, width, falloff. | ~5 (Syntone, Sparkles, Fractal Walls, Chroma) | yes | S–M | 1 day |
| 4 | **`spectral` layer kind** — color-dispersion curved band sampled along an arc. | ~5 (Chroma, Nova, Fractal Maze, Redilliums) | yes | M | 1–2 days |
| 5 | **Bokeh multi-orb** — N circular gaussian blobs with separate colors/positions (extend `mesh.blobs` to allow >16 points and per-point radius). | ~3 (LightGlow) | extend | S | ½ day |
| 6 | **`stripe` layer kind** — N parallel iridescent strands warped by the scene's existing wave displacement. | ~5 (Fractal Maze, Glass Sands, Fractal Nights) | yes | M | 2 days |
| 7 | **Pseudo-3D normal layer** — fake glass via radial gradient + specular highlight + warped UV (cheap, won't fool anyone but covers ~30% of cluster C visually). | ~5 (Phantom, Darkshells, partial Lavendery) | yes | L | 1–2 wk |

After rank 1–6 (≈5 working days), our coverage of their catalog goes from ~30% → ~55%. Rank 7 is the boundary where procedural can plausibly substitute for true 3D — past that, we should accept "we don't render 3D" as a positioning choice rather than a roadmap item.

---

## 5. Strategic positioning

**Where we already win**

- **Animation.** Their entire catalog is static. Every loop we export is a new product they can't ship.
- **Editability.** They ship pixels; we ship a parameterized scene. A user can re-color, re-time, and re-aspect any of our presets.
- **Pipeline.** Headless export + JSON presets + GitHub Action releases — they have none of that.
- **Palette extraction.** Drop an image, get a tuned mesh. They have no tooling, only finished assets.

**Where we'd be unwise to compete**

- True 3D glass / liquid renders (~45% of their catalog). Octane / C4D / AI image-gen pipelines own that surface. Adding raymarching to a Metal compositor app is a different project.
- Themed AI scenes (Apple iPhone wallpapers, fire glass, ocean liquid). Wrong abstraction layer.

**The 80/20 play**

Ship items 1–3 of the gap roadmap (radial, heavier grain/halftone, beam) and ~4 new presets per addition. That puts us at parity with the **hero-blur** half of their catalog — which is most of their commercial volume — while keeping the "animated, parameterized, exportable" wedge they cannot match.

---

## 6. Methodology notes

- **Crawl:** raw HTML via `curl` over 50 collection slugs. Framer's static SSR exposed thumbnail URLs (325×238) for 42 of them; the remaining 8 lazy-load via JS and were classified from descriptions + adjacent collections.
- **CV:** thumbnails read inline via the multimodal Read tool; technique classification by visual inspection across the 9 clusters above. No automated CV model — counts and clusters are my read of the images, not pixel statistics.
- **Limitations:** thumbnails are 325 px so fine grain/halftone differences are partially lost; collection counts come from their own page metadata and may include retired items.

---

*Source data: `/tmp/grainient-crawl/` (HTML + 42 thumbnails). Re-run `Scripts/` equivalent if we want to track their drift over time.*
