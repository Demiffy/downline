# The game's mark (docs/images/mark.svg): two amber chevrons going down over the hazard stripe. Here
# as SVG text (no asset files), the glow drawn as soft wide strokes under a crisp one (Godot's SVG
# renderer blurs a filtered line without keeping it sharp). The window's and the dock's icon.
extends RefCounted

const SVG := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <radialGradient id="vig" cx="50%" cy="46%" r="72%">
      <stop offset="0%" stop-color="#1e1813"/><stop offset="65%" stop-color="#0e0c0b"/><stop offset="100%" stop-color="#050404"/>
    </radialGradient>
    <clipPath id="tile"><rect width="256" height="256" rx="44"/></clipPath>
  </defs>
  <g clip-path="url(#tile)">
    <rect width="256" height="256" fill="url(#vig)"/>
    <g fill="#d4a12a" opacity="0.9">
      <polygon points="-14,232 -1,232 -13,256 -26,256"/><polygon points="12,232 25,232 13,256 0,256"/>
      <polygon points="38,232 51,232 39,256 26,256"/><polygon points="64,232 77,232 65,256 52,256"/>
      <polygon points="90,232 103,232 91,256 78,256"/><polygon points="116,232 129,232 117,256 104,256"/>
      <polygon points="142,232 155,232 143,256 130,256"/><polygon points="168,232 181,232 169,256 156,256"/>
      <polygon points="194,232 207,232 195,256 182,256"/><polygon points="220,232 233,232 221,256 208,256"/>
      <polygon points="246,232 259,232 247,256 234,256"/>
    </g>
    <g fill="none" stroke="#fda951" stroke-linecap="round" stroke-linejoin="round">
      <g opacity="0.035" stroke-width="46"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g opacity="0.040" stroke-width="40"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g opacity="0.050" stroke-width="34"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g opacity="0.060" stroke-width="29"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g opacity="0.075" stroke-width="25"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g opacity="0.090" stroke-width="21"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g opacity="0.120" stroke-width="18"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g stroke-width="14"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.55"/></g>
      <g stroke="#ffd29a" stroke-width="5" opacity="0.8"><polyline points="54,58 128,124 202,58"/><polyline points="54,128 128,194 202,128" opacity="0.5"/></g>
    </g>
  </g>
</svg>"""


static func image(size := 256) -> Image:
	var img := Image.new()
	img.load_svg_from_string(SVG, size / 256.0)
	return img


## The mark as a Mac app icon: Apple's grid puts the tile in the middle 824 of 1024, a margin all round
## (a full-bleed one stands bigger than every other app in the dock).
static func mac_image(size := 1024) -> Image:
	var inner := int(round(size * 824.0 / 1024.0))
	var tile := image(inner)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	tile.convert(Image.FORMAT_RGBA8)
	img.blit_rect(tile, Rect2i(0, 0, inner, inner), Vector2i((size - inner) / 2, (size - inner) / 2))
	return img


## Sets the window's (and on a Mac, the dock's) icon.
static func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.set_icon(mac_image(512) if OS.get_name() == "macOS" else image(256))
