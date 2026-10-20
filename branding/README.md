# PactFall title concepts (working name)

Working name picked by Anthony on 2026-10-20: PactFall (casing being confirmed). Earlier Kivivala concepts are kept in `../kivivala/` for reference.

## Folders

- `seal-forum/`: **Anthony's pick (2026-10-20)**, the broken seal with the Forum lettering and crossbarless A's from the stele. Its standalone mark is the same as `seal-mark/`.
- `stele/`, `seal/`, `seal-mark/`, `manuscript-camel/` (PactFall), `manuscript/` (Pactfall with a word point): one per concept.
  - `master/*-master.svg`: editable master. Named layers (`letters`, `ornament`, `seal-ring`, ...), colors as two CSS classes (`.ink`, `.accent`), and a hidden `live-text-reference` layer with the same word as live text at the same letter positions. It loads its font from `../../fonts/`.
  - `distribution/*.svg`: outlined, no font needed, flat fills. Four variants: `on-light`, `on-dark`, `mono-black`, `mono-white`.
  - `png/*.png`: transparent PNGs of each distribution file at 2400 px and 600 px wide.
- `sheet/`: comparison sheet (HTML and PNG) at large and small sizes, light, dark and mono.
- `fonts/`: the three OFL fonts with their license texts. See `LICENSES.md`.
- `tools/`: the generators. `make_titles.py <fonts> <out>` rebuilds every SVG; `render.js <out> 2400 600` renders the PNGs (Node + Playwright Chromium); `sheet.py <out>` and `shot.js` build the sheet. The screening helpers (`uspto_query.py`, `uspto_classes.py`, `store_search.sh`) are the ones used for the naming report.

## Renaming

Every file name and the word itself come from `make_titles.py` (`letters = ...` in each concept, and the `manuscript(...)` calls at the bottom). Changing the name means editing those three lines and rerunning the tools; spacing pairs will need a fresh look for new letters.

## Minimum sizes (from the rendered sheet)

- Carved stele: 240 px wide or more. At 120 px the rules start to compete with the letters; at 80 px it is not readable.
- Broken seal lockup: 240 px wide or more. Below that, use the seal mark alone.
- Seal mark alone: 32 px or more. At 16 px the inner ring and the break fill in.
- Manuscript colophon: readable down to 120 px; at 80 px the word still reads but the knot becomes a blot.
