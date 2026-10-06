extends SceneTree
# Messung (kein Test, vom Testlauf ausgenommen): Was kostet ein Bild am Tisch im Ruhezustand? Mit Renderer starten:
#   godot_run.ps1 -Script res://tests/perf_table.gd -Resolution 2400x1080 -Timeout 120 [-EnvPairs 'KARTEN=23']
# Übungsspiel mit 3 Computergegnern; gemessen wird, während der Mensch am Zug ist und die Regie ruht. Je Abschnitt: Bilder/s,
# Prozesszeit (Skripte und Engine-Prozess), CPU- und GPU-Zeit des Zeichnens, Zeichenaufrufe, Objekte. Danach werden einzelne
# Bausteine angehalten bzw. ausgeblendet, um ihren Anteil zu sehen.

var nav: ScreenNav
var ts: TableScreen


func _initialize() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await process_frame


func measure(label: String, seconds := 2.5) -> Dictionary:
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await frames(10)
	var n := 0
	var proc := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var draws := 0.0
	var objs := 0.0
	var prims := 0.0
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var end := t0 + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		n += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var secs := (Time.get_ticks_usec() - t0) / 1000000.0
	var r := {"fps": n / secs, "proc": proc / n, "cpu": cpu / n, "gpu": gpu / n, "draws": draws / n, "objs": objs / n, "prims": prims / n, "worst": worst}
	print("%-34s %5.0f fps | Prozess %5.2f ms | Zeichnen CPU %5.2f ms GPU %5.2f ms | %5.0f Aufrufe %5.0f Obj %6.0f Prim | schlechtestes Bild %5.1f ms" % [label, r.fps, r.proc, r.cpu, r.gpu, r.draws, r.objs, r.prims, r.worst])
	return r


func run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	GameStarter.test_speed = 0.3
	nav = ScreenNav.new()
	root.add_child(nav)
	await frames(5)
	print("Fenster ", root.size, " sichtbar ", root.get_visible_rect().size)
	await measure("Hauptmenü")
	var cfg := RuleConfig.new()
	var karten := int(OS.get_environment("KARTEN")) if OS.get_environment("KARTEN") != "" else 0
	if karten > 0:
		cfg.hand_size = karten
	var players := [{"name": "Ich", "kind": "human"}, {"name": "Minka", "kind": "bot"}, {"name": "Mogli", "kind": "bot"}, {"name": "Luna", "kind": "bot"}]
	var src := GameStarter.local("solo", cfg, players, 4711)
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	# warten, bis der Mensch dran ist und die Regie ruht
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await frames(1)
		if int(ts.view.get("turn", -1)) == 0 and not ts.table.director.is_busy() and str(ts.view.get("phase", "")) == "turn":
			break
	await create_timer(1.0 + float(OS.get_environment("WARTEN") if OS.get_environment("WARTEN") != "" else "0")).timeout
	print("Hand %d Karten, Seite %s" % [(ts.view.get("hand", []) as Array).size(), str(ts.view.get("side", ""))])
	await measure("Tisch, Ruhe (alles an)")
	# Anteile: einzeln anhalten bzw. ausblenden
	var parts := {
		"Hand angehalten": [ts.hand],
		"Regie+Tisch angehalten": [ts.table],
	}
	for label in parts:
		for n in parts[label]:
			(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
		await measure(label)
		for n in parts[label]:
			(n as Node).process_mode = Node.PROCESS_MODE_INHERIT
	var bg: Variant = ts.table.get("_bg")
	if bg is CanvasItem:
		(bg as CanvasItem).visible = false
		await measure("ohne Hintergrund-Shader")
		(bg as CanvasItem).visible = true
	var ring: Variant = ts.table.get("_ring")
	if ring is CanvasItem:
		(ring as CanvasItem).visible = false
		await measure("ohne Richtungsring")
		(ring as CanvasItem).visible = true
	ts.hand.visible = false
	await measure("ohne Hand")
	ts.hand.visible = true
	ts.table.visible = false
	await measure("ohne Tisch (nur Hand)")
	ts.table.visible = true
	ts.table.visible = false
	ts.hand.visible = false
	await measure("ohne Tisch und Hand")
	ts.table.visible = true
	ts.hand.visible = true
	_dump_counts()
	ts._leave_now()
	await create_timer(0.5).timeout
	print("RESULT: 1 ok")
	quit(0)


func _dump_counts() -> void:
	var counts := {}
	var procs := {}
	_walk(ts, counts, procs)
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var line := "Knoten: "
	for k in keys.slice(0, 14):
		line += "%s %d, " % [k, counts[k]]
	print(line)
	var pk := procs.keys()
	pk.sort_custom(func(a, b): return procs[a] > procs[b])
	line = "_process aktiv: "
	for k in pk.slice(0, 20):
		line += "%s %d, " % [k, procs[k]]
	print(line)


func _walk(n: Node, counts: Dictionary, procs: Dictionary) -> void:
	var key := n.get_class()
	var s: Script = n.get_script()
	if s != null:
		key = s.resource_path.get_file() if s.resource_path != "" else ("inner:" + str(s.get_global_name()))
		if s.resource_path == "":
			key = "inner " + n.get_class()
	counts[key] = int(counts.get(key, 0)) + 1
	if n.is_processing() and n.can_process():
		procs[key] = int(procs.get(key, 0)) + 1
	for c in n.get_children():
		_walk(c, counts, procs)
