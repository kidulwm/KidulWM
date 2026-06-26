#!/usr/bin/env python3
"""Generate the RKT-dashboard SVG icon pack.

All icons are drawn on a 24x24 viewBox using simple vector shapes and a fixed
soft company palette.  They are exported at 24, 32, 48 and 64 logical pixels.
"""
from pathlib import Path
import re

OUT = Path("/home/dad/dev/KidulWM/rkt-dashboard/assets/icons")
PALETTE = {
    "purple": "#7C3AED",
    "blue": "#2563EB",
    "turquoise": "#06B6D4",
    "lavender": "#A78BFA",
    "deep_indigo": "#1E1B4B",
    "ice": "#E0F2FE",
    "pearl": "#F1F5F9",
    "white": "#F8FAFC",
    "orange": "#F97316",
    "ink": "#0F172A",
}
P = PALETTE


def wrap(name, elements, width, height, fill_opacity="1.0"):
    body = "\n".join(f"  {e}" for e in elements)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" '
        f'width="{width}" height="{height}" viewBox="0 0 24 24" aria-labelledby="{name}Title" role="img">\n'
        f'  <title id="{name}Title">{name}</title>\n'
        f"{body}\n"
        "</svg>\n"
    )


# ---------------------------------------------------------------------------
# Shared primitives
# ---------------------------------------------------------------------------
def bob_head(x=12, y=13.5, scale=1.0):
    """White-hat hacker Bob head with fedora + round glasses."""
    s = scale
    def tx(xx, yy):
        return (x + (xx - 12) * s, y + (yy - 13.5) * s)
    def pt(xx, yy):
        px, py = tx(xx, yy)
        return f"{px:.2f},{py:.2f}"
    return [
        # hat brim
        f'<path d="M {pt(5,10.5)} A {7*s:.2f},{2.2*s:.2f} 0 0 1 {pt(19,10.5)} V {tx(19,11.5)[1]:.2f} '
        f'A {7*s:.2f},{2.2*s:.2f} 0 0 1 {pt(5,11.5)} Z" fill="{P["white"]}"/>',
        # hat crown
        f'<path d="M {pt(7.5,10.5)} L {pt(9,6.5)} H {tx(15,6.5)[0]:.2f} L {pt(16.5,10.5)} Z" fill="{P["white"]}"/>',
        # hat band
        f'<rect x="{tx(7.7,10.0)[0]:.2f}" y="{tx(7.7,10.0)[1]:.2f}" width="{8.6*s:.2f}" height="{1.1*s:.2f}" '
        f'rx="{0.2*s:.2f}" fill="{P["purple"]}"/>',
        # face
        f'<circle cx="{tx(12,14.5)[0]:.2f}" cy="{tx(12,14.5)[1]:.2f}" r="{4.2*s:.2f}" fill="{P["pearl"]}"/>',
        # glasses lenses
        f'<circle cx="{tx(10.3,14.8)[0]:.2f}" cy="{tx(10.3,14.8)[1]:.2f}" r="{1.25*s:.2f}" fill="{P["ink"]}"/>',
        f'<circle cx="{tx(13.7,14.8)[0]:.2f}" cy="{tx(13.7,14.8)[1]:.2f}" r="{1.25*s:.2f}" fill="{P["ink"]}"/>',
        # bridge
        f'<line x1="{tx(11.55,14.8)[0]:.2f}" y1="{tx(11.55,14.8)[1]:.2f}" x2="{tx(12.45,14.8)[0]:.2f}" '
        f'y2="{tx(12.45,14.8)[1]:.2f}" stroke="{P["ink"]}" stroke-width="{0.5*s:.2f}" stroke-linecap="round"/>',
        # friendly smile
        f'<path d="M {pt(10.5,16.3)} Q {pt(12,17.3)} {pt(13.5,16.3)}" fill="none" stroke="{P["ink"]}" '
        f'stroke-width="{0.55*s:.2f}" stroke-linecap="round"/>',
    ]


def cloud(x=12, y=13, w=10, h=6, fill=P["blue"], opacity=1.0):
    # A simple cloud made of two rounded bumps plus a flat bottom.
    rx, ry = w / 2, h / 2
    left_bump = rx * 0.55
    right_bump = rx * 0.65
    return [
        f'<path d="M {x-left_bump},{y} '
        f'A {left_bump},{ry} 0 0 1 {x},{y-ry} '
        f'h {w-left_bump-right_bump:.2f} '
        f'A {right_bump},{ry} 0 0 1 {x+right_bump},{y} '
        f'A {ry*0.55},{ry*0.55} 0 0 1 {x+right_bump-ry*0.55},{y+ry*0.55} '
        f'h {-w+ry:.2f} '
        f'A {ry*0.55},{ry*0.55} 0 0 1 {x-left_bump},{y} z" '
        f'fill="{fill}" fill-opacity="{opacity}" stroke="white" stroke-width="0.8" stroke-linejoin="round"/>'
    ]


