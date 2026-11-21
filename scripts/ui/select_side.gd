class_name SelectSide
extends RefCounted
## One player's half of the character-select screen: the big fighter art (cropped and enlarged like the stills, with a drop
## shadow, a quick slide-in swap and a faded ghost of the previous art) and the name block: school crest and school, the name
## in Barlow with BA's white to pale-blue headline gradient, then CLUB, STRIKER TYPE and EASE OF USE as navy tags on white
## value plates (a row without data is left out). P2 is the mirror image, right-aligned, the lean is not mirrored.
## The screen adds `art_layer` below the roster tiles and `text_layer` above them, and calls `process(delta)`.

const ART_SHADER := preload("res://shaders/select_art.gdshader")
const GRADIENT_SHADER := preload("res://shaders/name_gradient.gdshader")
const Menu := preload("res://scripts/ui/ba_menu.gd")

const X_LEFT := 31.0
const X_RIGHT := 1250.0
const MAX_W := 340.0
const SCHOOL_Y := 452.0
const SCHOOL_SIZE := 14
const NAME_TOP := 494.0
const NAME_SIZE := 76
const ROWS_Y := 570.0
const ROW_PITCH := 36.0
const TAG_H := 22.0
const PLATE_H := 30.0
const INK_RATE := 8.0               # the silhouette goes dark or comes back in about 0.12 s, never in one frame
const ROW_LABELS := ["CLUB", "STRIKER TYPE", "EASE OF USE"]

var slot := 1
var art_layer: Control
var text_layer: Control
var fighter_id := -2

var _cur: TextureRect
var _ghost: TextureRect
var _cur_mat: ShaderMaterial
var _ghost_mat: ShaderMaterial
var _cur_frame := {}
var _ghost_frame := {}
var _name: Label
var _block: Control
var _crest: Texture2D
var _crest_size := Vector2.ZERO
var _school := ""
var _rows: Array = []
var _started := false
var _in := 0.0
var _swap_t := 1.0
var _ghost_t := 1.0
var _blur := 0.0
var _blur_to := 0.0
var _flash := 0.0
var _random_block := false       # the text block shows "?"'s RANDOM card, not fighter_id's stats
var _ink := 0.0                  # 0 = full colour, 1 = dark silhouette (the "?" random tile), eased toward _ink_to
var _ink_to := 0.0
var _ghost_ink := 0.0            # the ink the ghost's art was showing when it was swapped out
var _text_pop := 1.0

func setup(player_slot: int) -> SelectSide:
	slot = player_slot
	art_layer = Control.new()
	art_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_layer = Control.new()
	text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost = _rect()
	_cur = _rect()
	_ghost_mat = _ghost.material
	_cur_mat = _cur.material
	art_layer.add_child(_ghost)
	art_layer.add_child(_cur)
	_name = Label.new()
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if _right() else HORIZONTAL_ALIGNMENT_LEFT
	_name.add_theme_font_override("font", UI.font_name())
	_name.add_theme_font_size_override("font_size", NAME_SIZE)
	_name.add_theme_color_override("font_color", Color.WHITE)
	_name.add_theme_color_override("font_outline_color", BaTokens.HEAD_OUTLINE)
	_name.add_theme_constant_override("outline_size", 9)
	_name.size = Vector2(MAX_W + 40.0, NAME_SIZE * 1.3)
	_name.position = Vector2((X_RIGHT - _name.size.x) if _right() else X_LEFT, NAME_TOP - NAME_SIZE * 0.3)
	var gm := ShaderMaterial.new()
	gm.shader = GRADIENT_SHADER
	gm.set_shader_parameter("y_top", NAME_SIZE * 0.3 + 8.0)
	gm.set_shader_parameter("y_bottom", NAME_SIZE * 1.0 + 4.0)
	_name.material = gm
	text_layer.add_child(_name)
	_block = Control.new()
	_block.size = Vector2(1280.0, 720.0)
	_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block.draw.connect(_draw_block)
	text_layer.add_child(_block)
	return self

func _right() -> bool:
	return slot == 2

func _rect() -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	var m := ShaderMaterial.new()
	m.shader = ART_SHADER
	r.material = m
	return r

## Begin the entrance (art slides in from the outer edge, text follows).
func start() -> void:
	_started = true
	_in = 0.0

