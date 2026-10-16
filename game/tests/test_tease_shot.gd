extends SceneTree
# Kontrollbilder Easter Eggs Teil 2 „Necken“ (mit Renderer; „_shot“: vom Testlauf ausgenommen):
#   tools/godot_run.ps1 -Script res://tests/test_tease_shot.gd -Resolution 1600x720 [-EnvPairs "SHOT_DIR=…","SERIE=163"]
#   (15.10.2026: mit -Extra '--rendering-driver','opengl3_angle', siehe test_tease_icons_shot.gd)
# Beta 1.6.5 (Standard, SERIE=165) nach docs/module/optik_165_*.png: die 4 Reaktionsknöpfe (Lachen, Klatschen, Daumen hoch, Schreck)
#   tisch_tag / tisch_nacht      Knöpfe neben „Du“, verdecken weder Sortieren, Rückseiten, Mau, Hand, Stapel noch Hinweis
#   reaktion_tag                 eigener Daumen hoch steigt auf (festes Bild, Fluent Emoji)
#   gesperrt                     Sperrzeit (eigener Eimer leer): alle 4 ausgegraut
#   gross_tag / gross_nacht      großer Modus: Knöpfe in der Zeile „Du“ vor der Kartenzahl
#   sehr_gross / gross_sehr_gross_nacht   Schrift „Sehr groß“ (normal bzw. großer Modus)
#   rundenende                   Rundenende: Knöpfe über der Tafel, eine Reaktion steigt auf
#   en_tag                       Englisch (Hinweis englisch, Knöpfe ohne Text)
# SERIE=1611 nach docs/module/optik_1611_baeh_*.png (Beta 1.6.11: fünfte Reaktion „Bäää“ 😝): wie 165 mit fünf Knöpfen, dazu
#   reaktion_tag / reaktion_nacht  Bäää steigt auf · alle_tag  alle fünf gleichzeitig · rundenende mit Bäää
#   (Aufruf mit -EnvPairs "SERIE=1611"; die Bilder heißen optik_1611_baeh_<name>.png)
# SERIE=166 nach docs/module/optik_166_*.png (Furzkissen, eastereggs2.md 12.4):
#   menue_tag / menue_nacht      Necken-Menü mit der Zeile „Furzkissen“ (Mit Namen / Geheim)
#   menue_gesperrt               nach dem eigenen Kissen: grau, „Das Kissen muss sich erst wieder aufpusten.“ (und „Da liegt schon …“)
#   bestaetigung                 Leger: leise Zeile „Kissen liegt bei Kim.“
#   pups_tag / pups_nacht        Kissen plattgedrückt, Wolke, „Pfffrt!“ an Kim; pups_oben_nacht an Lena (oben)
#   zeile_tag / zeile_geheim     danach „Du war's!“ bzw. „Wer war das?“
#   ziel_tag / ziel_nacht        beim Ziel (ich): groß über dem eigenen Namensschild, danach „Kim war's!“ (ziel_zeile)
#   gross_menue / gross_pups_tag / gross_pups_nacht   großer Modus
#   sehr_gross                   Schrift „Sehr groß“: Menü mit Kissen-Zeile
#   reduziert                    Effekte reduziert: liegt flach, keine Bewegung
#   en_menue / en_pups           Englisch
# SERIE=1610 nach docs/module/optik_1610_*.png (Beta 1.6.10: Furzkissen als zwei runde Knöpfe „Kissen geheim“/„Kissen mit Namen“):
#   menue_tag / menue_nacht      Mensch am Zug: Reihe 1 Kugel, Schnarchen, Wecker, Karten ansehen; Reihe 2 die beiden Kissen (zoom_*: Ausschnitt 2×)
#   bot_tag / bot_nacht          Computergegner: eine Reihe Kugel, Kissen geheim, Kissen mit Namen, Karten ansehen
#   ausgegraut / ausgegraut_nacht   eigenes Kissen gerade gelegt (Sperre) und Kim nicht am Zug: Kissen und Schnarchen/Wecker grau
#   gross_tag / gross_nacht / gross_sehr_gross   großer Modus (mit Schrift „Sehr groß“)
#   sehr_gross_kim/_lena_bot/_ben / schrift_gross   Schrift „Sehr groß“ an allen drei Plätzen bzw. „Groß“
#   en_menue / en_bot            Englisch
# SERIE=167 nach docs/module/optik_167_*.png (Beta 1.6.7: „Erwischt!“ als Buzzer, Necken-Menü bleibt offen):
#   buzzer_tag / buzzer_nacht    Kim (1 Karte, kein Mau) erwischbar: großer roter Druckknopf unter seiner Kopfzeile
#   zwei_tag / zwei_nacht        Kim und Lena gleichzeitig erwischbar
#   menue_buzzer                 Necken-Menü an Ben offen, Kim wird erwischbar: Menü bleibt, Buzzer sichtbar daneben
#   menue_ueber_buzzer           Menü liegt (erzwungen) über Kims Buzzer: der Buzzer liegt sichtbar über der Blase
#   menue_vor_zugwechsel / menue_zugwechsel   Menü an Kim (am Zug) offen, dann kommt Ben dran: Schnarchen/Wecker grau,
#                                „Erst, wenn Kim dran ist.“, die Blase bleibt an ihrer Stelle
#   gross_tag / gross_nacht / gross_zwei   großer Modus: Buzzer links neben der Zeile (zwei: Kim und Lena)
#   sehr_gross / gross_sehr_gross          Schrift „Sehr groß“ (normal bzw. großer Modus, mit Menü)
#   reduziert                    Effekte reduziert: kein Pulsieren
#   en_buzzer                    Englisch
# SERIE=163 nach docs/module/optik_163_*.png (docs/module/eastereggs2.md 9; Stand 1.6.3, Reaktionsknopf seit 1.6.5 wie oben):
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
var serie := "165"


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
	var pre := serie + ("_baeh" if serie == "1611" else "")   # Beta 1.6.11: optik_1611_baeh_*.png
	root.get_texture().get_image().save_png(out.path_join("optik_%s_%s.png" % [pre, file]))
	print("Bild: optik_%s_%s.png" % [pre, file])


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
	root.size = Vector2i(int(OS.get_environment("SHOT_W")) if OS.get_environment("SHOT_W") != "" else 1600, 720)   # 1.6.11: SHOT_W=1280 für 16:9
	GameStarter.test_speed = 0.0
	out = OS.get_environment("SHOT_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../docs/module").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	if OS.get_environment("SERIE") != "":
		serie = OS.get_environment("SERIE")
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
	if serie == "165" or serie == "166" or serie == "167" or serie == "1610" or serie == "1611":
		if serie == "165" or serie == "1611":
			await run_165(me, kim)
		elif serie == "1610":
			await run_1610(me, kim)
		elif serie == "166":
			await run_166(me, kim)
		else:
			await run_167(me, kim)
		I18n.set_language("de")
		for key in before:
			app.settings.set_value(key, before[key])
		print("RESULT: 1 ok")
		quit(0)
		return

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
	await create_timer(0.4).timeout
	await shot("reaktion_knopf")

	# --- großer Modus
	ts.table.set_big(true)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.8).timeout
	tz.open_menu(kim)
	await create_timer(0.4).timeout
	await shot("gross_menue")
	tz.close_menu(false)
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
	await create_timer(0.4).timeout
	await shot("sehr_gross")
	tz.close_menu(false)
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
	fx("react", me, -1, "klatschen")
	await create_timer(0.5).timeout
	await shot("rundenende_reaktion")

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


