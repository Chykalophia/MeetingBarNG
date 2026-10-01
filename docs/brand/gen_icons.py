#!/usr/bin/env python3
"""Generate Punctual app-icon concepts (A-D), menu-bar glyphs, and a contact sheet.

Palette: Chykalophia (CKLPH) tokens from
~/.claude/skills/cklph-diagram/references/brands/cklph.md
"""
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))

# --- CKLPH tokens -----------------------------------------------------------
NAVY = "#1f3658"       # primary-500 / ink-2 / cat-1
NAVY_DEEP = "#12243f"  # primary-800
NAVY_INK = "#09182f"   # seq-6
TEAL = "#1e465a"       # primary-400 / link
TEAL_MID = "#2f6a80"   # seq-3 dark
TEAL_SOFT = "#4f8296"  # seq-4
TEAL_PALE = "#8fbcc9"  # seq-3
TEAL_MIST = "#bcdce2"  # seq-2
CRIMSON = "#ab132a"    # coral-500 / accent
CRIMSON_DEEP = "#850e21"  # cat-4
CORAL = "#dd7e80"      # coral-300
CORAL_MID = "#c4636e"  # div-neg-1
GOLD = "#f5b35a"       # cat-2 dark
OCHRE = "#92511a"      # cat-2 light
CREAM = "#fafaf7"      # paper
PARCHMENT = "#f2ead2"  # div-mid


def squircle(cx=512, cy=512, half=412, n=5.0, steps=720):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + half * math.copysign(abs(c) ** (2 / n), c)
        y = cy + half * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.2f},{y:.2f}")
    return "M" + " L".join(pts) + " Z"


SQ = squircle()


