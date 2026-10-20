# Font and asset license record (PactFall title concepts)

Recorded 2026-10-20. Applies to everything in this `branding/` folder.

## Fonts

All three typefaces are under the SIL Open Font License 1.1. The OFL allows use in logos and artwork, commercial use, and modification. Artwork made with an OFL font (including text converted to outlines) is not itself bound by the OFL. Obligations that still apply:

- If we ship the font files themselves (for example inside the game build, or this folder), keep each font's copyright line and its OFL text with them. They are kept here as `fonts/*-OFL.txt`.
- The fonts may not be sold on their own.
- A modified version of the font software may not use the Reserved Font Name ("Marcellus", "Forum"). We have not modified any font file; the letter changes exist only as artwork paths.

| Font | Used in | Designer and copyright | Reserved Font Name | Source (retrieved 2026-10-20) | File and SHA-256 |
|---|---|---|---|---|---|
| Forum Regular, v1.000 | Concept 1, Carved stele; concept 2b wordmark | Copyright (c) 2011, Denis Masharov | "Forum" | github.com/google/fonts, `ofl/forum/` (main branch) | `Forum-Regular.ttf` 5c9fbe9c4ce76d0269f5088d921d57e58082fd9c28433eacb6de95baf938adf8 |
| Marcellus Regular, v1.000 | Concept 2, Broken seal; the stone in every seal | Copyright (c) 2012, Brian J. Bonislawsky DBA Astigmatic (AOETI) | "Marcellus" | github.com/google/fonts, `ofl/marcellus/` (main branch) | `Marcellus-Regular.ttf` 1cf0cd10b17d35e852729962cc1ffaffed94514895972458345e2df34abb2f81 |
| Cormorant Garamond variable, v4.001, used at weight 600 | Concept 3, Manuscript colophon | Copyright 2015 The Cormorant Project Authors (Christian Thalmann) | none | github.com/google/fonts, `ofl/cormorantgaramond/` (main branch) | `CormorantGaramond[wght].ttf` b20b7d9626dd956b2c5e558692ad328b1f19e3275e2782db4fa07670d83f35e0 |

## Ornament and letter modifications

All made in code (`tools/make_titles.py`) from geometry: rectangles, triangles, lozenges, circle arcs. No image generation tools, no traced artwork, nothing taken from the reference collage or from any existing logo.

- Crossbarless A (concept 1) and the stone (concept 2): the font's own V outline mirrored top to bottom, so the stone is two crossbarless A's point to point.
- Word point (concept 3, Pactfall version): a drawn diamond between Pact and fall.
- Hannunvaakuna knot (concept 3): the looped square, a traditional Finnish and Nordic folk sign (also the Unicode character U+2318). It is a public domain motif; this drawing is our own construction of four bars and four tangent rings.

## Colors

Ink #211d18 and bronze #7a5a2c (for light grounds), bone #ece4d3 and bronze #c39c5c (for dark grounds), plain black and white for mono. Our own choices; no license applies.