# Beta 1.6.5: die 4 Reaktionsknöpfe am Tisch (Kim am Zug, eigener Eimer voll bzw. leer)
func run_165(me: int, kim: int) -> void:
	for tm in ["tag", "nacht"]:
		clock += 20000
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(kim)
		await create_timer(0.5).timeout
		await shot("tisch_" + tm)
	ts.table.set_night(0.0)
	clock += 20000
	var rx := "baeh" if serie == "1611" else "daumen"     # Beta 1.6.11: die neue Reaktion „Bäää“
	fx("react", me, -1, rx)
	await create_timer(0.55).timeout
	await shot("reaktion_tag")
	await create_timer(1.5).timeout
	if serie == "1611":
		# nachts: Bäää steigt auf; dann alle fünf von verschiedenen Plätzen gleichzeitig
		ts.table.set_night(1.0)
		clock += 20000
		fx("react", me, -1, "baeh")
		await create_timer(0.55).timeout
		await shot("reaktion_nacht")
		await create_timer(1.5).timeout
		ts.table.set_night(0.0)
		clock += 20000
		var who := [me, 1 if me != 1 else 0, 2, 3 if me != 3 else 0, me]
		for i in TeaseMenu.REACT_ORDER.size():
			clock += 3000
			fx("react", int(who[i]), -1, TeaseMenu.REACT_ORDER[i])
		await create_timer(0.6).timeout
		await shot("alle_tag")
		await create_timer(1.8).timeout
	# Sperrzeit: eigener Eimer leer → alle 4 grau
	clock += 20000
	for i in TeaseRules.REACT_BUCKET:
		fx("react", me, -1, "lachen")
	await create_timer(2.0).timeout
	await shot("gesperrt")
	# großer Modus, Tag und Nacht
	clock += 20000
	ts.table.set_big(true)
	await process_frame
	ts._layout()
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(kim)
		await create_timer(0.9).timeout
		await shot("gross_" + tm)
	# Schrift „Sehr groß“: großer Modus (nachts), dann normal (tags)
	UiFonts.set_level("sehr_gross", root)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.8).timeout
	await shot("gross_sehr_gross_nacht")
	ts.table.set_night(0.0)
	ts.table.set_big(false)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.8).timeout
	await shot("sehr_gross")
	UiFonts.set_level("normal", root)
	await process_frame
	ts._layout()
	# Rundenende: Knöpfe über der Tafel, eine Reaktion steigt auf
	var ranking: Array = []
	for p in fake.v.players:
		ranking.append(int(p.seat))
	fake.v["ranking"] = ranking
	show(-1, "round_over")
	await create_timer(0.8).timeout
	clock += 20000
	fx("react", me, -1, "baeh" if serie == "1611" else "klatschen")
	await create_timer(0.5).timeout
	await shot("rundenende")
	fake.v.erase("ranking")
	# Englisch
	show(kim)
	await create_timer(1.6).timeout
	I18n.set_language("en")
	show(kim)
	await create_timer(0.5).timeout
	await shot("en_tag")


