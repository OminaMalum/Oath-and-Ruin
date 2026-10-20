#!/usr/bin/env python3
"""Build the three PACTFALL title treatment concepts as SVG.

All geometry is generated here from OFL font outlines plus hand set
parameters (spacing, modified letters, ornament). No image generation.

Usage: python3 make_titles.py <fonts_dir> <out_dir>
"""
import math
import os
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

FONTS, OUT = sys.argv[1], sys.argv[2]

# Ink sets for the variants. "light" means: for use ON a light background.
VARIANTS = {
    "on-light": {"ink": "#211d18", "accent": "#7a5a2c"},
    "on-dark": {"ink": "#ece4d3", "accent": "#c39c5c"},
    "mono-black": {"ink": "#000000", "accent": "#000000"},
    "mono-white": {"ink": "#ffffff", "accent": "#ffffff"},
}


class Face:
    def __init__(self, file, family, wght=None):
        self.file, self.family = file, family
        tt = TTFont(os.path.join(FONTS, file))
        if wght and "fvar" in tt:
            tt = instancer.instantiateVariableFont(tt, {"wght": wght})
        self.tt = tt
        self.gs = tt.getGlyphSet()
        self.cmap = tt.getBestCmap()
        self.upm = tt["head"].unitsPerEm
        self.cap = tt["OS/2"].sCapHeight
        self.xh = tt["OS/2"].sxHeight
        self.wght = wght

    def name(self, ch):
        return self.cmap[ord(ch)]

    def adv(self, ch):
        return self.tt["hmtx"][self.name(ch)][0]

    def bounds(self, ch):
        bp = BoundsPen(self.gs)
        self.gs[self.name(ch)].draw(bp)
        return bp.bounds

    def path(self, ch, x, base, size, flip=False):
        """SVG path for a glyph. flip=True mirrors it top to bottom inside
        the cap height (V becomes a crossbarless A)."""
        s = size / self.upm
        pen = SVGPathPen(self.gs, ntos=lambda v: ("%.2f" % v).rstrip("0").rstrip("."))
        if flip:
            t = (s, 0, 0, s, x, base - s * self.cap)
        else:
            t = (s, 0, 0, -s, x, base)
        self.gs[self.name(ch)].draw(TransformPen(pen, t))
        return pen.getCommands()

    def top_contour_bounds(self, ch):
        rp = RecordingPen()
        self.gs[self.name(ch)].draw(rp)
        contours, cur = [], []
        for op, args in rp.value:
            cur.append((op, args))
            if op in ("closePath", "endPath"):
                contours.append(cur)
                cur = []
        best = None
        for c in contours:
            pts = [p for _, a in c for p in a]
            ys = [p[1] for p in pts]
            xs = [p[0] for p in pts]
            b = (min(xs), min(ys), max(xs), max(ys))
            if best is None or b[3] > best[3]:
                best = b
        return best


def f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def lozenge(cx, cy, w, h):
    return "M%s %sL%s %sL%s %sL%s %sZ" % (f(cx), f(cy - h / 2), f(cx + w / 2), f(cy), f(cx), f(cy + h / 2), f(cx - w / 2), f(cy))


def rect(x, y, w, h):
    return "M%s %sH%sV%sH%sZ" % (f(x), f(y), f(x + w), f(y + h), f(x))


def tri(x1, y1, x2, y2, x3, y3):
    return "M%s %sL%s %sL%s %sZ" % tuple(f(v) for v in (x1, y1, x2, y2, x3, y3))


def circle_d(cx, cy, r, cw=True):
    """Circle as two arcs. cw picks winding so rings can be built with
    nonzero fill (outer one way, inner the other)."""
    sw = 1 if cw else 0
    return "M%s %sA%s %s 0 1 %d %s %sA%s %s 0 1 %d %s %sZ" % (
        f(cx - r), f(cy), f(r), f(r), sw, f(cx + r), f(cy), f(r), f(r), sw, f(cx - r), f(cy))


def ring(cx, cy, r_out, r_in):
    return circle_d(cx, cy, r_out, True) + circle_d(cx, cy, r_in, False)