def chrome(body_grad_stops, inner, extra_defs=""):
    """Wrap icon artwork in the Big Sur body: shadow, squircle body, rim light."""
    stops = "".join(
        f'<stop offset="{o}" stop-color="{c}"/>' for o, c in body_grad_stops
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <path id="sq" d="{SQ}"/>
    <clipPath id="clip"><use href="#sq"/></clipPath>
    <linearGradient id="body" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">{stops}</linearGradient>
    <linearGradient id="rim" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.32"/>
      <stop offset="0.25" stop-color="#ffffff" stop-opacity="0.06"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.18"/>
    </linearGradient>
    <radialGradient id="sheen" cx="512" cy="140" r="620" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <filter id="drop" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="14"/>
      <feOffset dy="12"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.30"/></feComponentTransfer>
      <feMerge><feMergeNode/></feMerge>
    </filter>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="10"/>
      <feOffset dy="10"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.28"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="tight" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="4"/>
      <feOffset dy="4"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.30"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    {extra_defs}
  </defs>
  <use href="#sq" filter="url(#drop)"/>
  <use href="#sq" fill="url(#body)"/>
  <g clip-path="url(#clip)">
    <use href="#sq" fill="url(#sheen)"/>
{inner}
  </g>
  <use href="#sq" fill="none" stroke="url(#rim)" stroke-width="3"/>
</svg>
'''


# --- Concept A: "On the dot" clock -----------------------------------------
def concept_a():
    cx, cy, r = 512, 512, 296
    ticks = []
    for i in range(12):
        if i == 0:
            continue  # 12 o'clock is where the dot lives
        a = math.radians(i * 30)
        major = i % 3 == 0
        r1, r2 = (r - 62, r - 30) if major else (r - 50, r - 32)
        x1, y1 = cx + r1 * math.sin(a), cy - r1 * math.cos(a)
        x2, y2 = cx + r2 * math.sin(a), cy - r2 * math.cos(a)
        ticks.append(
            f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{NAVY}" stroke-opacity="{0.55 if major else 0.28}" '
            f'stroke-width="{16 if major else 10}" stroke-linecap="round"/>'
        )
    defs = f'''
    <radialGradient id="face" cx="512" cy="420" r="380" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{CREAM}"/>
      <stop offset="1" stop-color="{PARCHMENT}"/>
    </radialGradient>
    <radialGradient id="dotA" cx="0.38" cy="0.32" r="0.75">
      <stop offset="0" stop-color="#d4283f"/>
      <stop offset="1" stop-color="{CRIMSON_DEEP}"/>
    </radialGradient>'''
    dot_y = cy - r + 70
    inner = f'''
    <g filter="url(#soft)">
      <circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#face)"/>
    </g>
    <circle cx="{cx}" cy="{cy}" r="{r - 6}" fill="none" stroke="{NAVY}" stroke-opacity="0.08" stroke-width="6"/>
    {"".join(ticks)}
    <g filter="url(#tight)">
      <line x1="{cx}" y1="{cy}" x2="{cx}" y2="{dot_y + 92}" stroke="{NAVY}" stroke-width="40" stroke-linecap="round"/>
      <line x1="{cx}" y1="{cy}" x2="{cx + 124}" y2="{cy - 72}" stroke="{NAVY}" stroke-width="40" stroke-linecap="round"/>
      <circle cx="{cx}" cy="{cy}" r="34" fill="{NAVY}"/>
      <circle cx="{cx}" cy="{dot_y}" r="44" fill="url(#dotA)"/>
    </g>
    <circle cx="{cx}" cy="{cy}" r="12" fill="{CREAM}" fill-opacity="0.9"/>'''
    return chrome([(0, "#2b4a74"), (0.55, NAVY), (1, NAVY_DEEP)], inner, defs)


def menubar_a():
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <circle cx="9" cy="9" r="7.25" fill="none" stroke="#000" stroke-width="1.5"/>
  <path d="M9 9 V6.8 M9 9 L11.3 7.7" fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round"/>
  <circle cx="9" cy="4.3" r="1.35" fill="#000"/>
</svg>
'''


# --- Concept B: calendar tile, one bold dot --------------------------------
def concept_b():
    cols, rows = 5, 3
    x0, y0, gx, gy = 272, 522, 120, 116
    today = (3, 1)
    dots = []
    for rr in range(rows):
        for cc in range(cols):
            x, y = x0 + cc * gx, y0 + rr * gy
            if (cc, rr) == today:
                continue
            past = rr * cols + cc < today[1] * cols + today[0]
            dots.append(
                f'<circle cx="{x}" cy="{y}" r="19" fill="{TEAL_SOFT if past else TEAL_PALE}" '
                f'fill-opacity="{0.45 if past else 0.75}"/>'
            )
    tx, ty = x0 + today[0] * gx, y0 + today[1] * gy
    defs = f'''
    <linearGradient id="band" x1="0" y1="100" x2="0" y2="360" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2b4a74"/>
      <stop offset="1" stop-color="{NAVY}"/>
    </linearGradient>
    <radialGradient id="dotB" cx="0.38" cy="0.32" r="0.75">
      <stop offset="0" stop-color="#d4283f"/>
      <stop offset="1" stop-color="{CRIMSON_DEEP}"/>
    </radialGradient>'''
    inner = f'''
    <rect x="0" y="0" width="1024" height="352" fill="url(#band)"/>
    <rect x="0" y="352" width="1024" height="10" fill="#000" fill-opacity="0.10"/>
    {"".join(dots)}
    <g filter="url(#soft)">
      <circle cx="{tx}" cy="{ty}" r="62" fill="url(#dotB)"/>
    </g>'''
    return chrome([(0, CREAM), (1, PARCHMENT)], inner, defs)


def menubar_b():
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <rect x="2.25" y="3.25" width="13.5" height="12" rx="2.6" fill="none" stroke="#000" stroke-width="1.5"/>
  <path d="M2.25 7.1 H15.75 M6 1.6 V4.4 M12 1.6 V4.4" stroke="#000" stroke-width="1.5" stroke-linecap="round"/>
  <circle cx="11.3" cy="11.3" r="2" fill="#000"/>
</svg>
'''


# --- Concept C: bell whose clapper is the dot -------------------------------
BELL = ("M512 262 C402 262 334 342 334 462 L334 584 C334 628 306 656 268 690 "
        "L756 690 C718 656 690 628 690 584 L690 462 C690 342 622 262 512 262 Z")


def concept_c():
    defs = f'''
    <linearGradient id="bell" x1="0" y1="240" x2="0" y2="720" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{CREAM}"/>
      <stop offset="1" stop-color="{PARCHMENT}"/>
    </linearGradient>
    <linearGradient id="bellShade" x1="334" y1="0" x2="690" y2="0" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#000" stop-opacity="0"/>
      <stop offset="0.6" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="{OCHRE}" stop-opacity="0.16"/>
    </linearGradient>
    <radialGradient id="dotC" cx="0.38" cy="0.32" r="0.75">
      <stop offset="0" stop-color="#d4283f"/>
      <stop offset="1" stop-color="{CRIMSON_DEEP}"/>
    </radialGradient>'''
    inner = f'''
    <g transform="rotate(-10 512 300)">
      <g filter="url(#soft)">
        <circle cx="512" cy="246" r="30" fill="url(#bell)"/>
        <path d="{BELL}" fill="url(#bell)"/>
        <rect x="252" y="676" width="520" height="40" rx="20" fill="url(#bell)"/>
      </g>
      <path d="{BELL}" fill="url(#bellShade)"/>
    </g>
    <g filter="url(#soft)">
      <circle cx="556" cy="790" r="56" fill="url(#dotC)"/>
    </g>
    <g fill="none" stroke="{CREAM}" stroke-opacity="0.55" stroke-width="22" stroke-linecap="round">
      <path d="M232 330 A300 300 0 0 0 214 470"/>
      <path d="M792 300 A300 300 0 0 1 822 430"/>
    </g>'''
    return chrome([(0, "#3b7f97"), (0.5, TEAL_MID), (1, TEAL)], inner, defs)


def menubar_c():
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <path d="M9 2.4 C6.4 2.4 4.9 4.3 4.9 6.9 V9.6 C4.9 10.8 4.2 11.6 3.1 12.6 H14.9 C13.8 11.6 13.1 10.8 13.1 9.6 V6.9 C13.1 4.3 11.6 2.4 9 2.4 Z"
        fill="none" stroke="#000" stroke-width="1.5" stroke-linejoin="round"/>
  <circle cx="9" cy="15.3" r="1.7" fill="#000"/>
</svg>
'''


# --- Concept D: "P" made of a timeline stem + progress arc + now-dot --------
def concept_d():
    sx = 392          # stem x
    top, bot = 262, 772
    bcx, bcy, br = 548, 418, 156   # bowl circle
    # bowl arc: from stem top, across, round the right side, back toward stem
    end_angle = math.radians(184)  # measured clockwise from 12 o'clock
    ex = bcx + br * math.sin(end_angle)
    ey = bcy - br * math.cos(end_angle)
    defs = f'''
    <linearGradient id="arc" x1="392" y1="262" x2="620" y2="574" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{CREAM}"/>
      <stop offset="1" stop-color="{PARCHMENT}"/>
    </linearGradient>
    <radialGradient id="dotD" cx="0.38" cy="0.32" r="0.75">
      <stop offset="0" stop-color="#ffd28a"/>
      <stop offset="1" stop-color="#e09a3c"/>
    </radialGradient>'''
    sw = 78
    inner = f'''
    <g filter="url(#soft)">
      <path d="M{sx} {bot} V{top + 0} " fill="none" stroke="url(#arc)" stroke-width="{sw}" stroke-linecap="round"/>
      <path d="M{sx} {bcy - br} H{bcx} A{br} {br} 0 1 1 {ex:.1f} {ey:.1f}" fill="none" stroke="url(#arc)" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>
    </g>
    <g filter="url(#soft)">
      <circle cx="{sx + 150}" cy="{bot - 2}" r="48" fill="url(#dotD)"/>
    </g>'''
    return chrome([(0, "#c22036"), (0.55, CRIMSON), (1, CRIMSON_DEEP)], inner, defs)


def menubar_d():
    # P: stem + bowl arc (open), plus dot at baseline
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <path d="M5.2 16 V2.6 H9.6 A3.75 3.75 0 1 1 8.3 9.85" fill="none" stroke="#000" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="10.6" cy="14.9" r="1.6" fill="#000"/>
</svg>
'''


CONCEPTS = {
    "a": (concept_a, menubar_a, "On the dot"),
    "b": (concept_b, menubar_b, "Today, dotted"),
    "c": (concept_c, menubar_c, "Bell + clapper dot"),
    "d": (concept_d, menubar_d, "Timeline P"),
}


def contact_sheet():
    # Layout: two panels (light, dark), each with 4 rows.
    W, rowh, top = 1400, 300, 90
    H = top + rowh * 4 + 40
    panel_w = W // 2
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}" viewBox="0 0 {W} {H}">']
    for p, (bg, fg, sub, name) in enumerate([("#f5f5f7", "#1d1d1f", "#6e6e73", "Light"), ("#1e1e20", "#f5f5f7", "#a1a1a6", "Dark")]):
        ox = p * panel_w
        parts.append(f'<rect x="{ox}" y="0" width="{panel_w}" height="{H}" fill="{bg}"/>')
        parts.append(f'<text x="{ox + 32}" y="52" font-family="Helvetica Neue, Helvetica, Arial" font-size="26" font-weight="600" fill="{fg}">{name} backgrounds</text>')
        parts.append(f'<text x="{ox + 300}" y="52" font-family="Helvetica Neue, Helvetica, Arial" font-size="15" fill="{sub}">256 · 32 · 16 (1:1 and 4x) · menu bar 18 (1:1 and 3x)</text>')
        # menu bar strip colour (macOS light/dark menu bar)
        mbg = "#e9e9eb" if p == 0 else "#2c2c2e"
        for i, k in enumerate("abcd"):
            y = top + i * rowh
            label = CONCEPTS[k][2]
            parts.append(f'<text x="{ox + 32}" y="{y + 20}" font-family="Helvetica Neue, Helvetica, Arial" font-size="16" font-weight="600" fill="{fg}">{k.upper()} · {label}</text>')
            parts.append(f'<image x="{ox + 24}" y="{y + 30}" width="256" height="256" xlink:href="concept-{k}-256.png"/>')
            parts.append(f'<image x="{ox + 300}" y="{y + 130}" width="32" height="32" xlink:href="concept-{k}-32.png"/>')
            parts.append(f'<image x="{ox + 352}" y="{y + 138}" width="16" height="16" xlink:href="concept-{k}-16.png"/>')
            parts.append(f'<image x="{ox + 388}" y="{y + 114}" width="64" height="64" image-rendering="optimizeSpeed" style="image-rendering:pixelated" xlink:href="concept-{k}-16.png"/>')
            # menu bar
            parts.append(f'<rect x="{ox + 470}" y="{y + 122}" width="210" height="48" rx="8" fill="{mbg}"/>')
            mb = f"concept-{k}-menubar-18{'-w' if p else ''}.png"
            mb3 = f"concept-{k}-menubar-54{'-w' if p else ''}.png"
            parts.append(f'<image x="{ox + 484}" y="{y + 137}" width="18" height="18" xlink:href="{mb}"/>')
            parts.append(f'<text x="{ox + 508}" y="{y + 151}" font-family="Helvetica Neue, Helvetica, Arial" font-size="13" fill="{fg}">in 5 min</text>')
            parts.append(f'<image x="{ox + 600}" y="{y + 119}" width="54" height="54" xlink:href="{mb3}"/>')
    parts.append("</svg>")
    return "\n".join(parts)


def main():
    for k, (icon, mb, _) in CONCEPTS.items():
        with open(os.path.join(OUT, f"concept-{k}.svg"), "w") as f:
            f.write(icon())
        with open(os.path.join(OUT, f"concept-{k}-menubar.svg"), "w") as f:
            f.write(mb())
        # white variant for dark preview only (not a deliverable)
        with open(os.path.join(OUT, f"_concept-{k}-menubar-w.svg"), "w") as f:
            f.write(mb().replace("#000", "#fff"))
    with open(os.path.join(OUT, "contact-sheet.svg"), "w") as f:
        f.write(contact_sheet())


if __name__ == "__main__":
    main()