# Beta 1.6.6: Furzkissen (Bestätigung nur beim Leger, Pups für alle)
func placed(from: int, to: int, reveal: bool) -> void:
	var m := NetProtocol.make_cushion(from, to, reveal)
	fake.tease.commit(m, clock)
	fake.fx_event.emit(m)


func pop(to: int, reveal: bool, from := -1) -> void:
	clock += 300
	var m := NetProtocol.make_cushion_pop(to, reveal, from)
	fake.tease.commit(m, clock)
	fake.fx_event.emit(m)


func run_166(me: int, kim: int) -> void:
	var lena := 2
	var ben := 3 if me != 3 else 0
	# Menü mit der Kissen-Zeile, Tag und Nacht
	for tm in ["tag", "nacht"]:
		clock += 20000
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(kim)
		await create_timer(0.4).timeout
		tz.close_menu(false)
		tz.open_menu(kim)
		await create_timer(0.3).timeout
		await shot("menue_" + tm)
	tz.close_menu(false)
	# Leger: Bestätigung als leise Zeile, danach gesperrt
	ts.table.set_night(0.0)
	placed(me, kim, true)
	await create_timer(0.4).timeout
	await shot("bestaetigung")
	tz.open_menu(kim)
	await create_timer(0.3).timeout
	await shot("menue_gesperrt")
	tz.close_menu(false)
	await create_timer(3.0).timeout
	# Pups an Kim: mit Namen (ich war's), dann nachts geheim; oben an Lena
	pop(kim, true, me)
	await create_timer(0.45).timeout
	await shot("pups_tag")
	await create_timer(1.0).timeout
	await shot("zeile_tag")
	await create_timer(3.0).timeout
	ts.table.set_night(1.0)
	pop(kim, false)
	await create_timer(0.45).timeout
	await shot("pups_nacht")
	await create_timer(1.0).timeout
	await shot("zeile_geheim")
	await create_timer(3.0).timeout
	pop(lena, true, ben)
	await create_timer(0.5).timeout
	await shot("pups_oben_nacht")
	await create_timer(3.0).timeout
	# beim Ziel (ich): groß über dem eigenen Namensschild
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		pop(me, true, kim)
		await create_timer(0.45).timeout
		await shot("ziel_" + tm)
		if tm == "tag":
			await create_timer(1.0).timeout
			await shot("ziel_zeile")
			await create_timer(2.5).timeout
		else:
			await create_timer(3.5).timeout
	# reduziert
	ts.table.set_night(0.0)
	ts.table.reduced = true
	pop(ben, true, kim)
	await create_timer(0.6).timeout
	await shot("reduziert")
	ts.table.reduced = false
	await create_timer(3.0).timeout
	# großer Modus
	clock += 200000
	ts.table.set_big(true)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.9).timeout
	tz.open_menu(kim)
	await create_timer(0.4).timeout
	await shot("gross_menue")
	tz.close_menu(false)
	pop(kim, true, me)
	await create_timer(0.45).timeout
	await shot("gross_pups_tag")
	await create_timer(3.0).timeout
	ts.table.set_night(1.0)
	pop(me, false)
	await create_timer(0.45).timeout
	await shot("gross_pups_nacht")
	await create_timer(3.0).timeout
	ts.table.set_night(0.0)
	ts.table.set_big(false)
	await process_frame
	ts._layout()
	# Schrift „Sehr groß“
	UiFonts.set_level("sehr_gross", root)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.6).timeout
	tz.open_menu(kim)
	await create_timer(0.4).timeout
	await shot("sehr_gross")
	tz.close_menu(false)
	UiFonts.set_level("normal", root)
	await process_frame
	ts._layout()
	# Englisch
	I18n.set_language("en")
	show(kim)
	await create_timer(0.5).timeout
	tz.open_menu(kim)
	await create_timer(0.3).timeout
	await shot("en_menue")
	tz.close_menu(false)
	pop(lena, true, kim)
	await create_timer(0.45).timeout
	await shot("en_pups")
	await create_timer(1.0).timeout
	await shot("en_zeile")