def arc_band(cx, cy, r_out, r_in, a0, a1):
    """Filled ring segment from angle a0 to a1 (degrees, clockwise from 12
    o'clock), ends cut radially. Used for the broken seal."""
    def pt(r, a):
        t = math.radians(a)
        return cx + r * math.sin(t), cy - r * math.cos(t)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    p0, p1 = pt(r_out, a0), pt(r_out, a1)
    q1, q0 = pt(r_in, a1), pt(r_in, a0)
    return "M%s %sA%s %s 0 %d 1 %s %sL%s %sA%s %s 0 %d 0 %s %sZ" % (
        f(p0[0]), f(p0[1]), f(r_out), f(r_out), large, f(p1[0]), f(p1[1]),
        f(q1[0]), f(q1[1]), f(r_in), f(r_in), large, f(q0[0]), f(q0[1]))


def set_word(face, letters, size, base, tracking, pairs=None, flips=(), x0=0.0):
    """Lay out letters with our own spacing. Returns (list of (ch, x, d,
    flipped)), right edge. pairs adds extra space (em units) per letter
    pair; flips holds indices drawn as mirrored V."""
    pairs = pairs or {}
    s = size / face.upm
    x = x0
    out = []
    for i, ch in enumerate(letters):
        flip = i in flips
        g = "V" if flip else ch
        out.append((ch, x, face.path(g, x, base, size, flip), flip, g))
        x += face.adv(g) * s + tracking * size
        if i + 1 < len(letters):
            x += pairs.get(letters[i] + letters[i + 1], 0) * size
    return out, x - tracking * size


def ink_bounds(face, glyphs, size, base):
    s = size / face.upm
    xs, ys = [], []
    for ch, x, d, flip, g in glyphs:
        b = face.bounds(g)
        if b is None:
            continue
        xs += [x + b[0] * s, x + b[2] * s]
        if flip:
            ys += [base - s * face.cap + b[1] * s, base - s * face.cap + b[3] * s]
        else:
            ys += [base - b[3] * s, base - b[1] * s]
    return min(xs), min(ys), max(xs), max(ys)


STYLE = """<style>
      /* Edit these two colors to restyle. Variants used:
         on-light ink #211d18 accent #7a5a2c, on-dark ink #ece4d3 accent #c39c5c,
         mono: one color for both. */
      .ink { fill: %(ink)s; }
      .accent { fill: %(accent)s; }
      .live { font-family: '%(family)s'; fill: %(ink)s; }
    </style>"""


def svg_doc(w, h, body, title, desc, style=""):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%s" height="%s">\n'
            '  <title>%s</title>\n  <desc>%s</desc>\n  %s\n%s\n</svg>\n') % (f(w), f(h), f(w), f(h), title, desc, style, body)


def emit(concept, w, h, layers, face, master_extra, desc):
    """layers: list of (id, cls, [d...]). Writes the editable master (named
    layers, live text reference layer, CSS colors) and four outlined
    distribution files with inline fills."""
    os.makedirs(os.path.join(OUT, concept, "master"), exist_ok=True)
    os.makedirs(os.path.join(OUT, concept, "distribution"), exist_ok=True)
    title = "PACTFALL title concept: %s" % concept
    # master
    body = []
    for lid, cls, ds in layers:
        body.append('  <g id="%s" class="%s">' % (lid, cls))
        for i, d in enumerate(ds):
            body.append('    <path id="%s-%d" d="%s"/>' % (lid, i + 1, d))
        body.append("  </g>")
    body.append(master_extra)
    v = VARIANTS["on-light"]
    style = STYLE % {"ink": v["ink"], "accent": v["accent"], "family": face.family}
    style = ('<defs>\n    <style>@font-face { font-family: \'%s\'; src: url(\'../../fonts/%s\'); }</style>\n  </defs>\n  ' % (face.family, face.file)) + style
    with open(os.path.join(OUT, concept, "master", "pactfall-%s-master.svg" % concept), "w") as fh:
        fh.write(svg_doc(w, h, "\n".join(body), title + " (editable master)", desc, style))
    # distribution: outlines only, one flat fill per layer, no font needed
    for vname, v in VARIANTS.items():
        body = []
        for lid, cls, ds in layers:
            body.append('  <path id="%s" fill="%s" d="%s"/>' % (lid, v[cls], "".join(ds)))
        with open(os.path.join(OUT, concept, "distribution", "pactfall-%s-%s.svg" % (concept, vname)), "w") as fh:
            fh.write(svg_doc(w, h, "\n".join(body), title + " (" + vname + ")", desc))