def sun_disc(cx=16, cy=9, r=3, opacity=1.0):
    rays = []
    import math
    for a in range(0, 360, 45):
        rad = math.radians(a)
        x1 = cx + (r + 1.0) * math.cos(rad)
        y1 = cy + (r + 1.0) * math.sin(rad)
        x2 = cx + (r + 2.2) * math.cos(rad)
        y2 = cy + (r + 2.2) * math.sin(rad)
        rays.append(
            f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" '
            f'stroke="white" stroke-width="0.9" stroke-linecap="round"/>'
        )
    return [f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{P["orange"]}" fill-opacity="{opacity}" stroke="white" stroke-width="0.8"/>'] + rays


# ---------------------------------------------------------------------------
# Icon definitions: each returns a list of SVG element strings
# ---------------------------------------------------------------------------
GLOW_FILL_OPACITY = 0.30


def icon_sunny():
    return sun_disc(12, 12, 4, opacity=GLOW_FILL_OPACITY)


def icon_cloudy():
    return cloud(12, 13, 11, 6.5, P["purple"], opacity=GLOW_FILL_OPACITY)


def icon_partly_cloudy():
    return sun_disc(16, 9, 2.6, opacity=GLOW_FILL_OPACITY) + cloud(11, 14.5, 11, 6, P["blue"], opacity=GLOW_FILL_OPACITY)


def icon_rain():
    return cloud(12, 12, 11, 6, P["blue"], opacity=GLOW_FILL_OPACITY) + [
        '<line x1="9" y1="16.5" x2="7.5" y2="20.5" stroke="white" stroke-width="1.0" stroke-linecap="round"/>',
        '<line x1="12" y1="16.5" x2="10.5" y2="20.5" stroke="white" stroke-width="1.0" stroke-linecap="round"/>',
        '<line x1="15" y1="16.5" x2="13.5" y2="20.5" stroke="white" stroke-width="1.0" stroke-linecap="round"/>',
    ]


def icon_thunderstorm():
    return cloud(12, 12, 11, 6, P["deep_indigo"], opacity=GLOW_FILL_OPACITY) + [
        f'<path d="M13.5,15.5 L10.5,20.5 H13 L12,23.5 L16.5,17.5 H13.5 Z" fill="{P["orange"]}" stroke="white" stroke-width="0.6"/>'
    ]


def icon_snow():
    flakes = []
    for cx in (8.5, 12, 15.5):
        flakes.append(
            f'<g transform="translate({cx}, 18.5) scale(0.55)">'
            '<path d="M0,-3 V3 M-2.6,-1.5 L2.6,1.5 M-2.6,1.5 L2.6,-1.5" stroke="white" stroke-width="1.1" stroke-linecap="round"/>'
            '</g>'
        )
    return cloud(12, 12, 11, 6, P["lavender"], opacity=GLOW_FILL_OPACITY) + flakes


def icon_fog():
    return [
        '<path d="M4,8 Q8,6 12,8 T20,8" fill="none" stroke="white" stroke-width="1.3" stroke-linecap="round"/>',
        '<path d="M4,12 Q8,10 12,12 T20,12" fill="none" stroke="white" stroke-width="1.3" stroke-linecap="round"/>',
        '<path d="M4,16 Q8,14 12,16 T20,16" fill="none" stroke="white" stroke-width="1.3" stroke-linecap="round"/>',
    ]


def icon_bob():
    return bob_head()


def icon_security_bob():
    return [
        '<path d="M12,4 L20,7 V13 Q20,18 12,21 Q4,18 4,13 V7 Z" fill="#2563EB"/>',
        '<path d="M12,6 L18,8.5 V13 Q18,16.5 12,19 Q6,16.5 6,13 V8.5 Z" fill="#1E1B4B"/>',
    ] + bob_head(12, 13, 0.72)


def icon_media_bob():
    return bob_head(9.5, 13.5, 0.85) + [
        '<path d="M15.5,9 V19 L21.5,14 Z" fill="#06B6D4"/>'
    ]


def icon_artist_bob():
    return bob_head(9, 13.5, 0.8) + [
        '<ellipse cx="17.5" cy="16.5" rx="3.2" ry="2.6" fill="#F97316"/>',
        '<circle cx="16.2" cy="15.5" r="0.6" fill="#06B6D4"/>',
        '<circle cx="18.2" cy="15.2" r="0.6" fill="#7C3AED"/>',
        '<circle cx="17.5" cy="17.6" r="0.6" fill="#2563EB"/>',
        '<line x1="20" y1="12" x2="18" y2="18" stroke="#F1F5F9" stroke-width="1.4" stroke-linecap="round"/>',
    ]


def icon_coder_bob():
    return bob_head(9.5, 13.5, 0.82) + [
        '<polyline points="14,9 12,12.5 14,16" fill="none" stroke="#06B6D4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
        '<polyline points="20,9 22,12.5 20,16" fill="none" stroke="#06B6D4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
        '<line x1="17.5" y1="8" x2="15.5" y2="17" stroke="#7C3AED" stroke-width="1.5" stroke-linecap="round"/>',
    ]


def icon_admin_bob():
    return bob_head(9, 13.5, 0.78) + [
        '<path d="M17.5,8 C15.5,8 15.5,11 17.5,11 V20 H19.5 V11 C21.5,11 21.5,8 19.5,8 Z" fill="#F97316"/>'
    ]


def icon_search_bob():
    return bob_head(9, 13.5, 0.78) + [
        '<circle cx="17.5" cy="16" r="3" fill="none" stroke="#06B6D4" stroke-width="1.6"/>',
        '<line x1="19.6" y1="18.1" x2="22" y2="20.5" stroke="#06B6D4" stroke-width="1.6" stroke-linecap="round"/>',
    ]


def icon_chat_bob():
    return bob_head(9, 13.5, 0.78) + [
        '<path d="M15.5,9 H21 A1,1 0 0 1 22,10 V16 A1,1 0 0 1 21,17 H18 L15.5,20 V17 H15.5 A1,1 0 0 1 14.5,16 V10 A1,1 0 0 1 15.5,9 Z" fill="#7C3AED"/>',
        '<circle cx="17.5" cy="13" r="0.7" fill="#F1F5F9"/>',
        '<circle cx="19" cy="13" r="0.7" fill="#F1F5F9"/>',
        '<circle cx="20.5" cy="13" r="0.7" fill="#F1F5F9"/>',
    ]


def icon_cloud_bob():
    return bob_head(9.5, 14, 0.72) + cloud(17, 11, 7, 4.5, P["turquoise"])


def icon_logo():
    # stylised trident / RKT mark
    return [
        '<path d="M12,2 V7 M12,9 V22" stroke="#7C3AED" stroke-width="2.4" stroke-linecap="round"/>',
        '<path d="M12,7 L6.5,4 V9 L12,7 L17.5,4 V9 L12,7 Z" fill="#06B6D4"/>',
        '<circle cx="12" cy="7" r="1.6" fill="#F8FAFC"/>',
    ]


def icon_dashboard():
    r = 1.2
    return [
        f'<rect x="4" y="4" width="7" height="7" rx="{r}" fill="#7C3AED"/>',
        f'<rect x="13" y="4" width="7" height="7" rx="{r}" fill="#2563EB"/>',
        f'<rect x="4" y="13" width="7" height="7" rx="{r}" fill="#06B6D4"/>',
        f'<rect x="13" y="13" width="7" height="7" rx="{r}" fill="#A78BFA"/>',
    ]


def icon_settings():
    return [
        '<path d="M12,7 A5,5 0 1 0 12,17 A5,5 0 1 0 12,7 Z" fill="none" stroke="#2563EB" stroke-width="1.8"/>',
        '<path d="M12,2 L12,5 M12,19 L12,22 M2,12 L5,12 M19,12 L22,12 M4.7,4.7 L6.8,6.8 M17.2,17.2 L19.3,19.3 M4.7,19.3 L6.8,17.2 M17.2,6.8 L19.3,4.7" stroke="#A78BFA" stroke-width="1.6" stroke-linecap="round"/>',
        '<circle cx="12" cy="12" r="2" fill="#06B6D4"/>',
    ]


def icon_lock():
    return [
        '<rect x="6" y="11" width="12" height="9" rx="1.5" fill="#7C3AED"/>',
        '<path d="M8,11 V8 A4,4 0 0 1 16,8 V11" fill="none" stroke="#A78BFA" stroke-width="2" stroke-linecap="round"/>',
        '<circle cx="12" cy="15.5" r="1.2" fill="#F1F5F9"/>',
        '<line x1="12" y1="16.7" x2="12" y2="18.2" stroke="#F1F5F9" stroke-width="1.4" stroke-linecap="round"/>',
    ]


def icon_menu():
    return [
        '<line x1="4" y1="7" x2="20" y2="7" stroke="#F1F5F9" stroke-width="2" stroke-linecap="round"/>',
        '<line x1="4" y1="12" x2="20" y2="12" stroke="#F1F5F9" stroke-width="2" stroke-linecap="round"/>',
        '<line x1="4" y1="17" x2="20" y2="17" stroke="#F1F5F9" stroke-width="2" stroke-linecap="round"/>',
    ]


def icon_close():
    return [
        '<line x1="6" y1="6" x2="18" y2="18" stroke="#F97316" stroke-width="2.2" stroke-linecap="round"/>',
        '<line x1="18" y1="6" x2="6" y2="18" stroke="#F97316" stroke-width="2.2" stroke-linecap="round"/>',
    ]


def icon_user():
    return [
        '<circle cx="12" cy="8" r="3.5" fill="#A78BFA"/>',
        '<path d="M5,19 A7,7 0 0 1 19,19" fill="none" stroke="#2563EB" stroke-width="2.2" stroke-linecap="round"/>',
    ]


# ---------------------------------------------------------------------------
# Build everything
# ---------------------------------------------------------------------------
ICONS = [
    ("weather-sunny", icon_sunny),
    ("weather-cloudy", icon_cloudy),
    ("weather-partly-cloudy", icon_partly_cloudy),
    ("weather-rain", icon_rain),
    ("weather-thunderstorm", icon_thunderstorm),
    ("weather-snow", icon_snow),
    ("weather-fog", icon_fog),
    ("bob", icon_bob),
    ("security-bob", icon_security_bob),
    ("media-bob", icon_media_bob),
    ("artist-bob", icon_artist_bob),
    ("coder-bob", icon_coder_bob),
    ("admin-bob", icon_admin_bob),
    ("search-bob", icon_search_bob),
    ("chat-bob", icon_chat_bob),
    ("cloud-bob", icon_cloud_bob),
    ("logo", icon_logo),
    ("dashboard", icon_dashboard),
    ("settings", icon_settings),
    ("lock", icon_lock),
    ("menu", icon_menu),
    ("close", icon_close),
    ("user", icon_user),
]


def make_weather_variants():
    """For each root weather SVG, create a fill-only and stroke-only variant."""
    for path in OUT.glob("rkt-icon-weather-*.svg"):
        if path.name.endswith(("-fill.svg", "-stroke.svg")):
            continue
        text = path.read_text(encoding="utf-8")

        # Fill variant: remove all stroke attributes, keep translucent fills.
        fill_text = re.sub(r'\s+stroke-linejoin="[^"]*"', "", text)
        fill_text = re.sub(r'\s+stroke-linecap="[^"]*"', "", fill_text)
        fill_text = re.sub(r'\s+stroke-width="[^"]*"', "", fill_text)
        fill_text = re.sub(r'\s+stroke="[^"]*"', "", fill_text)
        fill_text = fill_text.replace("</svg>", "<style>path,circle,line,polyline,rect{stroke:none}</style></svg>")
        (OUT / f"{path.stem}-fill.svg").write_text(fill_text, encoding="utf-8")

        # Stroke variant: remove fills, keep white outlines.
        stroke_text = re.sub(r'\s+fill-opacity="[^"]*"', "", text)
        stroke_text = re.sub(r'\s+fill="[^"]*"', ' fill="none"', stroke_text)
        stroke_text = stroke_text.replace("</svg>", "<style>path,circle,polyline,rect{fill:none}</style></svg>")
        (OUT / f"{path.stem}-stroke.svg").write_text(stroke_text, encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sizes = [24, 32, 48, 64]
    for size in sizes:
        (OUT / str(size)).mkdir(exist_ok=True)

    # Remove stale weather variants so they get rewritten cleanly.
    for p in OUT.glob("rkt-icon-weather-*-fill.svg"):
        p.unlink()
    for p in OUT.glob("rkt-icon-weather-*-stroke.svg"):
        p.unlink()

    written = []
    for name, fn in ICONS:
        elements = fn()
        for size in sizes:
            svg = wrap(name, elements, size, size)
            path = OUT / str(size) / f"rkt-icon-{name}.svg"
            path.write_text(svg, encoding="utf-8")
            written.append(path)
        # also write a default 24px copy at root
        root_path = OUT / f"rkt-icon-{name}.svg"
        root_path.write_text(wrap(name, elements, 24, 24), encoding="utf-8")
        written.append(root_path)

    make_weather_variants()
    print(f"Wrote {len(written)} SVGs to {OUT}")


if __name__ == "__main__":
    main()