# Beta 1.6.7: „Erwischt!“-Buzzer und Necken-Menü, das bei Zugwechsel und Erwischbarkeit offen bleibt
func catchable(seats: Array) -> void:
	for p in fake.v.players:
		if seats.has(int(p.seat)):
			p["count"] = 1
			var backs: Array = p.get("backs", [])
			if backs.size() > 1:
				p["backs"] = [backs[0]]
	var h: Dictionary = fake.v.get("hints", {})
	h["catch"] = seats.duplicate()
	fake.v["hints"] = h


func run_167(me: int, kim: int) -> void:
	var lena := 2
	var ben := 3 if me != 3 else 0
	catchable([kim])
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(ben)
		await create_timer(0.6).timeout
		await shot("buzzer_" + tm)
	catchable([kim, lena])
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(ben)
		await create_timer(0.6).timeout
		await shot("zwei_" + tm)
	# Menü an Ben offen, dann wird Kim erwischbar
	ts.table.set_night(0.0)
	catchable([])
	show(ben)
	clock += 20000
	await create_timer(0.3).timeout
	tz.open_menu(ben)
	await create_timer(0.3).timeout
	catchable([kim])
	show(ben)
	await create_timer(0.5).timeout
	await shot("menue_buzzer")
	# erzwungen: Menü über Kims Buzzer
	var cr := tz.catch_rect_of(kim, tz.menu.get_parent(), 0.0)
	tz.menu.position = cr.position + Vector2(-40.0, -30.0)
	tz.tick(0.02)
	await create_timer(0.3).timeout
	await shot("menue_ueber_buzzer")
	tz.close_menu(false)
	# Zugwechsel bei offenem Menü an Kim (ab 10 s Schnarchen/Wecker aktiv, dann kommt Ben dran)
	catchable([])
	show(kim)
	clock += 20000
	await create_timer(0.3).timeout
	tz.open_menu(kim)
	tz.tick(0.2)
	await create_timer(0.3).timeout
	await shot("menue_vor_zugwechsel")
	show(ben)
	tz.tick(0.2)
	await create_timer(0.3).timeout
	await shot("menue_zugwechsel")
	tz.close_menu(false)
	# großer Modus
	ts.table.set_big(true)
	await process_frame
	ts._layout()
	catchable([kim])
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(ben)
		await create_timer(0.9).timeout
		await shot("gross_" + tm)
	catchable([kim, lena])
	show(ben)
	await create_timer(0.9).timeout
	await shot("gross_zwei")
	# Schrift „Sehr groß“: großer Modus mit Menü, dann normal
	UiFonts.set_level("sehr_gross", root)
	await process_frame
	ts._layout()
	catchable([kim])
	show(ben)
	await create_timer(0.9).timeout
	tz.open_menu(ben)
	await create_timer(0.4).timeout
	await shot("gross_sehr_gross")
	tz.close_menu(false)
	ts.table.set_night(0.0)
	ts.table.set_big(false)
	await process_frame
	ts._layout()
	show(ben)
	await create_timer(0.8).timeout
	tz.open_menu(ben)
	await create_timer(0.4).timeout
	await shot("sehr_gross")
	tz.close_menu(false)
	UiFonts.set_level("normal", root)
	await process_frame
	ts._layout()
	# reduziert
	ts.table.reduced = true
	show(ben)
	await create_timer(0.5).timeout
	await shot("reduziert")
	ts.table.reduced = false
	# Englisch
	I18n.set_language("en")
	show(ben)
	await create_timer(0.5).timeout
	await shot("en_buzzer")