## Show fighter `id` (a roster id); `random` shows the "?" tile's mystery card instead.
func show_fighter(id: int) -> void:
	if id == fighter_id:
		if _random_block:     # leaving "?" onto the fighter its silhouette shows: the art is right, the text is not
			_fighter_block(Game.by_id[id])
		return
	var tex := UI.portrait(id)
	if tex == null:
		return
	var s: Dictionary = Game.by_id[id]
	if fighter_id != -2 and _cur.texture != null:
		_ghost.texture = _cur.texture
		_ghost_frame = _cur_frame
		_ghost_t = 0.0
		_ghost_ink = _ink
	fighter_id = id
	_cur.texture = tex
	_cur_frame = SelectFrames.frame(id, tex, slot)
	_swap_t = 0.0 if _started and _in > 0.4 else 1.0
	_fighter_block(s)

func _fighter_block(s: Dictionary) -> void:
	_random_block = false
	_set_block(String(s["schoolName"]).to_upper(), String(s["school"]), Fighters.display_name(s).to_upper(),
			[String(s.get("clubName", "")), Fighters.striker_type(s), Fighters.ease_of_use(s)])
	_text_pop = 0.0

## The random tile: a dark silhouette of `id`'s art, no stats.
func show_random(id: int) -> void:
	var cycling := _ink_to > 0.0
	if id != fighter_id:
		if cycling:
			fighter_id = -2
		show_fighter(id)
		if cycling:
			_swap_t = 1.0     # one dark silhouette for the next: no fade through the pale plate
	_set_block("ANY SCHOOL", "", "RANDOM", [])
	_random_block = true
	_ink_to = 1.0

func clear_random() -> void:
	_ink_to = 0.0

func _set_block(school: String, school_key: String, nm: String, values: Array) -> void:
	_school = school
	_crest = CrestIcon.get_icon(school_key) if school_key != "" else null
	_crest_size = CrestIcon.fit(school_key) if school_key != "" else Vector2.ZERO
	_name.text = nm
	var size := NAME_SIZE
	var f := UI.font_name()
	while size > 40 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > MAX_W:
		size -= 2
	_name.add_theme_font_size_override("font_size", size)
	_rows = []
	for i in values.size():
		if String(values[i]).strip_edges() != "":
			_rows.append([ROW_LABELS[i], String(values[i])])
	_block.queue_redraw()

## Where everything in the block sits, for the draw and the tests: {school: Rect2 (the plate), crest: Rect2, name: Rect2,
## rows: [{tag, plate, tag_text, value, value_size, value_w}]}.
func layout() -> Dictionary:
	var out := {"rows": []}
	var sw := Menu.text_width(_school, SCHOOL_SIZE, 800)
	var crest_w := (_crest_size.x + 8.0) if _crest != null else 0.0
	var plate_w := 28.0 + crest_w + sw
	var plate_x := X_RIGHT - plate_w if _right() else X_LEFT
	out["school"] = Rect2(plate_x, SCHOOL_Y, plate_w, PLATE_H)
	var crest_x := plate_x + plate_w - 14.0 - _crest_size.x if _right() else plate_x + 14.0
	out["crest"] = Rect2(crest_x, SCHOOL_Y + (PLATE_H - 10.0 - _crest_size.y) * 0.5, _crest_size.x, _crest_size.y)
	out["school_text"] = (plate_x + plate_w - 14.0 - crest_w) if _right() else (plate_x + 14.0 + crest_w)
	var f := UI.font_name()
	var size: int = _name.get_theme_font_size("font_size")
	var nw := f.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	out["name"] = Rect2((X_RIGHT - nw) if _right() else X_LEFT, NAME_TOP, nw, size * 0.7)
	for i in _rows.size():
		var y := ROWS_Y + ROW_PITCH * float(i)
		var tag_w := Menu.text_width(_rows[i][0], 12, 800) + 26.0
		var vsize := Menu.fit(_rows[i][1], 16, MAX_W - tag_w - 30.0, 12, 800)
		var vw := Menu.text_width(_rows[i][1], vsize, 800)
		var pw := vw + 34.0
		var tag: Rect2
		var plate: Rect2
		if _right():
			tag = Rect2(X_RIGHT - tag_w, y, tag_w, TAG_H)
			plate = Rect2(tag.position.x + 10.0 - pw, y + 1.0, pw, PLATE_H)
		else:
			tag = Rect2(X_LEFT, y, tag_w, TAG_H)
			plate = Rect2(tag.end.x - 10.0, y + 1.0, pw, PLATE_H)
		out["rows"].append({"tag": tag, "plate": plate, "tag_text": _rows[i][0], "value": _rows[i][1], "value_size": vsize, "value_w": vw})
	return out

