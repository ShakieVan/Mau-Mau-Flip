extends SceneTree
# Kontrollbilder Beta 1.3.3, App-Wechsel (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_ui_away_shot.gd -Resolution 1600x720
# Je Tag/Nacht, normal und groß: Püppi „kurz in einer anderen App“ am Platz bzw. in der Liste mit dem Hinweis des Gastgebers
# („platz“), danach der Knopf „Computer für Püppi spielen lassen“ („knopf“) und beim Gast der Hinweis „Shakie (Gastgeber) ist kurz in
# einer anderen App – warte …“ („gastgeber“):
# docs/geraetetest/1.3.3/app_wechsel_<platz|knopf|gastgeber>_<normal|gross>_<tag|nacht>.png

var nav: ScreenNav
var ts: TableScreen
var shots := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1600, 720)
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/geraetetest/1.3.3").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	nav = ScreenNav.new()
	root.add_child(nav)
	await process_frame
	var players := [{"name": "Du", "kind": "human"}, {"name": "Püppi", "kind": "bot"}, {"name": "Shakie", "kind": "bot"}]
	var src := GameStarter.local("solo", RuleConfig.preset("familie"), players, 1)
	src.speed = 0.0
	src.max_steps = 0
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	await create_timer(3.0).timeout
	ts._sub_next_ms = 1 << 60          # keine Nachführung durch die (lokale) Quelle
	for big in [false, true]:
		ts.table.set_big(big)
		for tm in ["tag", "nacht"]:
			for k in ["platz", "knopf", "gastgeber"]:
				var v: Dictionary = src.current_view().duplicate(true)
				for p in v.get("players", []):
					if int(p.seat) == 1 and k != "gastgeber":
						p["away"] = true
					if int(p.seat) == 2 and k == "gastgeber":
						p["away"] = true
						p["host"] = true
				ts.table.night = 1.0 if tm == "nacht" else 0.0
				ts._on_state([], v)
				ts._sub_seat = 1 if k == "knopf" else -1
				ts._sub_hint_seat = 1 if k == "platz" else -1
				ts._sub_hint_label.text = I18n.t("%s ist kurz in einer anderen App") % "Püppi"
				ts._sub_btn.text = I18n.t("Computer für %s spielen lassen") % "Püppi"
				ts._conn.visible = false
				if k == "gastgeber":
					ts._conn_label.text = I18n.t("%s (Gastgeber) ist kurz in einer anderen App – warte …") % "Shakie"
					for b: Control in [ts._conn_menu, ts._conn_save, ts._conn_host, ts._conn_sub]:
						b.visible = false
					ts._conn.visible = true
				ts._layout()
				for i in 8:
					await process_frame
				ts.table.night = 1.0 if tm == "nacht" else 0.0
				await process_frame
				await process_frame
				root.get_texture().get_image().save_png(out.path_join("app_wechsel_%s_%s_%s.png" % [k, "gross" if big else "normal", tm]))
				shots += 1
	print("RESULT: %d ok" % shots)
	quit(0)