def live_layer(face, glyphs, size, base, note, weight=None):
    """Hidden reference layer: the same word as live text at the same
    positions, so the spacing can be re-typeset or edited in a vector app."""
    xs = " ".join(f(x) for _, x, _, _, _ in glyphs)
    txt = "".join(ch for ch, *_ in glyphs)
    wt = ' font-weight="%d"' % weight if weight else ""
    return ('  <!-- %s -->\n  <g id="live-text-reference" style="display:none">\n'
            '    <text class="live" x="%s" y="%s" font-size="%s"%s>%s</text>\n  </g>') % (note, xs, f(base), f(size), wt, txt)


# ---------------------------------------------------------------- concept 1
def stele():
    """Carved stele. Forum (Roman inscriptional capitals). Both A's are
    replaced by a mirrored V (crossbarless, like early inscriptions), so the
    word reads as a run of alternating points: K I V I V Λ L Λ. Incised rules
    above and below, the lower one broken under the centre. Triangular
    interpuncts close each end."""
    face = Face("Forum-Regular.ttf", "Forum")
    size, base = 200.0, 260.0
    letters = "PACTFALL"
    pairs = {"PA": -0.07, "AC": -0.01, "CT": -0.01, "TF": 0.0, "FA": -0.07, "AL": -0.01, "LL": 0.02}
    glyphs, right = set_word(face, letters, size, base, 0.10, pairs, flips=(1, 5), x0=120)
    x0, y0, x1, y1 = ink_bounds(face, glyphs, size, base)
    pad_x = 52
    rule_h = 6
    top_y = y0 - 34
    bot_y = y1 + 28
    L, R = x0 - pad_x, x1 + pad_x
    mid = (x0 + x1) / 2
    gap = 46
    rules = [rect(L, top_y, R - L, rule_h), rect(L, bot_y, mid - gap / 2 - L, rule_h), rect(mid + gap / 2, bot_y, R - mid - gap / 2, rule_h)]
    cy = base - size * face.cap / face.upm / 2
    t = 20
    puncts = [tri(L - 14 - t, cy - t * 0.62, L - 14, cy, L - 14 - t, cy + t * 0.62),
              tri(R + 14 + t, cy - t * 0.62, R + 14, cy, R + 14 + t, cy + t * 0.62)]
    # chisel mark in the gap of the broken rule
    chip = [lozenge(mid, bot_y + rule_h / 2, 14, 14)]
    T = top_y - 44
    W, H = (R + 14 + t) + 40, bot_y + rule_h + 44 - T
    shift = -(L - 14 - t - 40)
    layers = [("letters", "ink", [d for _, _, d, _, _ in glyphs]),
              ("ornament", "accent", rules + puncts + chip)]
    # translate everything so the art starts at the left padding
    W = W + shift
    master_extra = live_layer(face, glyphs, size, base, "Live text: A is drawn as a mirrored V in the letters layer; live text keeps a plain A", None)
    wrap_layers = [(lid, cls, ds) for lid, cls, ds in layers]
    emit_t("stele", W, H, wrap_layers, face, master_extra, (shift, -T),
                 "Concept 1, Carved stele. Forum capitals with custom spacing, crossbarless A from a mirrored V, incised rules with a broken lower rule, triangular interpuncts.")
    return glyphs


def emit_t(concept, w, h, layers, face, master_extra, shift, desc):
    clean = [(lid, cls, [d.replace('<SHIFT>', '') for d in ds]) for lid, cls, ds in layers]
    global svg_doc
    base_doc = svg_doc

    def doc(w_, h_, body, title, desc_, style=""):
        return base_doc(w_, h_, '  <g transform="translate(%s %s)">\n%s\n  </g>' % (f(shift[0]), f(shift[1]), body), title, desc_, style)
    svg_doc = doc
    try:
        emit(concept, w, h, clean, face, master_extra, desc)
    finally:
        svg_doc = base_doc


