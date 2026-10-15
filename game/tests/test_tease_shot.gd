extends SceneTree
# Kontrollbilder Beta 1.6.3, Easter Eggs Teil 2 „Necken“ (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_tease_shot.gd -Resolution 1600x720 [-EnvPairs "SHOT_DIR=…"]
# Ohne SHOT_DIR nach docs/module/optik_163_*.png (docs/module/eastereggs2.md 9):
#   menue_tag / menue_nacht      Necken-Menü am Spieler am Zug (ab 10 s: Kugel, Schnarchen, Wecker, Karten ansehen)
#   menue_ausgegraut             vor 10 s: Schnarchen/Wecker ausgegraut mit Ring und Hinweis
#   schnarchen                   Z z z mit Schlafmütze am Gegner (Tag)
#   wecker_tickt / wecker_klingelt  Wecker am Gegner (nachts)
#   wecker_ziel                  Wecker groß über dem eigenen Namensschild, „Kim hat dir einen Wecker gestellt!“
#   kugel_flug / kugel_liegt     Papierkugel auf der Flugbahn bzw. liegend am Ziel („Mpf!“ beim Bot)
#   reaktionen / reaktionen_tag  alle 4 Reaktionen gleichzeitig (Lachen, Schreck, Klatschen, Daumen), nachts bzw. tags
#   schnarchen_oben_nacht, schnarchen_rechts_tag, wecker_oben_tag   Beta 1.6.3: größere Effekte an den anderen Plätzen
#   gross_effekte_tag / gross_effekte_nacht   großer Modus: Schnarchen, Reaktionen, Kugel bzw. Wecker klingelt, Kugel im Flug
#   reaktion_knopf               Reaktionsfächer offen am eigenen Platz (verdeckt weder Sortieren, Rückseiten, Mau noch Hinweis)
#   gross_menue                  großer Modus: Menü an der Listenzeile, Reaktionsknopf links der Zeile „Du“
#   sehr_gross                   Schrift „Sehr groß“: Menü und Reaktionsfächer
#   rundenende_reaktion          Rundenende: Reaktionsknopf über der Tafel, eine Reaktion steigt auf
#   en_menue                     Englisch

var nav: ScreenNav
var out := ""
var clock := 500000
var ts: TableScreen
var tz: TeaseFx
var fake: ShotSource


class ShotSource:
	extends TableSource
	var seat := 0
	var v: Dictionary = {}
	var sent: Array = []

	func mode() -> String:
		return "client"

	func local_seat() -> int:
		return seat

	func current_view() -> Dictionary:
		return v

	func send_fx(req: Dictionary) -> void:
		sent.append(req)


func _initialize() -> void:
	call_deferred("run")


func now_ms() -> int:
	return clock


func shot(file: String) -> void:
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("optik_163_%s.png" % file))
	print("Bild: optik_163_%s.png" % file)


func show(turn: int, phase := "turn") -> void:
	fake.v["turn"] = turn
	fake.v["phase"] = phase
	fake.tease.note_view(fake.v, clock)
	var n := ts.table.night          # Sicht setzt die Tageszeit nach side: Tag/Nacht des Bildes behalten
	ts.table.apply_view(fake.v)
	ts.table.set_night(n)


func fx(k: String, from: int, to := -1, r := "") -> void:
	clock += 300
	var m := NetProtocol.make_fx(k, from, to, r)
	fake.tease.commit(m, clock)
	fake.fx_event.emit(m)


