extends SceneTree
# Rauchtest Modul F1b: Tisch-Demo laden und alle Schritte der Ereignisfolge durchspielen (beschleunigt).
const CleanExit := preload("res://tests/clean_exit.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ok := 0
	var demo: Control = load("res://scenes/dev/table_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set("auto", false)
	Engine.time_scale = 6.0
	var steps: int = (demo.get("steps") as Array).size()
	for i in steps:
		demo.call("next_step")
		var guard := 0
		while (demo.get("table") as TableView).director.is_busy() and guard < 2000:
			await process_frame
			guard += 1
	Engine.time_scale = 1.0
	var t: TableView = demo.get("table")
	if t.side == "dunkel": ok += 1
	else: print("FAIL: Seite am Ende %s" % t.side)
	if t.round_end.visible: ok += 1
	else: print("FAIL: Rundenende nicht sichtbar")
	print("RESULT: %d ok" % ok)
	# Töne anhalten und aufräumen, sonst „resources still in use at exit“ (Sieg-Ton läuft noch)
	await CleanExit.finish(self, 0 if ok == 2 else 1)
