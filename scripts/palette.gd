class_name Palette
extends RefCounted
## Colour AND surface for every block in the arena.
##
## Target: **Burg** — Krunker's signature map, a walled sand-stone village that
## is a de_dust2 remake. Hex family from reference/krunker-look.md plus direct
## sampling of reference/bar/krunker_burg_overview_01.webp: cream limestone
## (#CFBB93), terracotta roof tile (#C4552F), dark timber framing (#4A3423),
## warm sand ground (#B9A176), muted olive foliage (#5F7A3A).
##
## The single biggest gap against the bar was not hue, it was TEXTURE. Krunker
## blocks are not flat colour: walls show brick coursing, roofs show tile rows,
## floors show planks. We cannot ship image files, so every texture here is
## synthesised into an Image at boot. They are deliberately tiny and sampled
## NEAREST — the chunky texel grid is part of the look, not a compromise.

const TEX_SIZE := 32

enum Surf { BRICK, BLOCK, TILE, PLANK, PANEL, GRAIN, ROUGH, FLAT, LEAF, PANE, FLAG }

## key -> [base colour, surface kind, pattern contrast]
const SPEC := {
	# Burg's floor carries as much colour identity as its walls: warm tan
	# flagstones with visible joints, not the cool near-uniform noise this had.
	"road":     [Color8(188, 166, 128), Surf.FLAG, 0.26],
	"kerb":     [Color8(208, 191, 158), Surf.BLOCK, 0.24],
	"wall_a":   [Color8(198, 189, 170), Surf.BRICK, 0.24],
	"wall_b":   [Color8(182, 171, 152), Surf.BRICK, 0.26],
	"wall_c":   [Color8(160, 150, 133), Surf.BLOCK, 0.28],
	"roof":     [Color8(196, 85, 47), Surf.TILE, 0.22],
	"roof_alt": [Color8(122, 106, 94), Surf.TILE, 0.20],
	"wood":     [Color8(107, 74, 47), Surf.PLANK, 0.20],
	"crate":    [Color8(156, 111, 60), Surf.GRAIN, 0.22],
	"metal":    [Color8(138, 131, 120), Surf.PANEL, 0.17],
	"accent":   [Color8(179, 58, 43), Surf.FLAT, 0.06],
	"grass":    [Color8(95, 122, 58), Surf.LEAF, 0.20],
	"dirt":     [Color8(146, 124, 96), Surf.ROUGH, 0.20],
	"glass":    [Color8(53, 64, 74), Surf.PANE, 0.30],
	"dark":     [Color8(58, 44, 32), Surf.PLANK, 0.16],
	"light":    [Color8(230, 220, 196), Surf.BLOCK, 0.10],
}

const SKY_TOP := Color8(152, 187, 210)   # paler and warmer: Burg's sky is hazy, not vivid
const SKY_HORIZON := Color8(240, 231, 206)
const SUN_COLOR := Color8(255, 244, 214)
const FOG_COLOR := Color8(226, 214, 186)

static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}

static func get_color(key: String) -> Color:
	if SPEC.has(key):
		return SPEC[key][0]
	return Color8(255, 0, 255)

static func material(key: String) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE          # the tint is baked into the texture
	m.albedo_texture = texture(key)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.04
	m.uv1_scale = Vector3.ONE             # map_builder emits world-scaled UVs
	if key == "glass":
		m.metallic_specular = 0.4
		m.roughness = 0.25
	_mat_cache[key] = m
	return m

static func texture(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var spec: Array = SPEC.get(key, [Color8(255, 0, 255), Surf.FLAT, 0.0])
	var tex := ImageTexture.create_from_image(_bake(spec[0], spec[1], spec[2], key))
	_tex_cache[key] = tex
	return tex

# ------------------------------------------------------------------ synthesis
## Builds one tile. `contrast` is how far the pattern pushes brightness either
## side of the base colour; keep it low or the blocks stop reading as one
## material at distance.
static func _bake(base: Color, kind: int, contrast: float, key: String) -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)                  # stable across runs, so shots compare
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			img.set_pixel(x, y, base * (1.0 + _value(x, y, kind, rng) * contrast))
	return img

## Returns roughly -1..1 describing how much lighter or darker this texel is.
static func _value(x: int, y: int, kind: int, rng: RandomNumberGenerator) -> float:
	var n: float = rng.randf() * 2.0 - 1.0
	match kind:
		Surf.BRICK:
			# 4 courses per unit, alternate rows offset by half a brick
			var row: int = y / 8
			var off: int = 0 if row % 2 == 0 else 8
			var joint: bool = (y % 8 == 0) or ((x + off) % 16 == 0)
			return -2.2 if joint else 0.25 * n + (0.12 if row % 2 == 0 else -0.06)
		Surf.BLOCK:
			# big ashlar blocks, 2 per unit
			var j: bool = (y % 16 == 0) or (x % 16 == 0)
			return -1.8 if j else 0.3 * n
		Surf.TILE:
			# overlapping roof tile rows: bright lip, shaded body
			var ly: int = y % 8
			if ly == 0:
				return -2.0
			if ly == 1:
				return 1.4
			return -0.25 - 0.06 * float(ly) + 0.2 * n
		Surf.PLANK:
			var pj: bool = y % 8 == 0
			if pj:
				return -1.9
			return 0.5 * n + (0.15 if (y / 8) % 2 == 0 else -0.1)
		Surf.PANEL:
			var edge: bool = (x % 16 == 0) or (y % 16 == 0)
			var rivet: bool = (x % 16 == 3 or x % 16 == 13) and (y % 16 == 3 or y % 16 == 13)
			if rivet:
				return 1.3
			return -1.5 if edge else 0.25 * n
		Surf.GRAIN:
			# crate: plank body with a border frame
			var border: bool = x < 2 or y < 2 or x >= TEX_SIZE - 2 or y >= TEX_SIZE - 2
			if border:
				return -1.4
			return (0.6 * n) + (0.35 if (y / 4) % 2 == 0 else -0.2)
		Surf.LEAF:
			# clumpy foliage rather than uniform noise
			var c: float = sin(float(x) * 1.7) * cos(float(y) * 1.3)
			return c * 0.9 + 0.5 * n
		Surf.PANE:
			# window: dark glass with a bright reflected streak
			var streak: bool = absi((x - y) % 32) < 3
			return 1.6 if streak else -0.4 + 0.2 * n
		Surf.FLAG:
			# irregular flagstones: a coarse grid whose rows shift, so it never
			# reads as graph paper the way a plain lattice does
			var row: int = y / 11
			var shift: int = (row * 5) % 11
			var jx: bool = ((x + shift) % 11) == 0
			var jy: bool = (y % 11) == 0
			if jx or jy:
				return -1.7
			var cell: float = float(((x + shift) / 11 + row * 3) % 5) / 5.0
			return (cell - 0.5) * 0.9 + 0.55 * n
		Surf.ROUGH:
			return 0.8 * n
		_:
			return 0.25 * n