# ---------------------------------------------------------------- concept 2
def seal(file="Marcellus-Regular.ttf", family="Marcellus", concept="seal", flips=(), pairs=None, size=96.0):
    """Broken seal. A double ring cut open at one point (the broken oath)
    around a stone: a lozenge built from the name's own letters, a mirrored
    V over a V. Marcellus capitals below, widely spaced. The seal works alone
    as the small mark."""
    face = Face(file, family)
    s_cap = face.cap / face.upm
    # seal
    cx, cy = 0.0, 0.0
    R1o, R1i = 150, 136
    R2o, R2i = 124, 119
    gap_a0, gap_a1 = 28, 44  # the break, a little past one o'clock
    bands = [arc_band(cx, cy, R1o, R1i, gap_a1, gap_a0 + 360), arc_band(cx, cy, R2o, R2i, gap_a1, gap_a0 + 360)]
    # stone: mirrored V on top, V below, points meeting. Always cut from
    # Marcellus, whose heavier V keeps the stone solid at icon sizes.
    sf = Face("Marcellus-Regular.ttf", "Marcellus") if face.family != "Marcellus" else face
    vs = 150.0
    vb = sf.bounds("V")
    sv = vs / sf.upm
    vw = (vb[2] - vb[0]) * sv
    vh = sf.cap * sv
    vx = cx - vw / 2 - vb[0] * sv
    # mirrored V occupies [base - cap, base]; put its base just above centre so its point is up
    top = [sf.path("V", vx, cy - 3, vs, flip=True)]
    bottom = [sf.path("V", vx, cy + 3 + vh, vs)]
    # wordmark
    letters = "PACTFALL"
    pairs = pairs or {"PA": -0.06, "TF": 0.0, "FA": -0.05, "LL": 0.02}
    glyphs, right = set_word(face, letters, size, 0, 0.30, pairs, flips=flips)
    wx0, wy0, wx1, wy1 = ink_bounds(face, glyphs, size, 0)
    ww = wx1 - wx0
    base = R1o + 70 + size * s_cap
    glyphs, right = set_word(face, letters, size, base, 0.30, pairs, flips=flips, x0=cx - ww / 2 - wx0)
    x0, y0, x1, y1 = ink_bounds(face, glyphs, size, base)
    # small lozenges either side of the word
    lz = [lozenge(x0 - 46, base - size * s_cap / 2, 16, 22), lozenge(x1 + 46, base - size * s_cap / 2, 16, 22)]
    L = min(x0 - 46 - 8, -R1o) - 40
    Rr = max(x1 + 46 + 8, R1o) + 40
    T = -R1o - 40
    B = y1 + 40
    W, H = Rr - L, B - T
    layers = [("seal-ring", "accent", bands),
              ("seal-stone", "ink", top + bottom),
              ("letters", "ink", [d for _, _, d, _, _ in glyphs]),
              ("ornament", "accent", lz)]
    extra = live_layer(face, glyphs, size, base, "Live text reference for the wordmark", None)
    global svg_doc
    base_doc = svg_doc

    def doc(w_, h_, body, title, desc_, style=""):
        return base_doc(w_, h_, '  <g transform="translate(%s %s)">\n%s\n  </g>' % (f(-L), f(-T), body), title, desc_, style)
    svg_doc = doc
    try:
        emit(concept, W, H, layers, face, extra,
             "Concept 2, Broken seal. Double ring broken at one point around a lozenge stone made of a mirrored V over a V; Marcellus capitals, wide spacing.")
        # standalone seal mark for small sizes
        mL, mT = -R1o - 12, -R1o - 12
        mW = 2 * (R1o + 12)
        svg_doc = lambda w_, h_, body, title, desc_, style="": base_doc(w_, h_, '  <g transform="translate(%s %s)">\n%s\n  </g>' % (f(-mL), f(-mT), body), title, desc_, style)
        emit(concept + "-mark" if concept != "seal" else "seal-mark", mW, mW, layers[:2], face, "",
             "Concept 2 standalone mark: the broken seal and stone, for icons and small sizes.")
    finally:
        svg_doc = base_doc


