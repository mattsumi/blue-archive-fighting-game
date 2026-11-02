extends SceneTree
## The VS screen and the character select. The flow contracts (what the fight and the other screens read, timings, input
## gating, who may move which cursor) and the geometry of the redrawn pieces.
## Run: TEST=res://scripts/ui/tests/vs_select_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

class StubTransition extends Node:
	var styles: Array = []
	var cover_all := false
	func play(style: String, _opts: Dictionary, on_cover: Callable) -> void:
		if style != "cut":
			styles.append(style)
		if style == "cut" or cover_all:
			on_cover.call()

const DT := 1.0 / 60.0

var checks := 0
var failures: Array = []
var game: Node
var stub: StubTransition
var real_transition: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("VS_SELECT_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("VS_SELECT_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	real_transition = game.transition
	stub = StubTransition.new()
	root.add_child(stub)
	game.transition = stub
	await _vs_flow()
	await _vs_beat()
	_vs_fit()
	await _select_flow()
	await _select_roster()
	await _select_pixels()
	await _vs_portraits()
	_new_picks()
	await _select_seed()
	await _select_poll()
	await _select_cover()
	_select_random_art()
	_select_random_name()
	await _select_crest_entrance()
	check(BaArt.warnings().is_empty(), "no art name was missing or unknown (%s)" % str(BaArt.warnings()))
	game.transition = real_transition
	print("VS_SELECT_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# helpers
func _session(mode: String, f1: Variant, f2: Variant, sp1: Variant = -1, sp2: Variant = -1) -> void:
	var s = game.session
	s.begin(mode)
	for i in 2:
		s.players[i]["claimed"] = true
		s.players[i]["device"] = "kb1" if i == 0 else "kb2"
	s.players[0]["fighter"] = f1
	s.players[1]["fighter"] = f2
	s.players[0]["special"] = sp1
	s.players[1]["special"] = sp2

func _open(screen_name: String, params := {}) -> Node:
	stub.styles.clear()
	await game.go(screen_name, params, "cut")
	var scr: Node = game.current()
	scr.set_process(false)
	return scr

func _tick(scr: Node, frames: int) -> void:
	for i in frames:
		scr._process(DT)

func _tick_to(scr: Node, secs: float) -> void:
	while float(scr.probe()["t"]) < secs - 0.0001:
		scr._process(DT)

func _viewport(bg: Color, sz := Vector2i(1280, 720)) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = sz
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var r := ColorRect.new()
	r.color = bg
	r.size = Vector2(sz)
	vp.add_child(r)
	return vp

func _px(img: Image, x: float, y: float) -> Color:
	return img.get_pixel(clampi(int(x), 0, img.get_width() - 1), clampi(int(y), 0, img.get_height() - 1))

func _sfx(name: String) -> int:
	return int(root.get_node("Sfx").played.get(name, 0))

# VS screen: the flow the fight depends on
func _vs_flow() -> void:
	game.session.stage = {}
	_session("versus2p", 10004, 10005, 10017, 10040)
	game.session.stage = load("res://scripts/core/stages.gd").LIST[0]
	var whoosh0 := _sfx("whoosh")
	var slam0 := _sfx("slam")
	var fight0 := _sfx("fight")
	var scr: Node = await _open("vs", {"hold": true})
	var p: Dictionary = scr.probe()
	check(p["fighters"] == [10004, 10005] and p["specials"] == [10017, 10040], "vs reads the picked fighters and specials")
	check(not p["handed_off"] and not p["end_hold"] and not p.has("caption"), "vs holds nothing yet and has no READY? or FIGHT! caption")
	check(_sfx("whoosh") == whoosh0 + 1, "vs opens with one whoosh")
	check(p["match_config"]["stage"]["id"] == "gehenna-night" and p["match_config"]["p1"]["fighter"] == 10004, "match_config carries stage and fighters")

	_tick_to(scr, 1.75)
	check(not scr.probe()["handed_off"], "no handoff before 1.8 s")
	check(_sfx("slam") - slam0 == 3 and _sfx("fight") - fight0 == 0, "a slam for each fighter and one for VS, and no fight sound")
	_tick_to(scr, 1.85)
	p = scr.probe()
	check(p["handed_off"] and p["end_hold"], "hold: stops at the end state at 1.8 s")
	_tick_to(scr, 3.0)
	check(_sfx("slam") - slam0 == 3 and _sfx("fight") - fight0 == 0, "nothing more is played after the VS lettering")
	check(stub.styles.is_empty(), "hold never starts a transition")

	scr = await _open("vs", {})
	_tick_to(scr, 1.75)
	check(stub.styles.is_empty() and not scr.probe()["handed_off"], "live run: nothing before 1.8 s")
	_tick_to(scr, 1.85)
	check(scr.probe()["handed_off"] and stub.styles == ["slam"], "live run hands off to the fight with the slam wipe")

	scr = await _open("vs", {})
	scr.on_action("kb1", "confirm")
	check(not scr.probe()["handed_off"], "confirm before 0.2 s is ignored")
	scr.on_action("kb1", "back")
	check(stub.styles.is_empty(), "back before 0.2 s is ignored")
	_tick_to(scr, 0.3)
	scr.on_action("kb1", "confirm")
	check(scr.probe()["handed_off"] and stub.styles == ["slam"], "confirm after 0.2 s skips ahead to the fight")
	scr.on_action("kb2", "start")
	check(stub.styles.size() == 1, "a second confirm does not hand off twice")

	scr = await _open("vs", {})
	_tick_to(scr, 0.3)
	scr.on_action("kb1", "back")
	await process_frame
	check(stub.styles == ["fade"], "back leaves with the fade")

	scr = await _open("vs", {"hold": true})
	_tick_to(scr, 0.3)
	check(not _vs_settled(scr), "setup: nothing has landed at 0.3 s")
	scr.on_action("kb1", "start")
	_tick(scr, 2)
	p = scr.probe()
	check(p["handed_off"] and p["end_hold"] and _vs_settled(scr), "hold: skip jumps to the settled end state")

	scr = await _open("vs", {"hold": true})
	_tick_to(scr, 1.0)
	check(scr._strip.position.y > 1.0 and not _vs_settled(scr), "the stage strip is the last to land: still moving at 1.0 s")
	_tick_to(scr, 1.3)
	check(_vs_settled(scr), "everything has landed by 1.3 s, with half a second to read it before the handoff")

	await _vs_resolve()

## Every piece of the screen is at rest: fighters, plates, name plates, specials, the stage strip, the band, the VS lettering.
func _vs_settled(scr: Node) -> bool:
	var ok: bool = scr.probe()["band"] >= 0.999 and absf(scr._vs.scale.x - 1.0) < 0.004 and scr._vs.modulate.a == 1.0
	ok = ok and absf(scr._strip.position.y) < 0.5 and scr._strip.modulate.a == 1.0
	for i in 2:
		var home: Vector2 = scr._holders[i].get_meta("home")
		ok = ok and scr._holders[i].position.distance_to(home) < 0.5 and scr._holders[i].modulate.a == 1.0
		ok = ok and absf(scr._plates[i].position.x - (scr.PORTRAIT_CX[i] - scr.PLATE_SIZE.x * 0.5)) < 0.5
		ok = ok and absf(scr._blocks[i].position.x) < 0.5 and scr._blocks[i].modulate.a == 1.0
		ok = ok and absf(scr._specs[i].position.x) < 0.5 and scr._specs[i].modulate.a == 1.0
		ok = ok and absf(scr._decos[i].position.x - scr.DECO_X[i]) < 0.5 and absf(scr._decos[i].scale.y - 1.0) < 0.004
	return ok

func _vs_resolve() -> void:
	_session("versus-cpu", "random", -1)
	game.session.stage = {}
	var scr: Node = await _open("vs", {"hold": true})
	var p: Dictionary = scr.probe()
	var ids: Array = p["fighters"]
	check(game.by_id.has(ids[0]) and game.by_id.has(ids[1]) and ids[0] != ids[1], "random and empty picks resolve to two different fighters")
	check(game.session.players[0]["fighter"] == ids[0] and game.session.players[1]["fighter"] == ids[1], "the resolved fighters are written back to the session")
	var sp: Array = p["specials"]
	check(game.by_id.has(sp[0]) and sp[0] != ids[0] and sp[1] != ids[1], "specials resolve and never equal their own fighter")
	check(not game.session.stage.is_empty(), "an empty stage is filled from the stage list")
	_session("versus2p", 10004, 10004, 10004, 10004)
	scr = await _open("vs", {"hold": true})
	p = scr.probe()
	check(p["fighters"][0] == 10004 and p["fighters"][1] == 10004, "the same fighter on both sides is kept")
	check(p["specials"][0] != 10004 and p["specials"][1] != 10004, "a special equal to its fighter is re-rolled")

# select: the state machine and the grid
func _grid_model() -> Dictionary:
	var rows: Array = load("res://scripts/core/fighters.gd").build_grid(game.fighters)
	var tiles: Array = []
	var row_idx: Array = []
	for r in rows.size():
		var idxs: Array = []
		for c in rows[r].size():
			var cell: Variant = rows[r][c]
			tiles.append({"id": int(cell["id"]) if cell is Dictionary else -1, "row": r, "col": c,
				"x": 640.0 + (float(c) - float(rows[r].size() - 1) * 0.5) * 91.3})
			idxs.append(tiles.size() - 1)
		row_idx.append(idxs)
	return {"tiles": tiles, "rows": row_idx}

func _model_move(m: Dictionary, i: int, act: String) -> int:
	var tiles: Array = m["tiles"]
	var rows: Array = m["rows"]
	var t: Dictionary = tiles[i]
	if act == "left" or act == "right":
		var row: Array = rows[t["row"]]
		return row[(int(t["col"]) + (1 if act == "right" else -1) + row.size()) % row.size()]
	var nr: int = (int(t["row"]) + (1 if act == "down" else -1) + rows.size()) % rows.size()
	var best: int = i
	var best_d := INF
	for k in rows[nr]:
		var d := absf(float(tiles[k]["x"]) - float(t["x"]))
		if d < best_d:
			best_d = d
			best = k
	return best

func _model_tile(m: Dictionary, id: int) -> int:
	for i in m["tiles"].size():
		if m["tiles"][i]["id"] == id:
			return i
	return -1

## Presses the shortest d-pad path for slot s from tile `from` to tile `to` on the reference grid.
func _walk(scr: Node, m: Dictionary, s: int, from: int, to: int) -> void:
	var queue: Array = [[from, []]]
	var seen := {from: true}
	var path: Array = []
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		if cur[0] == to:
			path = cur[1]
			break
		for act in ["left", "right", "up", "down"]:
			var nx := _model_move(m, cur[0], act)
			if not seen.has(nx):
				seen[nx] = true
				queue.append([nx, cur[1] + [act]])
	for act in path:
		scr.on_action("kb1" if s == 0 else "kb2", act)
		_tick(scr, 3)

func _enter_select(params := {}, reset := true) -> Node:
	if reset:
		_session("versus2p", -1, -1)
	var scr: Node = await _open("select", params)
	var guard := 0
	while not scr.probe()["entered"] and guard < 600:
		scr._process(DT)
		guard += 1
	_tick(scr, 30)
	return scr

func _select_flow() -> void:
	var m := _grid_model()
	check(m["tiles"].size() == 3 and m["tiles"][1]["id"] == -1, "the grid is one row of three with the random tile in the middle")
	_session("versus2p", -1, -1)
	var scr: Node = await _enter_select()
	var p: Dictionary = scr.probe()
	check(p["entered"] and p["state"] == ["pick", "pick"], "both players start picking")
	check(p["cursor"] == [10004, 10005], "cursors start on Hina and Hoshino")
	check(p["players"].size() == 2 and p["panels"].size() == 2 and not p["panels"][0]["open"], "probe keeps players and panels")

	# movement against the reference model
	var at := [_model_tile(m, 10004), _model_tile(m, 10005)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var acts := ["left", "right", "up", "down"]
	var ok := true
	for n in 60:
		var s := rng.randi() % 2
		var act: String = acts[rng.randi() % 4]
		at[s] = _model_move(m, at[s], act)
		scr.on_action("kb1" if s == 0 else "kb2", act)
		_tick(scr, 4)
		var cur: Array = scr.probe()["cursor"]
		if cur[s] != m["tiles"][at[s]]["id"]:
			ok = false
	check(ok, "60 random moves match the grid model (wrap in rows, nearest column between rows)")
	var before: Array = scr.probe()["cursor"]
	scr.on_action("kb3", "right")
	scr.on_action("pad0", "left")
	_tick(scr, 4)
	check(scr.probe()["cursor"] == before, "a device that claimed neither slot moves nothing")

	# same tile
	scr = await _enter_select()
	await _walk(scr, m, 0, _model_tile(m, 10004), _model_tile(m, 10005))
	check(scr.probe()["cursor"][0] == 10005 and scr.probe()["cursor"][1] == 10005, "both cursors can share a tile")
	scr.on_action("kb1", "confirm")
	scr.on_action("kb2", "confirm")
	_tick(scr, 5)
	p = scr.probe()
	check(p["state"] == ["special", "special"] and p["players"][0]["fighter"] == 10005 and p["players"][1]["fighter"] == 10005, "both can lock the same fighter")
	check(not p["players"][0]["locked"], "locked needs the special pick as well")

	# lock, special, locked cursors stay put
	scr = await _enter_select()
	scr.on_action("kb1", "confirm")
	_tick(scr, 5)
	p = scr.probe()
	check(p["state"][0] == "special" and p["state"][1] == "pick" and p["players"][0]["fighter"] == 10004, "confirm locks the fighter and opens the special pick")
	var cur0: int = p["cursor"][0]
	scr.on_action("kb1", "right")
	_tick(scr, 3)
	check(scr.probe()["cursor"][0] == cur0, "a locked cursor does not move with the d-pad")
	_tick(scr, 40)
	var panel0: Node = scr._panels[0]
	panel0.set_process(false)
	check(scr.probe()["panels"][0]["open"], "the special panel opens after the lock")
	panel0._t = 1.0
	var sid: int = scr.probe()["panels"][0]["id"]
	scr.on_action("kb1", "confirm")
	_tick(scr, 3)
	p = scr.probe()
	check(p["state"][0] == "done" and p["players"][0]["special"] == sid and p["players"][0]["locked"], "confirming a special finishes the player")
	scr.on_action("kb1", "back")
	_tick(scr, 3)
	check(scr.probe()["state"][0] == "special", "back from done reopens the special pick")

	# back from the special pick unlocks the fighter
	scr = await _enter_select()
	scr.on_action("kb2", "confirm")
	_tick(scr, 45)
	panel0 = scr._panels[1]
	panel0.set_process(false)
	panel0._t = 1.0
	scr.on_action("kb2", "back")
	_tick(scr, 5)
	p = scr.probe()
	check(p["state"][1] == "pick" and p["players"][1]["fighter"] == -1, "back in the special pick unlocks the fighter")

	# leaving
	scr = await _enter_select()
	stub.styles.clear()
	scr.on_action("kb1", "confirm")
	_tick(scr, 3)
	scr.on_action("kb2", "back")
	_tick(scr, 3)
	check(stub.styles.is_empty(), "back is refused while the other human has locked")
	scr = await _enter_select()
	stub.styles.clear()
	scr.on_action("kb2", "back")
	await process_frame
	check(stub.styles == ["fade"], "back with nothing locked leaves to the menu with the fade")

	await _select_random()
	await _select_cpu()
	await _select_mouse()

func _select_random() -> void:
	var m := _grid_model()
	_session("versus2p", -1, -1)
	var scr: Node = await _enter_select()
	await _walk(scr, m, 0, _model_tile(m, 10004), _model_tile(m, -1))
	check(scr.probe()["cursor"][0] == -1, "P1 reaches the random tile")
	var swapped := 0
	var stale := 0
	for i in 150:
		var was: int = scr._rand_id[0]
		scr._process(DT)
		if scr._rand_id[0] != was:
			swapped += 1
			stale += int(scr._sides[0]._cur.size.distance_to(scr._sides[0]._cur_frame["size"]) > 1.0)
	check(swapped >= 2 and stale == 0, "a silhouette swap draws in its own frame at once (%d swaps, %d stale)" % [swapped, stale])
	scr.on_action("kb1", "confirm")
	_tick(scr, 2)
	check(scr.probe()["state"][0] == "roll", "confirm on the random tile starts the roulette")
	_tick(scr, 200)
	var p: Dictionary = scr.probe()
	check(p["state"][0] == "special" and game.by_id.has(p["players"][0]["fighter"]) and p["cursor"][0] == p["players"][0]["fighter"], "the roulette lands on a real fighter and locks it")

func _select_cpu() -> void:
	_session("versus-cpu", -1, -1)
	game.session.players[1]["claimed"] = false
	var scr: Node = await _enter_select({}, false)
	scr.on_action("kb2", "right")
	_tick(scr, 3)
	check(scr.probe()["cursor"][1] == 10005, "the CPU slot ignores every device")
	scr.on_action("kb1", "confirm")
	_tick(scr, 400)
	var p: Dictionary = scr.probe()
	check(p["state"][1] != "pick" and game.by_id.has(p["players"][1]["fighter"]), "the CPU rolls its fighter after P1 locks")

func _select_mouse() -> void:
	_session("versus2p", -1, -1)
	var scr: Node = await _enter_select()
	var tile: Dictionary = scr._tiles[2]
	scr._on_tile_hover(2)
	_tick(scr, 3)
	check(scr.probe()["cursor"][0] == tile["id"], "hovering a tile moves the P1 cursor")
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	scr._on_tile_input(ev, 0)
	_tick(scr, 3)
	check(scr.probe()["state"][0] == "special" and scr.probe()["players"][0]["fighter"] == scr._tiles[0]["id"], "clicking a tile locks it for P1")

# fixes
## Every portrait file has its own size: the VS art keeps its proportions and every head is drawn the same width on the same spot.
func _vs_portraits() -> void:
	var ui: GDScript = load("res://scripts/ui/ui.gd")
	var ids: Array = []
	for f in game.fighters:
		ids.append(int(f["id"]))
	var bad := []
	var cx: Array = []
	for k in range(0, ids.size(), 2):
		_session("versus2p", ids[k], ids[k + 1], 10017, 10061)
		var scr: Node = await _open("vs", {"hold": true})
		cx = scr.PORTRAIT_CX
		for i in 2:
			var id: int = ids[k + i]
			var tex: Texture2D = ui.portrait(id)
			var h: Control = scr._holders[i]
			var fit := h.size.x / float(tex.get_width())
			if absf(h.size.y / float(tex.get_height()) - fit) > 0.001:
				bad.append("%d is stretched" % id)
			var head: Array = load("res://scripts/ui/select_frames.gd").HEADS[id]
			var hx := float(head[0]) + float(head[2]) * 0.5
			var home: Vector2 = h.get_meta("home", Vector2(-9999.0, -9999.0))
			var at := home + Vector2((float(tex.get_width()) - hx if i == 0 else hx) * fit, (float(head[1]) + float(head[2]) * 0.5) * fit)
			var head_px = scr.get("HEAD_PX")
			var head_y = scr.get("HEAD_Y")
			if head_px == null or head_y == null or at.distance_to(Vector2(cx[i], head_y)) > 0.5 or absf(float(head[2]) * fit - head_px) > 0.01:
				bad.append("%d head is off" % id)
	check(bad.is_empty(), "both VS portraits keep their proportions and put a head of the same size on the same spot (%s)" % str(bad.slice(0, 3)))

func _new_picks() -> void:
	var s = game.session
	s.begin("versus-cpu")
	s.players[0].merge({"claimed": true, "device": "kb2", "fighter": 10004, "special": 10017, "locked": true}, true)
	s.players[1].merge({"fighter": 10005, "special": 10061, "locked": true}, true)
	s.stage = {"id": "gehenna-night"}
	s.bgm = "alert"
	s.arcade_stage = 3
	s.arcade_ladder = [1, 2]
	s.new_picks()
	check(s.mode == "versus-cpu" and s.players[0]["claimed"] and s.players[0]["device"] == "kb2" and s.players[1]["cpu"], "new_picks keeps the mode, the claim, the device and the CPU slot")
	check(s.players[0]["fighter"] == -1 and s.players[0]["special"] == -1 and not s.players[0]["locked"] and s.players[1]["fighter"] == -1 and not s.players[1]["locked"], "new_picks clears the picks and the locks")
	check(s.stage.is_empty() and s.bgm == "auto" and s.arcade_stage == 0 and s.arcade_ladder.is_empty(), "new_picks clears the stage, the music and the arcade run")
	s.begin("versus2p")
	for i in 2:
		s.players[i]["claimed"] = true
		s.players[i]["device"] = ["kb2", "kb1"][i]     # no pad is connected under test; Session falls back to keyboards for those (input_test)
	s.new_picks()
	check(s.controls("kb2", 1) and s.controls("kb1", 2) and not s.controls("kb1", 1) and not s.controls("kb2", 2), "new_picks leaves each controller on its own side")

## Played sessions seed the pick RNGs from the clock; scripted runs keep their fixed seeds so captures and suites repeat.
func _select_seed() -> void:
	var sess: GDScript = load("res://scripts/core/session.gd")
	var vs: GDScript = load("res://scripts/screens/vs_screen.gd")
	var seed_of := func(scr: Node) -> int: return scr._rng.seed
	_session("versus-cpu", -1, -1)
	var scripted: Node = await _enter_select({}, false)
	check(seed_of.call(scripted) == scripted.SEED, "a scripted run seeds the select screen with its fixed seed")
	vs._rng = null
	_session("versus-cpu", "random", -1)
	await _open("vs", {"hold": true})
	check(vs._rng.seed == 91357, "a scripted run keeps the VS fallback on its fixed seed")
	sess.settings_path = "user://s1_test_settings.cfg"
	var seeds := []
	for n in 3:
		_session("versus-cpu", -1, -1)
		seeds.append(seed_of.call(await _enter_select({}, false)))
	vs._rng = null
	_session("versus-cpu", "random", -1)
	await _open("vs", {"hold": true})
	var vs_seed: int = vs._rng.seed
	sess.settings_path = sess.REAL_PATH
	vs._rng = null
	check(not seeds.has(scripted.SEED) and seeds[0] != seeds[1] and seeds[1] != seeds[2], "a played session seeds the select screen differently every visit, so the CPU picks vary")
	check(vs_seed != 91357, "a played session seeds the VS fallback from the clock")

## A decoded portrait costs about 7 ms on the main thread: the select screen takes at most one per frame.
func _select_poll() -> void:
	var ui: GDScript = load("res://scripts/ui/ui.gd")
	var scr: Node = await _enter_select()
	scr.exit()
	var rels := ["portrait/10004.webp", "portrait/10005.webp"]
	for rel in rels:
		ui._tex.erase(rel)
		var path: String = ui.BA + rel
		ResourceLoader.load_threaded_request(path)
		scr._pending.append({"id": 0, "rel": rel, "path": path})
	for rel in rels:
		var guard := 0
		while ResourceLoader.load_threaded_get_status(ui.BA + rel) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and guard < 600:
			await process_frame
			guard += 1
	scr._poll_loads()
	check(scr._pending.size() == 1 and ui._tex.has(rels[0]) and not ui._tex.has(rels[1]), "one finished portrait is collected per frame (%d left)" % scr._pending.size())
	scr._poll_loads()
	check(scr._pending.is_empty() and ui._tex.has(rels[1]), "the rest follow one by one")

## While a Special panel is open over a side, that side's text is gone, not dimmed to a faint row under the panel.
func _select_cover() -> void:
	var scr: Node = await _enter_select()
	var side = scr._sides[0]
	side.set_covered(1.0)
	for i in 120:
		side.process(DT)
	check(side.text_layer.modulate.a < 0.01, "a covered side hides its text (alpha %.3f)" % side.text_layer.modulate.a)
	side.set_covered(0.0)
	for i in 120:
		side.process(DT)
	check(side.text_layer.modulate.a > 0.9, "and shows it again when the panel closes")

## Behind a crest wipe the roster pop-in waits for the iris (0.66 s after the screen is built); other transitions start it at once.
func _select_crest_entrance() -> void:
	stub.cover_all = true
	_session("versus2p", -1, -1)
	await game.go("select", {}, "crest")
	var scr: Node = game.current()
	scr.set_process(false)
	check(is_equal_approx(scr._t, -0.66), "a crest wipe starts the select entrance at -0.66 s (%.2f)" % scr._t)
	scr._process(1.0)
	check(is_equal_approx(scr._t, -0.61), "a hitch moves the waiting entrance by no more than the wipe's own clamp (%.2f)" % scr._t)
	_tick(scr, 30)
	check(_tiles_shown(scr) == 0, "no roster tile has started to pop while the wipe is still black (%d)" % _tiles_shown(scr))
	_tick(scr, 40)
	check(_tiles_shown(scr) > 0, "the roster pops in once the iris opens (%d tiles)" % _tiles_shown(scr))
	_session("versus2p", -1, -1)
	await game.go("select", {}, "fade")
	scr = game.current()
	scr.set_process(false)
	check(scr._t == 0.0, "a fade starts the entrance at once")
	stub.cover_all = false

func _tiles_shown(scr: Node) -> int:
	var n := 0
	for tl in scr._tiles:
		if (tl["holder"] as Control).modulate.a > 0.0:
			n += 1
	return n

## The "?" tile's silhouette never goes pale: cycling swaps dark for dark, entering crossfades from the old art, and leaving
## fades a dark ghost, not a full-colour one.
func _select_random_art() -> void:
	var side = load("res://scripts/ui/select_side.gd").new().setup(1)
	side.show_fighter(10004)
	side.start()
	for i in 90:
		side.process(DT)
	side.show_fighter(10005)
	side.process(DT)
	check(side._ghost.modulate.a > 0.4 and side._ghost.modulate.a < 0.7, "a plain move keeps the soft 0.55 ghost (%.2f)" % side._ghost.modulate.a)
	for i in 60:
		side.process(DT)
	game.session.reduce_flashes = true
	side.show_fighter(10004)
	side.process(DT)
	game.session.reduce_flashes = false
	check(side._ghost.modulate.a > 0.9, "Reduce Flashes keeps the old art solid under the new one (ghost %.2f)" % side._ghost.modulate.a)
	for i in 60:
		side.process(DT)
	side.show_random(10005)
	side.process(DT)
	check(side._ink < 1.0 and side._ghost.modulate.a > 0.9, "entering ? crossfades from the old art without a pale gap (ink %.2f, ghost %.2f)" % [side._ink, side._ghost.modulate.a])
	for i in 60:
		side.process(DT)
	check(is_equal_approx(side._ink, 1.0) and side._cur.modulate.a > 0.99, "the silhouette settles dark and solid")
	for id in [10005, 10004]:
		side.show_random(id)
		side.process(DT)
		check(side._cur.modulate.a > 0.99 and side._ghost.modulate.a < 0.01, "cycling to %d swaps the silhouette at full opacity (%.2f, ghost %.2f)" % [id, side._cur.modulate.a, side._ghost.modulate.a])
	side.clear_random()
	side.show_fighter(10005)
	side.process(DT)
	var dim: Variant = side._ghost_mat.get_shader_parameter("dim")
	var sat: Variant = side._ghost_mat.get_shader_parameter("saturation")
	check(typeof(dim) == TYPE_FLOAT and typeof(sat) == TYPE_FLOAT and dim < 0.2 and sat < 0.1, "leaving ? fades a dark ghost, not full colour (dim %s, saturation %s)" % [dim, sat])
	check(side._ghost.modulate.a > 0.9, "and the dark ghost is solid, so the plate never shows through (%.2f)" % side._ghost.modulate.a)
	for i in 60:
		side.process(DT)
	check(is_equal_approx(side._ink, 0.0), "the new art comes back to full colour")

## Leaving "?" onto the fighter its silhouette shows swaps the RANDOM card for that fighter's name (issue #1).
func _select_random_name() -> void:
	var side = load("res://scripts/ui/select_side.gd").new().setup(1)
	side.show_fighter(10004)
	side.show_random(10005)
	check(side._name.text == "RANDOM", "the ? tile shows the RANDOM card")
	side.clear_random()
	side.show_fighter(10005)
	var want := Fighters.display_name(game.by_id[10005]).to_upper()
	check(side._name.text == want, "stepping onto the silhouette's own fighter shows its name (%s, want %s)" % [side._name.text, want])

# VS screen: the stage-start beat
func _vs_beat() -> void:
	var VL: GDScript = load("res://scripts/ui/vs_layout.gd")
	check(VL.band_k(0.0) == 0.0 and VL.band_k(VL.BAND_OPEN) == 1.0 and VL.band_k(1.0) == 1.0, "band: 0 at the start, open after 11 frames")
	var prev := 0.0
	var mono := true
	for i in 12:
		var k: float = VL.band_k(float(i) / 60.0)
		mono = mono and k >= prev and k <= 1.0
		prev = k
	check(mono, "band opens monotonically and never overshoots")
	check(is_equal_approx(VL.stamp(0.0).x, 1.5) and is_equal_approx(VL.stamp(0.117).x, 1.099) and is_equal_approx(VL.stamp(0.383).x, 1.0), "stamp keys: 1.5, 1.099 at 0.117 s, 1.0 at 0.383 s")
	check(is_equal_approx(VL.stamp(0.0).y, 0.02) and VL.stamp(0.05).y == 1.0 and VL.stamp(-0.1).y == 0.0, "stamp alpha: 0.02 at the start, 1 after 0.05 s, 0 before")
	prev = 2.0
	mono = true
	for i in 120:
		var sc: float = VL.stamp(float(i) / 120.0).x
		mono = mono and sc <= prev + 0.000001 and sc >= 1.0
		prev = sc
	check(mono, "the stamp only shrinks toward 1.0 (no overshoot)")
	check(VL.flare(0.0) == 0.0 and is_equal_approx(VL.flare(0.083), 1.25) and is_equal_approx(VL.flare(0.383), 1.0) and VL.flare(-1.0) == 0.0, "flare: 0, 1.25 at 0.083 s, 1.0 at 0.383 s")
	check(VL.deco_k(0.0) == 0.0 and is_equal_approx(VL.deco_k(0.117), 0.8) and VL.deco_k(0.383) == 1.0, "triangle decos: scale-Y 0, 0.8 at 0.117 s, 1.0 at 0.383 s")

	_session("versus2p", 10004, 10005, 10017, 10040)
	game.session.stage = load("res://scripts/core/stages.gd").LIST[0]
	var scr: Node = await _open("vs", {"hold": true})
	var p: Dictionary = scr.probe()
	check(p["band"] == 0.0 and scr._vs.modulate.a == 0.0, "frame 0: band shut, no words yet")
	_tick(scr, 5)
	check(scr.probe()["band"] > 0.5 and scr.probe()["band"] < 1.0 and is_equal_approx(scr._band.scale.y, scr.probe()["band"]), "frame 5: the band is half way and the node follows")
	_tick(scr, 6)
	check(scr.probe()["band"] >= 0.999 and scr._band.scale.y >= 0.999, "frame 11: the band is fully open")
	_tick(scr, 18)
	check(scr._vs.modulate.a == 0.0, "VS is hidden before its beat (frame 29)")
	_tick(scr, 1)
	check(absf(scr._vs.scale.x - 1.5) < 0.001 and scr._vs_flare.scale.x < 0.01, "VS starts at 1.5x with the flare shut (frame 30)")
	var last := 9.0
	var shrink := true
	var floor_ok := true
	for i in 23:
		scr._process(DT)
		var sc: float = scr._vs.scale.x
		shrink = shrink and sc <= last + 0.000001
		floor_ok = floor_ok and sc >= 1.0
		last = sc
	check(shrink and floor_ok and absf(scr._vs.scale.x - 1.0) < 0.004, "VS shrinks to 1.0x in 23 frames and stays above it")
	check(scr._vs.modulate.a == 1.0 and absf(scr.probe()["vs_scale"] - scr._vs.scale.x) < 0.0001, "VS is opaque and the probe reports its scale")
	_tick_to(scr, 1.5)
	for c in scr._world.get_children():
		if c != scr._bg and c != scr._band:
			c.visible = false
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var k := float(img.get_width()) / 1280.0
	var band_px := _px(img, 640.0 * k, (VL.BAND.position.y + 14.0) * k)
	var out_px := _px(img, 640.0 * k, (VL.BAND.position.y - 14.0) * k)
	check(band_px.get_luminance() < 0.2 and band_px.get_luminance() < out_px.get_luminance() + 0.001, "the open band is dark (%s) against the stage plate above it (%s)" % [band_px.to_html(false), out_px.to_html(false)])

# VS screen: every name fits
func _vs_fit() -> void:
	var VL: GDScript = load("res://scripts/ui/vs_layout.gd")
	var FI: GDScript = load("res://scripts/core/fighters.gd")
	var CI: GDScript = load("res://scripts/ui/crest_icon.gd")
	var screen_rect := Rect2(0, 0, 1280, 720)
	var inner: float = VL.PLATE.size.x - 2.0 * VL.PLATE_PAD
	var worst_name := 0.0
	var worst_school := 0.0
	var min_size := 999
	var inside := true
	var crest_ok := true
	for f in game.fighters:
		for i in 2:
			var crest: Vector2 = CI.fit(String(f["school"]))
			var b: Dictionary = VL.block(i, String(f["schoolName"]).to_upper(), FI.display_name(f).to_upper(), crest)
			crest_ok = crest_ok and crest.x > 8.0 and crest.x <= CI.BOX.x and crest.y <= CI.BOX.y
			worst_name = maxf(worst_name, float(b["name_w"]))
			worst_school = maxf(worst_school, float(b["school_w"]) + crest.x + 8.0)
			min_size = mini(min_size, int(b["name_size"]))
			for key in ["plate", "bar", "chip", "crest"]:
				inside = inside and screen_rect.encloses(b[key])
	check(worst_name <= inner + 0.5, "the widest fighter name fits the plate (%.0f of %.0f px)" % [worst_name, inner])
	check(worst_school <= inner + 0.5, "the longest school line with its crest fits the plate (%.0f of %.0f px)" % [worst_school, inner])
	check(min_size >= VL.NAME_MIN, "no fighter name shrinks below %d px (%d)" % [VL.NAME_MIN, min_size])
	check(inside, "every name plate, bar, role chip and crest stays on screen")
	check(crest_ok, "every school has a crest that fits its box (%s)" % str(CI.BOX))
	var max_end: Array = [0.0, 0.0]
	var min_start: Array = [9999.0, 9999.0]
	var specials_fit := true
	var special_inside := true
	var below_plate := true
	for sp in game.specials:
		for i in 2:
			var s: Dictionary = VL.special(i, String(sp["name"]).to_upper())
			specials_fit = specials_fit and float(s["text_w"]) <= VL.SPECIAL_NAME_MAX + 0.5
			special_inside = special_inside and screen_rect.encloses(s["plate"]) and screen_rect.encloses(s["ribbon"]) and screen_rect.encloses(s["face"])
			max_end[i] = maxf(max_end[i], (s["plate"] as Rect2).end.x)
			min_start[i] = minf(min_start[i], (s["plate"] as Rect2).position.x)
			below_plate = below_plate and (s["face"] as Rect2).position.y >= (VL.PLATE.end.y + 4.0)
	check(specials_fit, "the longest of %d special names fits at its fitted size" % game.specials.size())
	check(special_inside, "every special card, ribbon and plate stays on screen")
	check(below_plate, "special blocks sit under the name plates")
	var stage_list: Array = Array(load("res://scripts/core/stages.gd").LIST) + [load("res://scripts/core/stages.gd").RANDOM]
	var stage_fit := true
	var stage_clear := true
	var stage_inside := true
	var longest := 0.0
	for st in stage_list:
		var has_thumb := String(st["plate"]) != ""
		var s: Dictionary = VL.stage(String(st["name"]), String(st["school"]), has_thumb)
		stage_fit = stage_fit and float(s["name_w"]) <= float(s["avail"]) + 0.5 and float(s["school_w"]) <= float(s["avail"]) + 0.5
		stage_inside = stage_inside and screen_rect.encloses(s["plate"])
		var pl: Rect2 = s["plate"]
		stage_clear = stage_clear and pl.position.x >= max_end[0] + 8.0 and pl.end.x <= min_start[1] - 8.0
		longest = maxf(longest, float(s["name_w"]))
	check(stage_fit, "every stage name and school fits the stage plate (%d stages, longest %.0f px)" % [stage_list.size(), longest])
	check(stage_inside, "every stage plate stays on screen")
	check(stage_clear, "the stage plate never reaches a special plate (specials end at %.0f and start at %.0f)" % [max_end[0], min_start[1]])
	var random_plate: Dictionary = VL.stage("Random", "Kivotos", false)
	check(not random_plate["has_thumb"], "a stage with no plate art draws no thumbnail")

# select: the roster, the frames, the name block
func _select_roster() -> void:
	var SC: GDScript = load("res://scripts/screens/select_screen.gd")
	_session("versus2p", -1, -1)
	var scr: Node = await _open("select")
	var tiles: Array = scr._tiles
	check(tiles.size() == 3, "3 tiles")
	var by_pos := {}
	for tl in tiles:
		by_pos["%d,%d" % [tl["row"], tl["col"]]] = tl
	var tl: Dictionary = by_pos["0,0"]
	var br: Dictionary = by_pos["0,2"]
	var first := 99.0
	for t in tiles:
		first = minf(first, float(t["delay"]))
	check(is_equal_approx(first, SC.TILES_START) and is_equal_approx(tl["delay"], first) and is_equal_approx(br["delay"], first), "the top left and bottom right tiles pop first")
	var steps_ok := true
	var max_delay := 0.0
	var seen := {}
	for t in tiles:
		var q: float = (float(t["delay"]) - SC.TILES_START) / SC.TILE_STEP
		steps_ok = steps_ok and absf(q - roundf(q)) < 0.001
		seen[int(roundf(q))] = true
		max_delay = maxf(max_delay, float(t["delay"]))
	check(steps_ok and seen.size() == 2 and seen.has(0) and seen.has(1), "tiles pop in two 50 ms steps (%s)" % str(seen.keys()))
	check(float(by_pos["0,1"]["delay"]) > float(by_pos["0,0"]["delay"]), "the middle tile pops after the corners")
	var mirror_ok := true
	for t in tiles:
		var twin: Dictionary = by_pos["0,%d" % (2 - int(t["col"]))]
		mirror_ok = mirror_ok and is_equal_approx(t["delay"], twin["delay"])
	check(mirror_ok, "the roster closes in symmetrically from both corners")
	check(scr._cursors_at >= max_delay + SC.POP_FAST + SC.POP_SETTLE - 0.0001, "the cursors wait for the last tile to settle (%.2f s)" % scr._cursors_at)
	scr._process(DT)
	check(float(tl["holder"].modulate.a) == 0.0 or SC.TILES_START <= DT, "no tile shows before its delay")
	# a tile's pop: scale and alpha only grow, never past 1 (no spring)
	var t0: float = tl["delay"]
	_tick_to(scr, t0 + 0.0001)
	var grow := true
	var over := false
	var last_s := 0.0
	var last_a := 0.0
	for i in 22:
		scr._process(DT)
		var h: Control = tl["holder"]
		grow = grow and h.scale.x >= last_s - 0.0001 and h.modulate.a >= last_a - 0.0001
		over = over or h.scale.x > 1.0001 or h.modulate.a > 1.0001
		last_s = h.scale.x
		last_a = h.modulate.a
	check(grow and not over and absf(tl["holder"].scale.x - 1.0) < 0.001 and tl["holder"].modulate.a == 1.0, "a tile pops with no overshoot and ends at full size")
	_tick_to(scr, scr._cursors_at - 0.03)
	check(not scr.probe()["entered"], "input stays closed until the last tile has settled")
	_tick_to(scr, scr._cursors_at + 0.03)
	var settled := true
	for t in tiles:
		var h: Control = t["holder"]
		settled = settled and absf(h.scale.x - 1.0) < 0.001 and h.modulate.a == 1.0 and h.position.is_equal_approx((t["c"] as Vector2) - h.size * 0.5)
	check(settled, "every tile is home at full size when the cursors appear")
	check(scr.probe()["entered"], "the screen opens for input once the roster has landed")
	# every tile is a student card with its chip data
	var cards_ok := true
	for t in tiles:
		if t["id"] < 0:
			continue
		var d: Dictionary = game.by_id[t["id"]]
		cards_ok = cards_ok and BaArt.portrait(int(t["id"])) != null and BaArt.role_icon(String(d["role"])) != null and BaArt.attack_color(String(d["bullet"])) != BaArt.ATTACK_OTHER
	check(cards_ok, "both fighter tiles have a Student_Portrait, a role glyph and a known attack type")
	var T: GDScript = load("res://scripts/ui/select_tile.gd")
	check(T.CARD.size.x <= SC.PITCH.x - 3.0 and T.FACE.position.y < T.CARD.position.y, "a card fits the 91.3 px pitch and the portrait breaks out above it")

func _select_pixels() -> void:
	var SCUR: GDScript = load("res://scripts/ui/select_cursor.gd")
	var T: GDScript = load("res://scripts/ui/select_tile.gd")
	# the white copy of Card_Select_Line has no orange glow left
	var src := BaArt.tex("Common__Card_Select_Line").get_image()
	var white: Image = SCUR.white_line().get_image()
	var body := 0
	var kept := 0
	var tinted := 0
	var bigger := 0
	for y in src.get_height():
		for x in src.get_width():
			var a := src.get_pixel(x, y)
			var b := white.get_pixel(x, y)
			if a.a > 0.95 and a.g > 0.85:
				body += 1
				if b.a > 0.95:
					kept += 1
			if b.a > 0.0 and (b.r < 0.999 or b.g < 0.999 or b.b < 0.999):
				tinted += 1
			if b.a > a.a + 0.001:
				bigger += 1
	check(body > 200 and kept == body, "the yellow bracket body survives whole (%d of %d px)" % [kept, body])
	check(tinted == 0 and bigger == 0, "the copy is pure white and never more opaque than the source")
	var glow_left := 0
	for y in src.get_height():
		for x in src.get_width():
			if src.get_pixel(x, y).g < 0.5 and white.get_pixel(x, y).a > 0.05:
				glow_left += 1
	check(glow_left == 0, "no orange glow pixel is left in the copy")

	# P1 red and P2 blue frames, 4 px wide, pulsing 1.0 to 0.7
	var vp := _viewport(Color.WHITE, Vector2i(400, 200))
	var frames: Array = []
	for s in 2:
		var c: Node = SCUR.new()
		c.setup(s + 1, load("res://scripts/ui/ba_tokens.gd").side(s + 1))
		vp.add_child(c)
		c.snap_to(Vector2(100.0 + 200.0 * s, 100.0))
		c.appear()
		c.tick(1.0, 0.0)
		c.nudge()
		c.tick(0.001, 0.0)
		frames.append(c)
	await process_frame
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	var col: Array = []
	for s in 2:
		var cx := 100.0 + 200.0 * s
		var sum := Color(0, 0, 0, 0)
		var n := 0
		var run := 0
		var best_run := 0
		for x in range(int(cx) - 60, int(cx) + 60):
			var px := _px(img, x, 100.0)
			if px.get_luminance() < 0.9:
				sum += px
				n += 1
				run += 1
				best_run = maxi(best_run, run)
			else:
				run = 0
		col.append(sum / maxf(float(n), 1.0))
		check(n > 0 and best_run >= 3 and best_run <= 7, "P%d frame stroke is about 4 px wide (%d)" % [s + 1, best_run])
	check(col[0].r > col[0].b + 0.25 and col[0].r > col[0].g + 0.25, "the P1 frame is red (%s)" % col[0].to_html(false))
	check(col[1].b > col[1].r + 0.25 and col[1].b > col[1].g + 0.05 and col[1].g < col[1].b, "the P2 frame is blue, not green (%s)" % col[1].to_html(false))
	var orange := 0
	for y in 200:
		for x in 400:
			var px := _px(img, x, y)
			if px.r > 0.85 and px.g > 0.3 and px.g < 0.65 and px.b < 0.25:
				orange += 1
	check(orange == 0, "no orange glow reaches the screen (%d px)" % orange)
	var f0: Node = frames[0]
	check(is_equal_approx(f0.pulse(), 1.0), "a moved frame starts at full alpha")
	f0.tick(0.7, 0.0)
	check(absf(f0.pulse() - 0.7) < 0.01, "the frame pulses down to 0.7 after 0.7 s (%.3f)" % f0.pulse())
	f0.lock()
	check(f0.pulse() == 1.0, "a locked frame holds full alpha")
	vp.queue_free()

	# the tiles: portrait breaking out of the card, chip colour from the attack type
	var tv := _viewport(Color(0.05, 0.1, 0.2), Vector2i(600, 540))
	var holders: Array = []
	var ids: Array = []
	for f in game.fighters:
		ids.append(int(f["id"]))
	ids.append(-1)
	for n in ids.size():
		var t: Node = T.new().setup(ids[n])
		t.size = Vector2(80, 80)
		t.position = Vector2(float(n % 6) * 100.0 + 10.0, float(n / 6) * 100.0 + 10.0)
		tv.add_child(t)
		holders.append(t)
	await process_frame
	await process_frame
	await process_frame
	var timg := tv.get_texture().get_image()
	var bg := Color(0.05, 0.1, 0.2)
	var chip_ok := 0
	var face_ok := 0
	var breakout := 0
	for n in ids.size():
		var id: int = ids[n]
		var o: Vector2 = (holders[n] as Control).position + Vector2(40, 40)
		if id < 0:
			var qpx := _px(timg, o.x, o.y + 4.0)
			check(qpx != bg, "the random tile draws its card")
			continue
		var d: Dictionary = game.by_id[id]
		var chip: Rect2 = Rect2(o + Vector2(T.CARD.position.x - 3.0, T.CARD.end.y - T.CHIP.y + 3.0), T.CHIP)
		var cp := _px(timg, chip.position.x + 3.0, chip.position.y + chip.size.y * 0.5)
		var want := BaArt.attack_color(String(d["bullet"]))
		if absf(cp.r - want.r) < 0.1 and absf(cp.g - want.g) < 0.1 and absf(cp.b - want.b) < 0.1:
			chip_ok += 1
		var drawn := 0
		for yy in range(int(o.y + T.FACE.position.y + 10.0), int(o.y + T.FACE.end.y - 6.0), 3):
			for xx in range(int(o.x + T.FACE.position.x + 10.0), int(o.x + T.FACE.end.x - 10.0), 3):
				if _px(timg, xx, yy).is_equal_approx(bg) == false:
					drawn += 1
		if drawn > 100:
			face_ok += 1
		var top := 0
		for xx in range(int(o.x + T.FACE.position.x), int(o.x + T.FACE.end.x)):
			for yy in range(int(o.y + T.FACE.position.y), int(o.y + T.CARD.position.y) - 1):
				if _px(timg, xx, yy).is_equal_approx(bg) == false:
					top += 1
		if top > 8:
			breakout += 1
	check(chip_ok == 2, "the corner chip is the attack-type colour on both fighter tiles (%d)" % chip_ok)
	check(face_ok == 2, "both portraits draw inside their card (%d)" % face_ok)
	check(breakout >= 1, "hair, ears or halos break out of the card top on %d of 2 tiles" % breakout)
	tv.queue_free()

	# the band layer leaves the trapezoid alone
	var bv := _viewport(Color.BLACK)
	var band := ColorRect.new()
	band.size = Vector2(1280, 720)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/select_band.gdshader")
	mat.set_shader_parameter("field", BaArt.tex("UIs__00_Images__Image_Triangle_Pattern_Deco_1"))
	mat.set_shader_parameter("ring", BaArt.tex("UIs__00_Images__Image_Deco_Circle"))
	band.material = mat
	bv.add_child(band)
	await process_frame
	await process_frame
	await process_frame
	var bimg := bv.get_texture().get_image()
	var lit := 0
	for y in range(0, 720, 6):
		for x in range(0, 1280, 6):
			var inside_trap: bool = x > 258.0 + 0.18611 * y + 3.0 and x < 1280.0 - (258.0 + 0.18611 * y) - 3.0
			if _px(bimg, x, y).get_luminance() > 0.02:
				lit += 1
				if inside_trap:
					lit += 100000
	check(lit > 200 and lit < 100000, "the facet field and ring draw in the white bands only (%d)" % lit)
	bv.queue_free()

	# the name block
	var SS: GDScript = load("res://scripts/ui/select_side.gd")
	var worst := 0.0
	var inside := true
	var rows_ok := true
	for sl in [1, 2]:
		var side = SS.new().setup(sl)
		for f in game.fighters:
			side.show_fighter(int(f["id"]))
			var l: Dictionary = side.layout()
			var all: Rect2 = l["school"].merge(l["name"])
			for r in l["rows"]:
				all = all.merge(r["tag"]).merge(r["plate"])
			worst = maxf(worst, all.size.x)
			inside = inside and all.position.x >= 0.0 and all.end.x <= 1280.0 and (all.end.x <= 31.0 + SS.MAX_W + 70.0 if sl == 1 else all.position.x >= 1250.0 - SS.MAX_W - 70.0)
			rows_ok = rows_ok and l["rows"].size() == 3
	check(inside and worst > 100.0, "the longest name block stays inside its band (widest %.0f px)" % worst)
	check(rows_ok, "a fighter with data shows CLUB, STRIKER TYPE and EASE OF USE")
	var side2 = SS.new().setup(1)
	var odd: Dictionary = (game.by_id[10005] as Dictionary).duplicate()
	var saved: String = game.by_id[10005]["clubName"]
	game.by_id[10005]["clubName"] = ""
	side2.show_fighter(10005)
	var rl: Array = side2.layout()["rows"]
	game.by_id[10005]["clubName"] = saved
	check(rl.size() == 2 and rl[0]["tag_text"] == "STRIKER TYPE", "a row without data is left out")
	side2.show_random(10004)
	check(side2.layout()["rows"].is_empty(), "the random tile shows no stat rows")

	# the name gradient: white at the top of the letters, pale blue at the bottom
	var gv := _viewport(Color(0.05, 0.1, 0.2))
	var side3 = SS.new().setup(1)
	side3.show_fighter(10004)
	gv.add_child(side3.text_layer)
	await process_frame
	await process_frame
	await process_frame
	var gimg := gv.get_texture().get_image()
	var nr: Rect2 = side3.layout()["name"]
	var rows_y: Array = []
	for y in range(int(nr.position.y), int(nr.end.y) + 20):
		var bright := 0
		var sum_r := 0.0
		for x in range(int(nr.position.x), int(nr.end.x)):
			var px := _px(gimg, x, y)
			if px.get_luminance() > 0.8:
				bright += 1
				sum_r += px.r
		if bright > 3:
			rows_y.append([y, sum_r / float(bright)])
	check(rows_y.size() > 20, "the name fill is drawn (%d bright rows)" % rows_y.size())
	if rows_y.size() > 20:
		var top_r: float = rows_y[2][1]
		var bot_r: float = rows_y[rows_y.size() - 3][1]
		check(top_r > 0.96 and bot_r < top_r - 0.04, "the name gradient runs from white (%.2f) to pale blue (%.2f red)" % [top_r, bot_r])
	gv.queue_free()