func _draw_block() -> void:
	var l := layout()
	var sp: Rect2 = l["school"]
	BaArt.nine(_block, "Common__Common_Nonoutline_W_Bg", sp, Color.WHITE, BaTokens.SHEAR)
	if _crest != null:
		_block.draw_texture_rect(_crest, l["crest"], false, BaTokens.INK)
	var sx: float = l["school_text"]
	_block.draw_string(UI.font_ui(800), Vector2(sx - (Menu.text_width(_school, SCHOOL_SIZE, 800) if _right() else 0.0), sp.position.y + 17.5), _school, HORIZONTAL_ALIGNMENT_LEFT, -1, SCHOOL_SIZE, BaTokens.INK)
	for r in l["rows"]:
		var plate: Rect2 = r["plate"]
		var tag: Rect2 = r["tag"]
		BaArt.nine(_block, "Common__Common_Nonoutline_W_Bg", plate, Color.WHITE, BaTokens.SHEAR)
		var vx := plate.end.x - 17.0 if _right() else plate.position.x + 17.0
		Menu.label(_block, r["value"], Vector2(vx, plate.position.y + 17.0), int(r["value_size"]), BaTokens.INK, Color(0, 0, 0, 0), 0, 2 if _right() else 0, 800)
		Menu.ribbon(_block, tag, r["tag_text"])

## Blur + dim this side (a Special panel is open over it). 0..1
func set_covered(amount: float) -> void:
	_blur_to = amount

func flash() -> void:
	_flash = 1.0

func process(delta: float) -> void:
	if _started:
		_in += delta
	var outward := -1.0 if slot == 1 else 1.0
	var e := Motion.whip(_in, 0.117, 0.35) if _started else 0.0
	var a_in := clampf(_in * 5.0, 0.0, 1.0) if _started else 0.0
	_swap_t = minf(_swap_t + delta, 1.0)
	_ghost_t = minf(_ghost_t + delta, 1.0)
	_blur = lerpf(_blur, _blur_to, 1.0 - exp(-delta * 9.0))
	_flash = move_toward(_flash, 0.0, delta * 2.4)
	_ink = move_toward(_ink, _ink_to, delta * INK_RATE)
	_text_pop = minf(_text_pop + delta / 0.28, 1.0)
	var se := 1.0 - pow(1.0 - clampf(_swap_t / 0.26, 0.0, 1.0), 3.0)
	var slide := outward * (1.0 - e) * 460.0
	if _cur.texture:
		var f: Dictionary = _cur_frame
		_cur.size = f["size"]
		_cur.position = (f["pos"] as Vector2) + Vector2(slide + outward * (1.0 - se) * 38.0, 0.0)
		_cur.modulate.a = a_in * se
		var sc: float = f["scale"]
		_cur_mat.set_shader_parameter("blur_px", _blur * 13.0 / sc)
		_cur_mat.set_shader_parameter("shadow_px", 11.0 / sc)
		_cur_mat.set_shader_parameter("shadow_off", Vector2(5.0, 9.0) / sc)
		_cur_mat.set_shader_parameter("wash", _flash * 0.5 + _blur * 0.22)
		_cur_mat.set_shader_parameter("dim", lerpf(1.0, 0.04, _ink) - _blur * 0.12)
		_cur_mat.set_shader_parameter("saturation", lerpf(1.0, 0.4, _blur) * lerpf(1.0, 0.0, _ink))
	if _ghost.texture:
		var g: Dictionary = _ghost_frame
		var gt := clampf(_ghost_t / 0.45, 0.0, 1.0)
		_ghost.size = g["size"]
		_ghost.position = (g["pos"] as Vector2) + Vector2(slide - outward * gt * 30.0, 0.0)
		var solid := FxFlash.reduced() or _ghost_ink > 0.0 or _ink_to > 0.0   # a silhouette on either side, or Reduce Flashes: no dip or whitening between the two arts
		_ghost.modulate.a = a_in * (1.0 if solid else 0.55) * pow(1.0 - gt, 1.6)
		_ghost_mat.set_shader_parameter("wash", 0.0 if solid else 0.35)
		var gs: float = g["scale"]
		_ghost_mat.set_shader_parameter("blur_px", _blur * 13.0 / gs)
		_ghost_mat.set_shader_parameter("shadow_amt", 0.0)
		_ghost_mat.set_shader_parameter("dim", lerpf(1.0, 0.04, _ghost_ink))
		_ghost_mat.set_shader_parameter("saturation", lerpf(1.0, 0.0, _ghost_ink))
	var te := Motion.whip(maxf(_in - 0.12, 0.0), 0.117, 0.3) if _started else 0.0
	var pop := Motion.whip(_text_pop * 0.28, 0.08, 0.2)
	text_layer.position = Vector2(outward * (1.0 - te) * 240.0 + outward * (1.0 - pop) * 16.0, 0.0)
	text_layer.modulate.a = clampf((_in - 0.1) * 6.0, 0.0, 1.0) * lerpf(0.55 + 0.45 * pop, 0.0, _blur)