# ---------------------------------------------------------------- concept 3
def knot_d(cx, cy, a, r, wbar):
    """Hannunvaakuna (the looped square, U+2318 shape), an old Finnish and
    Nordic protective folk sign, built as filled geometry: four bars and
    four rings tangent to them, unioned with nonzero fill."""
    hw = wbar / 2
    c = a + r
    e = c  # bars run out to the ring centres' outer tangent
    ds = []
    # vertical bars at x = +-a, horizontal at y = +-a
    for sx in (-1, 1):
        ds.append(rect(cx + sx * a - hw, cy - e, wbar, 2 * e))
    for sy in (-1, 1):
        ds.append(rect(cx - e, cy + sy * a - hw, 2 * e, wbar))
    for sx in (-1, 1):
        for sy in (-1, 1):
            ds.append(ring(cx + sx * c, cy + sy * c, r + hw, r - hw))
    return ds


def manuscript(letters="Pactfall", concept="manuscript", point=True):
    """Manuscript colophon. Cormorant Garamond SemiBold in mixed case with
    tightened, even spacing; the tittles of both i's become lozenges; a hair
    rule below ends in lozenges with a hannunvaakuna knot at its centre."""
    face = Face("CormorantGaramond[wght].ttf", "Cormorant Garamond", wght=600)
    size, base = 240.0, 230.0
    s = size / face.upm
    pairs = {"Pa": -0.02, "ac": 0.0, "ct": -0.01, "tf": 0.10, "tF": 0.04, "fa": -0.015, "Fa": -0.03, "al": 0.0, "ll": 0.0}
    glyphs, right = set_word(face, letters, size, base, 0.015, pairs, x0=0)
    x0, y0, x1, y1 = ink_bounds(face, glyphs, size, base)
    # tittle position from the real i
    tb = face.top_contour_bounds("i")
    tcx_off = (tb[0] + tb[2]) / 2 * s
    tcy = base - (tb[1] + tb[3]) / 2 * s
    tsz = (tb[3] - tb[1]) * s
    tittles = []
    # a raised lozenge in the gap between "Pact" and "fall", like a manuscript word point
    t_end = glyphs[3][1] + face.bounds("t")[2] * s
    f_start = glyphs[4][1] + face.bounds(letters[4])[0] * s
    if point:
        tittles.append(lozenge((t_end + f_start) / 2, base - face.xh * s * 0.55, tsz * 0.8, tsz * 1.15))
    y_top = min(y0, tcy - tsz)
    # colophon rule
    ry = y1 + 56
    rh = 4.0
    k_a, k_r, k_w = 13.0, 9.0, 4.0
    kext = k_a + 2 * k_r + k_w
    midx = (x0 + x1) / 2
    gap = kext + 18
    rule = [rect(x0 + 30, ry - rh / 2, midx - gap - x0 - 30, rh), rect(midx + gap, ry - rh / 2, x1 - 30 - midx - gap, rh),
            lozenge(x0 + 18, ry, 16, 16), lozenge(x1 - 18, ry, 16, 16)]
    knot = knot_d(midx, ry, k_a, k_r, k_w)
    L, T = x0 - 40, y_top - 40
    W, H = (x1 + 40) - L, (ry + kext + 40) - T
    layers = [("letters", "ink", [d for _, _, d, _, _ in glyphs]),
              ("word-point", "accent", tittles),
              ("ornament", "accent", rule + knot)]
    extra = live_layer(face, glyphs, size, base, "Live text reference (the word point lozenge is in its own layer)", 600)
    global svg_doc
    base_doc = svg_doc
    svg_doc = lambda w_, h_, body, title, desc_, style="": base_doc(w_, h_, '  <g transform="translate(%s %s)">\n%s\n  </g>' % (f(-L), f(-T), body), title, desc_, style)
    try:
        emit(concept, W, H, [l for l in layers if l[2]], face, extra,
             "Concept 3, Manuscript colophon. Cormorant Garamond SemiBold, custom spacing, a lozenge word point between Pact and fall, hair rule with a hannunvaakuna knot.")
    finally:
        svg_doc = base_doc


if __name__ == "__main__":
    stele()
    seal()
    # 2b: the broken seal with the carved stele lettering (Anthony's pick)
    seal("Forum-Regular.ttf", "Forum", "seal-forum", flips=(1, 5),
         pairs={"PA": -0.07, "AC": -0.01, "FA": -0.07, "LL": 0.02}, size=104.0)
    manuscript()
    manuscript("PactFall", "manuscript-camel", point=False)
    print("done")