# Beta 1.6.10: Furzkissen als zwei runde Knöpfe „Kissen geheim“ (?-Abzeichen) und „Kissen mit Namen“ (Namensschild)
func zoom_menu(file: String) -> void:
	for i in 3:
		await process_frame
	var img := root.get_texture().get_image()
	var sc := img.get_width() / 1600.0
	var r := Rect2i(Rect2(tz.menu.get_global_rect().grow(16.0).position * sc, tz.menu.get_global_rect().grow(16.0).size * sc)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var part := img.get_region(r)
	part.resize(part.get_width() * 2, part.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	part.save_png(out.path_join("optik_%s_%s.png" % [serie, file]))
	print("Bild: optik_%s_%s.png" % [serie, file])


func run_1610(me: int, kim: int) -> void:
	var lena := 2
	# Mensch am Zug (ab 10 s): Reihe 1 Kugel/Schnarchen/Wecker/Karten, Reihe 2 die beiden Kissen
	for tm in ["tag", "nacht"]:
		clock += 20000
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(kim)
		await create_timer(0.4).timeout
		tz.close_menu(false)
		tz.open_menu(kim)
		await create_timer(0.3).timeout
		await shot("menue_" + tm)
		await zoom_menu("zoom_" + tm)
	tz.close_menu(false)
	# Computergegner (Lena): eine Reihe Kugel, Kissen, Kissen, Karten
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		show(kim)
		await create_timer(0.3).timeout
		tz.open_menu(lena)
		await create_timer(0.3).timeout
		await shot("bot_" + tm)
		tz.close_menu(false)
	# ausgegraut: eigenes Kissen gerade gelegt (Sperre), dazu Kim nicht am Zug
	ts.table.set_night(0.0)
	placed(me, lena, true)
	await create_timer(0.3).timeout
	show(lena)
	tz.open_menu(kim)
	await create_timer(0.3).timeout
	await shot("ausgegraut")
	await zoom_menu("zoom_ausgegraut")
	tz.close_menu(false)
	ts.table.set_night(1.0)
	tz.open_menu(kim)
	await create_timer(0.3).timeout
	await shot("ausgegraut_nacht")
	tz.close_menu(false)
	clock += 400000
	# großer Modus
	ts.table.set_night(0.0)
	ts.table.set_big(true)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.9).timeout
	for tm in ["tag", "nacht"]:
		ts.table.set_night(1.0 if tm == "nacht" else 0.0)
		tz.close_menu(false)
		tz.open_menu(kim)
		await create_timer(0.4).timeout
		await shot("gross_" + tm)
	tz.close_menu(false)
	# Schrift „Sehr groß“ im großen Modus und normal
	UiFonts.set_level("sehr_gross", root)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.9).timeout
	tz.open_menu(kim)
	await create_timer(0.4).timeout
	await shot("gross_sehr_gross")
	tz.close_menu(false)
	ts.table.set_night(0.0)
	ts.table.set_big(false)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.8).timeout
	var who := {kim: "kim", lena: "lena_bot", (3 if me != 3 else 0): "ben"}
	for s in who:
		tz.open_menu(s)
		await create_timer(0.4).timeout
		await shot("sehr_gross_" + str(who[s]))
		tz.close_menu(false)
	UiFonts.set_level("gross", root)
	await process_frame
	ts._layout()
	show(kim)
	await create_timer(0.6).timeout
	tz.open_menu(kim)
	await create_timer(0.4).timeout
	await shot("schrift_gross")
	tz.close_menu(false)
	UiFonts.set_level("normal", root)
	await process_frame
	ts._layout()
	# Englisch
	I18n.set_language("en")
	show(kim)
	await create_timer(0.5).timeout
	tz.open_menu(kim)
	await create_timer(0.3).timeout
	await shot("en_menue")
	tz.close_menu(false)
	tz.open_menu(lena)
	await create_timer(0.3).timeout
	await shot("en_bot")
	tz.close_menu(false)