func run() -> void:
	root.size = Vector2i(1600, 720)
	GameStarter.test_speed = 0.0
	out = OS.get_environment("SHOT_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	var app := UiApp.app()
	var keep := {"grosser_modus": false, "toene": "aus", "effekte": "voll", "necken": true, "schrift": "normal"}
	var before := {}
	if app != null and app.get("settings") != null:
		for key in keep:               # Einstellungen des Rechners merken und am Ende zurücksetzen
			before[key] = app.settings.get_value(key, keep[key])
			app.settings.set_value(key, keep[key])
	nav = ScreenNav.new()
	nav.autostart = false
	root.add_child(nav)
	nav.push(AppScreen.new(), false)
	await process_frame
	var players := [{"name": "Du", "kind": "human"}, {"name": "Kim", "kind": "bot"}, {"name": "Lena", "kind": "bot"}, {"name": "Ben", "kind": "bot"}]
	var src := GameStarter.local("solo", RuleConfig.preset("familie"), players, 11)
	src.max_steps = 0
	ts = TableScreen.create(src, func() -> void: src.start())
	nav.push(ts, false)
	await create_timer(3.0).timeout
	ts._sub_next_ms = 1 << 60
	# Netztisch nachstellen: dieselbe Sicht, Kim/Ben als Menschen (Lena bleibt Computergegner), Steuerung = Attrappe „client“
	fake = ShotSource.new()
	fake.fx_clock = now_ms
	fake.v = src.current_view().duplicate(true)
	fake.seat = int(fake.v.get("seat", 0))
	for p in fake.v.players:
		if int(p.seat) != 2:
			p["kind"] = "human"
	root.add_child(fake)
	tz = ts.table.tease
	tz.attach(fake)
	var me := fake.seat
	var kim := 1 if me != 1 else 2
	show(kim)
	await create_timer(0.5).timeout

	# --- Menü: ausgegraut (vor 10 s), dann Tag und Nacht
	ts.table.set_night(0.0)
	clock += 6000
	tz.open_menu(kim)
	await create_timer(0.3).timeout
	await shot("menue_ausgegraut")
	clock += 5000
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		tz.close_menu(false)
		tz.open_menu(kim)
		await create_timer(0.3).timeout
		await shot("menue_" + tm)
	tz.close_menu(false)

	# --- Schnarchen (Tag), Wecker (Nacht); Beta 1.6.3: doppelt so groß, dazu oben (Lena) und rechts (Ben) in Tag und Nacht
	ts.table.set_night(0.0)
	fx("snore", me, kim)
	await create_timer(1.7).timeout
	await shot("schnarchen")
	await create_timer(3.0).timeout
	show(2)
	ts.table.set_night(1.0)
	fx("snore", me, 2)
	await create_timer(2.0).timeout
	await shot("schnarchen_oben_nacht")
	await create_timer(3.0).timeout
	show(kim)
	fx("alarm", me, kim)
	await create_timer(1.4).timeout
	await shot("wecker_tickt")
	await create_timer(2.2).timeout
	await shot("wecker_klingelt")
	await create_timer(2.0).timeout
	ts.table.set_night(0.0)
	show(2)
	fx("alarm", me, 2)
	await create_timer(3.6).timeout
	await shot("wecker_oben_tag")
	await create_timer(2.0).timeout
	var ben := 3 if me != 3 else 0
	show(ben)
	fx("snore", me, ben)
	await create_timer(1.9).timeout
	await shot("schnarchen_rechts_tag")
	await create_timer(3.0).timeout
	show(kim)
	# Wecker beim Ziel (ich am Zug)
	ts.table.set_night(0.0)
	show(me)
	fx("alarm", kim, me)
	await create_timer(1.2).timeout
	await shot("wecker_ziel")
	await create_timer(4.0).timeout

	# --- Papierkugel: Flug und liegend (an Lena, Computergegner: „Mpf!“)
	show(kim)
	fx("ball", me, 2)
	await create_timer(0.36).timeout
	await shot("kugel_flug")
	fx("ball", kim, 2)
	await create_timer(0.9).timeout
	await shot("kugel_liegt")
	await create_timer(3.5).timeout

	# --- Reaktionen
	ts.table.set_night(1.0)
	var who := [me, kim, 2, 3 if me != 3 else 0]
	for i in 4:
		fx("react", who[i], -1, TeaseRules.FX_REACTS[i])
	await create_timer(0.45).timeout
	await shot("reaktionen")
	await create_timer(1.5).timeout
	ts.table.set_night(0.0)
	for i in 4:
		fx("react", who[i], -1, TeaseRules.FX_REACTS[3 - i])
	await create_timer(0.7).timeout
	await shot("reaktionen_tag")
	await create_timer(1.5).timeout
	tz.picker.toggle()
	await create_timer(0.4).timeout
	await shot("reaktion_knopf")
	tz.picker.open = false

	# --- großer Modus
	ts.table.set_big(true)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.8).timeout
	tz.open_menu(kim)
	tz.picker.toggle()
	await create_timer(0.4).timeout
	await shot("gross_menue")
	tz.close_menu(false)
	tz.picker.open = false
	# Beta 1.6.3: Effekte im großen Modus (Tag: Schnarchen, Reaktionen, Kugel; Nacht: Wecker klingelt, Kugel im Flug)
	await create_timer(0.3).timeout
	fx("snore", me, kim)
	fx("ball", me, 2)
	await create_timer(1.2).timeout
	fx("react", me, -1, "lachen")
	fx("react", 3 if me != 3 else 0, -1, "klatschen")
	await create_timer(0.6).timeout
	await shot("gross_effekte_tag")
	await create_timer(3.5).timeout
	ts.table.set_night(1.0)
	fx("alarm", me, kim)
	await create_timer(3.3).timeout
	fx("ball", me, 3 if me != 3 else 0)
	await create_timer(0.35).timeout
	await shot("gross_effekte_nacht")
	await create_timer(2.5).timeout
	ts.table.set_night(0.0)
	ts.table.set_big(false)
	await process_frame
	ts._layout()

	# --- Schrift „Sehr groß“
	UiFonts.set_level("sehr_gross", root)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.5).timeout
	tz.open_menu(kim)
	tz.picker.toggle()
	await create_timer(0.4).timeout
	await shot("sehr_gross")
	tz.close_menu(false)
	tz.picker.open = false
	UiFonts.set_level("normal", root)
	await process_frame
	ts._layout()

	# --- Rundenende: Reaktionsknopf über der Tafel
	var ranking: Array = []
	for p in fake.v.players:
		ranking.append(int(p.seat))
	fake.v["ranking"] = ranking
	show(-1, "round_over")
	await create_timer(0.8).timeout
	tz.picker.toggle()
	fx("react", me, -1, "klatschen")
	await create_timer(0.5).timeout
	await shot("rundenende_reaktion")
	tz.picker.open = false

	# --- Englisch
	fake.v.erase("ranking")
	show(kim)
	await create_timer(0.6).timeout
	I18n.set_language("en")
	await process_frame
	clock += 11000
	tz.open_menu(kim)
	await create_timer(0.3).timeout
	await shot("en_menue")
	I18n.set_language("de")
	for key in before:
		app.settings.set_value(key, before[key])
	print("RESULT: 1 ok")
	quit(0)
