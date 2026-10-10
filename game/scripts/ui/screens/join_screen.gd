class_name JoinScreen
extends AppScreen
# Beitreten (ClientTable, Modul G): oben das Adressfeld (die Bildschirmtastatur deckt im Querformat die untere Hälfte),
# darunter die im WLAN gefundenen Spiele (NetDiscovery) mit Name und Spielerzahl. Nach dem Verbinden zeigt dieselbe Seite die
# Lobby des Gastgebers (Spieler, Regeln, „Warte auf den Gastgeber …“); beginnt die Partie, kommt der Tisch.
# Über dem Regeltext steht fett die Voreinstellung mit Kartenzahl und den Hausregeln mit Zusatzkarten, damit Gäste sie sehen,
# ohne zu blättern.
# Regeln des Gastgebers: Die Lobby merkt sie sich noch nicht – erst der Tisch, sobald gespielt wird („Zuletzt gespielt bei
# <Gastgeber>“, RuleSets.remember_host in TableScreen). So überschreibt bloßes Beitreten den Platz nicht (Prüfung 06.10.2026). Der
# Hinweis über den Knöpfen sagt, wo die Regeln später stehen. Der Regelkopf nennt die Regeln aus Sicht des Gastes: Voreinstellung,
# sonst der Name eines passenden eigenen Satzes, sonst „Regeln von Lena“. „Regeln speichern“ neben „Bereit“ legt sie als eigenen
# Satz ab (Vorschlag „Regeln von <Gastgeber>“); entsprechen sie schon einem Satz, heißt der Knopf „Gespeichert“. Ändert der
# Gastgeber die Regeln, während der Speichern-Dialog offen ist, speichert er die neuen; beginnt die Partie, wandert der Dialog
# samt getipptem Namen an den Tisch (TableScreen.adopt_save_box). „Bereit“ zeigt nur im bereiten Zustand einen Haken („Bereit ✓“).
# „Bereit“ folgt dem eigenen Stand in der Lobby: Ändert der Gastgeber die Regeln, setzt er alle Gäste zurück (Nachtest 1, N4).
# Zum Tisch geht es mit „start“ oder mit dem ersten Spielstand: Wer mitten in der Partie mit seinem Token zurückkommt (App neu
# gestartet), bekommt kein „start“, nur den Stand (Nachtest 1, Nachbesserung; der Browser-Client macht es genauso).
# with_client(): Der Tisch eines App-Gasts gibt seine Verbindung hierher zurück, wenn dort eine Lobby ankommt (der Gastgeber hat eine
# neue Runde eröffnet, während der Gast neu verbunden hat) – sonst bliebe der alte Tisch stehen.
# Online (docs/online/ENTWURF.md 3): Zeile „Online:“ mit Raumcode und „Beitreten“; der Vermittler kommt aus den Einstellungen bzw.
# aus dem App-Link (direct_room). Vor dem Verbinden fragt die Seite /info?room=CODE (Raum unbekannt, andere Version); Ziel des
# ClientTable ist dann der Raum-Link („https://<vermittler>/?r=CODE“, Port 0), den NetClient erkennt.

var client: ClientTable
var discovery: NetDiscovery
var _address: LineEdit
var _connect_btn: Button
var _status: Label
var _games: VBoxContainer
var _search_box: Control
var _lobby_box: Control
var _lobby_list: VBoxContainer
var _lobby_head: Label
var _lobby_rules: Label
var _lobby_hint: Label
var _ready_btn: Button
var _save_btn: Button
var _save_box: RuleSetSaveBox
var _started := false
var _status_hold := false             # Ablehnung/Ende steht im Status, bis der Nutzer etwas tut (die Suche überschreibt sie nicht)
var host_rules: RuleConfig          # Regeln der letzten Lobby-Nachricht (null = noch keine)
var host_name := ""                 # Name des Gastgebers aus der Lobby
var _adopted: ClientTable           # with_client(): bestehende Verbindung, wird in build() übernommen
var direct := {}                    # App-Link (direct_to): {address, port} – ohne Suche verbinden
var _name_box: Control              # App-Link ohne gespeicherten Namen: erst nach dem Namen fragen
var _name_edit: LineEdit
var _room: LineEdit                 # Online: Raumcode
var _online_row: Control            # Zeile „Online:“ (nur ohne Lobby sichtbar)
var _room_btn: Button
var _room_check: HTTPRequest        # /info?room= vor dem Beitreten
var _pending_room := {}             # {room, relay} während der Prüfung


# Lobby mit einer bestehenden Verbindung (vom Tisch zurück); zeigt sofort deren letzte Lobby.
static func with_client(ct: ClientTable) -> JoinScreen:
	var s := JoinScreen.new()
	s._adopted = ct
	return s


# App-Link „In der App spielen“ (Beta 1.0.2): direkt zu diesem Gastgeber, ohne Suche. Fehlt der eigene Name, fragt die Seite
# zuerst danach.
static func direct_to(address: String, port: int) -> JoinScreen:
	var s := JoinScreen.new()
	s.direct = {"address": address, "port": port}
	return s


# Online-Link (maumauflip://join?r=…&v=…): direkt in diesen Raum; relay "" = Vermittler aus den Einstellungen.
static func direct_room(room: String, relay: String) -> JoinScreen:
	var s := JoinScreen.new()
	s.direct = {"room": room, "relay": relay}
	return s


# Link aus App.take_pending_link() ({ok, address, port, error}, NetAndroid.parse_app_link) auf dem Bildschirmstapel ausführen.
# Ungültig → freundlicher Hinweis. Läuft eine Partie oder Lobby, fragt die App erst. Ist man schon mit genau diesem Spiel verbunden,
# bleibt alles, wie es ist.
static func handle_link(nav: ScreenNav, link: Dictionary) -> void:
	if nav == null or link.is_empty():
		return
	if not bool(link.get("ok", false)):
		nav.toast(str(link.get("error", "Der Link zum Spiel ist unvollständig.")))
		return
	var address := str(link.address)
	var port := int(link.port)
	if str(link.get("room", "")) != "":
		# Online-Link: Vermittler aus dem Link, sonst aus den Einstellungen; als Ziel gilt der Raum-Link
		var relay := str(link.get("relay", ""))
		if relay == "":
			relay = NetProtocol.effective_relay(str(UiApp.setting("vermittler", "")))
		if relay == "":
			nav.toast("Für Online-Spiele fehlt die Vermittler-Adresse – bitte in den Einstellungen unter „Für Fortgeschrittene“ eintragen.")
			return
		address = NetProtocol.room_link(relay, str(link.room))
		port = 0
	var busy := false
	for s in nav.stack:
		var ct: Object = null
		if s is JoinScreen and (s as JoinScreen).client != null:
			ct = (s as JoinScreen).client
		elif s is TableScreen and not (s as TableScreen).leaving:
			ct = (s as TableScreen).source
		elif s is HostLobbyScreen:
			busy = true
			continue
		else:
			continue
		if ct is ClientTable and same_game(ct as ClientTable, address, port):
			nav.toast("Du bist schon in diesem Spiel.")
			return
		busy = true
	if not busy:
		_open_direct(nav, address, port)
		return
	var top := nav.top()
	var box := ConfirmBox.ask(top if top != null else nav, "Anderem Spiel beitreten?",
		"Du bist gerade in einem Spiel. Wenn du wechselst, verlässt du es.", "Wechseln", "Bleiben")
	box.name = "AppLinkFrage"
	box.answered.connect(func(yes: bool) -> void:
		if yes and is_instance_valid(nav):
			for s in nav.stack:
				if s is TableScreen and (s as TableScreen).source != null and not (s as TableScreen).leaving:
					(s as TableScreen).leaving = true
					(s as TableScreen).source.leave()
			_open_direct(nav, address, port))


static func _open_direct(nav: ScreenNav, address: String, port: int) -> void:
	nav.home(false)
	nav.push(WlanScreen.new(), false)
	var target := NetProtocol.parse_room_link(address)
	nav.push(JoinScreen.direct_room(str(target.room), str(target.relay)) if not target.is_empty() else JoinScreen.direct_to(address, port))


# Verbindung ct gehört zu genau diesem Gastgeber und ist nicht beendet
static func same_game(ct: ClientTable, address: String, port: int) -> bool:
	return ct.address == address and ct.port == port and not ct.connection_state() in ["closed", "rejected", "ended"]


func build() -> void:
	var content := page("Beitreten")
	var top := ScreenKit.hbox(14)
	content.add_child(top)
	_address = LineEdit.new()
	_address.name = "Adresse"
	_address.placeholder_text = "Adresse des Gastgebers, z. B. 192.168.178.8"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	_address.text = str(UiApp.setting("letzte_adresse", ""))
	_address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_address.text_submitted.connect(func(_t: String) -> void: _connect_typed())
	top.add_child(_address)
	_connect_btn = ScreenKit.button("Verbinden", "PrimaryButton", "start")
	_connect_btn.name = "Verbinden"
	_connect_btn.pressed.connect(_connect_typed)
	top.add_child(_connect_btn)
	# Online (docs/online/ENTWURF.md 3): Raumcode des Gastgebers, Vermittler aus den Einstellungen bzw. aus dem Link
	var online := ScreenKit.hbox(14)
	online.name = "OnlineZeile"
	_online_row = online
	content.add_child(online)
	var ol := ScreenKit.label("Online:", "", UiFonts.size("text"))
	ol.add_theme_font_override("font", UiFonts.text(700))
	ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	online.add_child(ol)
	_room = LineEdit.new()
	_room.name = "Raumcode"
	_room.placeholder_text = "Raumcode, z. B. KATZE-42"
	_room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	_room.max_length = 24
	_room.clear_button_enabled = true
	_room.text = str(last_room().get("room", ""))   # Beta 1.3.3: letzter Raumcode bleibt stehen (auch nach Neustart, Spielende, „nicht gefunden“)
	_room.text_changed.connect(_on_room_text)
	_room.text_submitted.connect(func(_t: String) -> void: join_typed_room())
	online.add_child(_room)
	_room_btn = ScreenKit.button("Beitreten", "PrimaryButton", "start")
	_room_btn.name = "RaumBeitreten"
	_room_btn.pressed.connect(join_typed_room)
	online.add_child(_room_btn)
	_status = ScreenKit.label("Suche Spiele im WLAN …", "HintLabel", UiFonts.size("text"))
	_status.name = "Status"
	content.add_child(_status)
	# Suche
	var search := ScreenKit.card(24.0)
	search.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search_box = search
	content.add_child(search)
	var sv := ScreenKit.vbox(10)
	search.add_child(sv)
	sv.add_child(ScreenKit.heading("Gefundene Spiele", UiFonts.size("zwischen")))
	var scroll := ScreenKit.scroller()
	sv.add_child(scroll)
	_games = ScreenKit.vbox(10)
	_games.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_games)
	# Lobby nach dem Verbinden
	var lobby := ScreenKit.card(24.0)
	lobby.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby.visible = false
	_lobby_box = lobby
	content.add_child(lobby)
	var lv := ScreenKit.hbox(26)
	lobby.add_child(lv)
	var lleft := ScreenKit.vbox(8)
	lleft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(lleft)
	lleft.add_child(ScreenKit.heading("Am Tisch", UiFonts.size("zwischen")))
	var lscroll := ScreenKit.scroller()
	lleft.add_child(lscroll)
	_lobby_list = ScreenKit.vbox(4)             # 5 Spieler passen bei 1600 × 720 ganz hinein, weitere per Wischen
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(_lobby_list)
	var lright := ScreenKit.vbox(14)
	lright.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(lright)
	lright.add_child(ScreenKit.heading("Regeln dieser Partie", UiFonts.size("zwischen")))
	_lobby_head = ScreenKit.text_block("", UiFonts.size("text"))
	_lobby_head.name = "RegelnKopf"
	_lobby_head.add_theme_font_override("font", UiFonts.text(800))
	lright.add_child(_lobby_head)
	# Der Regeltext blättert für sich; „Bereit“ steht immer darunter (Gerätetest 0.1.1, N1: lange Regeln schoben den Knopf hinaus)
	var rscroll := ScreenKit.scroller()
	rscroll.name = "RegelnBildlauf"
	lright.add_child(rscroll)
	_lobby_rules = ScreenKit.text_block("", UiFonts.size("text"))
	_lobby_rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(_lobby_rules)
	_lobby_hint = ScreenKit.hint(lobby_hint(""), UiFonts.size("hinweis"))
	_lobby_hint.name = "Hinweis"
	lright.add_child(_lobby_hint)
	var brow := ScreenKit.hbox(14)
	lright.add_child(brow)
	_save_btn = ScreenKit.button("Regeln speichern", "GhostButton", "regeln")
	_save_btn.name = "RegelnSpeichern"
	_save_btn.tooltip_text = "Diese Regeln als eigenen Satz speichern"
	_save_btn.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_save_btn.pressed.connect(save_rules)
	brow.add_child(_save_btn)
	_ready_btn = ScreenKit.button("Bereit", "PrimaryButton")
	_ready_btn.name = "Bereit"
	_ready_btn.toggle_mode = true
	_ready_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_btn.toggled.connect(func(on: bool) -> void:
		if client != null:
			client.set_ready(on)
		_ready_btn.text = I18n.t("Bereit ✓") if on else I18n.t("Bereit"))
	brow.add_child(_ready_btn)
	_refresh_save_btn()
	if _adopted != null and is_instance_valid(_adopted):
		_adopt(_adopted)
		_adopted = null
		return
	if not direct.is_empty():
		_start_direct()
		return
	_start_search()
	_refresh_games()


# App-Link: Adresse eintragen und ohne Suche verbinden; ohne gespeicherten Namen erst danach fragen
func _start_direct() -> void:
	_search_box.visible = false
	if direct.has("room"):
		_room.text = str(direct.room)
	else:
		_address.text = "%s:%d" % [str(direct.address), int(direct.port)]
	if AppSettings.clean_name(str(UiApp.setting("name", ""))) == "":
		_status.text = "Fast geschafft – wie heißt du?"
		_show_name_box()
		return
	_join_direct()


func _join_direct() -> void:
	if direct.has("room"):
		join_room(str(direct.room), str(direct.relay))
	else:
		join(str(direct.address), int(direct.port))


# Zuletzt benutzter Raum {room, relay} aus den Einstellungen ({} = keiner); relay "" = Vermittler aus den Einstellungen.
static func last_room() -> Dictionary:
	var v: Variant = AppSettings.clean_last_room(UiApp.setting("letzter_raum", {}))
	return v if v is Dictionary else {}


func _remember_room(code: String, relay: String) -> void:
	var app := UiApp.app()
	if app != null and app.settings != null:
		var entry := {"room": code, "relay": relay}
		if AppSettings.clean_last_room(entry) != last_room():
			app.settings.set_value("letzter_raum", entry)


func _on_room_text(text: String) -> void:
	# Feld geleert (z. B. mit dem ×): gemerkten Raum vergessen.
	if text.strip_edges() == "":
		var app := UiApp.app()
		if app != null and app.settings != null:
			app.settings.reset("letzter_raum")


# Eingetippter Raumcode (Vermittler aus den Einstellungen bzw. der gemerkte Vermittler dieses Raums)
func join_typed_room() -> void:
	_room.release_focus()
	var last := last_room()
	var relay := ""
	if not last.is_empty() and NetProtocol.normalize_room_code(_room.text) == str(last.room):
		relay = str(last.relay)
	join_room(_room.text, relay)


# Online beitreten: Code prüfen, beim Vermittler nachfragen (/info?room=), dann verbinden. relay "" = aus den Einstellungen;
# kommt der Vermittler aus einem Link und ist die eigene Einstellung leer, wird er gespeichert.
func join_room(code_text: String, relay: String) -> void:
	_status_hold = false
	var code := NetProtocol.normalize_room_code(code_text)
	if code == "":
		toast("Bitte den Raumcode eingeben, z. B. KATZE-42.")
		return
	_room.text = code
	var own := NetProtocol.effective_relay(str(UiApp.setting("vermittler", "")))
	var url := NetProtocol.normalize_relay_url(relay) if relay != "" else own
	if url == "":
		_status.text = I18n.t("Für Online-Spiele fehlt die Vermittler-Adresse – bitte in den Einstellungen unter „Für Fortgeschrittene“ eintragen.")
		return
	if own == "" and relay != "":
		var app := UiApp.app()
		if app != null:
			app.settings.set_value("vermittler", url)
	_remember_room(code, url)
	_status.text = I18n.t("Suche Raum %s …") % code
	_pending_room = {"room": code, "relay": url}
	if _room_check == null:
		_room_check = HTTPRequest.new()
		_room_check.name = "RaumPruefung"
		_room_check.timeout = 8.0
		add_child(_room_check)
		_room_check.request_completed.connect(_on_room_checked)
	_room_check.cancel_request()
	NetAddresses.hold_unbound(_check_hold(), 10000)   # Android: Anfrage ins Internet, nicht ins Spiel-WLAN
	if _room_check.request(url + "/info?room=" + code) != OK:
		_on_room_checked(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _check_hold() -> String:
	return "room_check:%d" % get_instance_id()


func _on_room_checked(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	NetAddresses.release_hold(_check_hold())
	if _pending_room.is_empty():
		return
	var target := _pending_room
	_pending_room = {}
	var room_text := str(target.room)
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		# Vermittler nicht erreichbar oder ohne /info: trotzdem versuchen (der Client meldet sich mit Klartext)
		join(NetProtocol.room_link(str(target.relay), room_text), 0)
		return
	var info: Variant = JSON.parse_string(body.get_string_from_utf8())
	var room: Variant = info.get("room") if info is Dictionary else null
	if room is Dictionary and not bool(room.get("open", false)):
		_status.text = I18n.t("Raum nicht gefunden. Prüf den Code – oder lass dir am besten den Link schicken.")
		return
	if room is Dictionary and str(room.get("version", "")) != "" and str(room.version) != NetProtocol.game_version():
		_status.text = I18n.t("Der Gastgeber spielt mit Version %s, du mit %s. Bitte beide auf dieselbe Version bringen.") % [str(room.version), NetProtocol.game_version()]
		return
	join(NetProtocol.room_link(str(target.relay), room_text), 0)


func _show_name_box() -> void:
	var card := ScreenKit.card(24.0)
	card.name = "NameFrage"
	_name_box = card
	_search_box.get_parent().add_child(card)
	var v := ScreenKit.vbox(14)
	card.add_child(v)
	v.add_child(ScreenKit.heading("Dein Name", UiFonts.size("zwischen")))
	v.add_child(ScreenKit.text_block("So sehen dich die anderen am Tisch.", UiFonts.size("text")))
	var row := ScreenKit.hbox(14)
	v.add_child(row)
	_name_edit = LineEdit.new()
	_name_edit.name = "Name"
	_name_edit.placeholder_text = "Dein Name"
	_name_edit.max_length = AppSettings.NAME_MAX
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, ScreenKit.TOUCH)
	_name_edit.add_theme_font_size_override("font_size", UiFonts.size("text"))
	_name_edit.text_submitted.connect(func(_t: String) -> void: confirm_name())
	row.add_child(_name_edit)
	var go := ScreenKit.button("Beitreten", "PrimaryButton", "start")
	go.name = "NameBeitreten"
	go.pressed.connect(confirm_name)
	row.add_child(go)
	_name_edit.call_deferred("grab_focus")


# Name aus der Namensfrage übernehmen, speichern und verbinden
func confirm_name() -> void:
	if _name_edit == null:
		return
	var n := AppSettings.clean_name(_name_edit.text)
	if n == "":
		toast("Bitte gib deinen Namen ein.")
		return
	_name_edit.release_focus()
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object:
		(st as Object).call("set_value", "name", n)
	_name_box.queue_free()
	_name_box = null
	_name_edit = null
	_join_direct()


# Bestehende Verbindung übernehmen (with_client): Lobby zeigen, ohne neu zu verbinden
func _adopt(ct: ClientTable) -> void:
	client = ct
	if ct.get_parent() == null:
		add_child(ct)
	elif ct.get_parent() != self:
		ct.reparent(self)
	_wire(ct)
	_status.text = "Verbunden. Warte auf den Gastgeber …"
	_search_box.visible = false
	_lobby_box.visible = true
	_online_row.visible = false          # Platz für die Lobby (5 Spieler und „Bereit“ bei 1600 × 720)
	if not ct.lobby.is_empty():
		_on_lobby(ct.lobby)
	if ct.connection_state() in ["closed", "rejected"]:
		_back_to_search()


func _start_search() -> void:
	if discovery != null:
		return
	discovery = NetDiscovery.new()
	discovery.name = "Suche"
	add_child(discovery)
	discovery.games_changed.connect(_refresh_games)
	if discovery.start_search() != OK:
		_status.text = "Suche nicht möglich – Adresse oben eingeben."


func _stop_search() -> void:
	if discovery != null and is_instance_valid(discovery):
		discovery.stop()
		discovery.queue_free()
	discovery = null


func _refresh_games() -> void:
	if _games == null or client != null:
		return
	for c in _games.get_children():
		_games.remove_child(c)
		c.queue_free()
	var list: Array = discovery.games_list() if discovery != null else []
	if list.is_empty():
		_games.add_child(ScreenKit.hint("Noch nichts gefunden. Der Gastgeber tippt auf „Spiel eröffnen“; beide Geräte im selben WLAN. Klappt die Suche nicht, die Adresse unter dem QR-Code des Gastgebers oben eintippen.", UiFonts.size("text")))
		return
	if _status_hold:
		pass   # Grund der Ablehnung bzw. des Endes bleibt stehen (Gerätetest 1.4.2: nach < 1 s „1 Spiel gefunden“)
	elif list.size() == 1:
		_status.text = I18n.t("1 Spiel gefunden – antippen zum Beitreten.")
	else:
		_status.text = I18n.t("%d Spiele gefunden – antippen zum Beitreten.") % list.size()
	for g in list:
		_games.add_child(_game_button(g))


func _game_button(g: Dictionary) -> Control:
	var b := ScreenKit.button("", "" if bool(g.get("compatible", true)) else "GhostButton")
	b.custom_minimum_size = Vector2(0, 96)
	var inner := ScreenKit.hbox(18)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 26
	inner.offset_right = -26
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var name_text := str(g.get("name", "?"))
	inner.add_child(ScreenKit.avatar(0, name_text, "human", 56.0))
	var texts := ScreenKit.vbox(0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(texts)
	var t := ScreenKit.label(I18n.t("Spiel von %s") % name_text, "", UiFonts.size("zwischen"))
	t.add_theme_font_override("font", UiFonts.title(800, false, 50.0, 48.0))
	texts.add_child(t)
	var np := int(g.get("players", 0))
	var detail := "%s · %s" % [I18n.t("1 Spieler") if np == 1 else I18n.t("%d Spieler") % np, str(g.get("address", ""))]
	if bool(g.get("running", false)):
		detail += " · " + I18n.t("Partie läuft")
	if not bool(g.get("compatible", true)):
		detail += " · " + I18n.t("andere Version (%s)") % str(g.get("version", "?"))
	texts.add_child(ScreenKit.label(detail, "HintLabel", UiFonts.size("hinweis")))
	var addr := str(g.get("address", ""))
	var port := int(g.get("port", NetProtocol.PORT))
	b.pressed.connect(func() -> void: join(addr, port))
	return b


# Eingetippte Adresse: „192.168.1.5“, „192.168.1.5:24690“ oder „http://192.168.1.5:24690/“
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges().trim_prefix("http://").trim_prefix("https://")
	var slash := t.find("/")
	if slash >= 0:
		t = t.substr(0, slash)
	var port := NetProtocol.PORT
	var colon := t.rfind(":")
	if colon > 0 and t.substr(colon + 1).is_valid_int():
		port = int(t.substr(colon + 1))
		t = t.substr(0, colon)
	if t == "":
		return {}
	return {"address": t, "port": port}


func _connect_typed() -> void:
	_address.release_focus()
	var a := parse_address(_address.text)
	if a.is_empty():
		toast("Bitte die Adresse des Gastgebers eingeben.")
		return
	var app := UiApp.app()
	if app != null:
		app.settings.set_value("letzte_adresse", _address.text.strip_edges())
	join(str(a.address), int(a.port))


func join(address: String, port: int) -> void:
	_status_hold = false
	if client != null:
		client.leave()
		client.queue_free()
	client = GameStarter.client()
	add_child(client)
	_wire(client)
	var target := NetProtocol.parse_room_link(address)
	_status.text = I18n.t("Verbinde mit Raum %s …") % str(target.room) if not target.is_empty() else I18n.t("Verbinde mit %s …") % address
	var who := str(UiApp.setting("name", ""))
	if client.join(address, port, who) != OK:
		_status.text = "Verbindung nicht möglich."
		_back_to_search()


func _wire(ct: ClientTable) -> void:
	ct.connection_changed.connect(_on_connection)
	ct.lobby_changed.connect(_on_lobby)
	ct.game_started.connect(_on_started)
	ct.state_changed.connect(_on_client_state)
	ct.notice.connect(_on_client_notice)


func _on_client_notice(t: String) -> void:
	_status.text = t


# Spielstand ohne „start“ (zurück mitten in der Partie): ebenfalls zum Tisch
func _on_client_state(_events: Array, v: Dictionary) -> void:
	if not v.is_empty():
		_on_started(int(v.get("seat", -1)))


func _on_connection(state: String) -> void:
	match state:
		"open":
			_status.text = "Verbunden. Warte auf den Gastgeber …"
			_search_box.visible = false
			_lobby_box.visible = true
			_online_row.visible = false          # Platz für die Lobby (5 Spieler und „Bereit“ bei 1600 × 720)
			_stop_search()
		"connecting":
			# schon in der Lobby (Beta 1.3.3): klarer Hinweis statt nur „Verbinde …“
			_status.text = client.connection_hint() if client != null and _lobby_box.visible else "Verbinde …"
		"rejected", "closed":
			if not _started:
				# Grund behalten (z. B. „Der Gastgeber hat das Spiel beendet.“); sonst bliebe „Verbunden. Warte …“ stehen.
				# Eine Ablehnung schreibt ihren Text danach selbst (notice).
				var why := client.client.close_text if client != null and client.client != null else ""
				_status_hold = true      # bleibt stehen, bis der Nutzer handelt (Suche, games_changed überschreiben nicht)
				_back_to_search()
				if state == "closed":
					_status.text = why if why != "" else "Verbindung beendet."


func _back_to_search() -> void:
	if client != null:
		var c := client
		client = null
		c.leave()
		c.queue_free()
	_lobby_box.visible = false
	_online_row.visible = true
	_search_box.visible = true
	_show_ready(false)
	host_rules = null
	_refresh_save_btn()
	_start_search()
	_refresh_games()


func _on_lobby(l: Dictionary) -> void:
	for c in _lobby_list.get_children():
		_lobby_list.remove_child(c)
		c.queue_free()
	var players: Array = (l.get("players", []) as Array).duplicate()
	# Wartende (Beta 1.4.2, seat −1) hinter den Sitzenden
	var order := func(p: Dictionary) -> int: return 1000 if bool(p.get("waiting", false)) or int(p.get("seat", 0)) < 0 else int(p.get("seat", 0))
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(order.call(a)) < int(order.call(b)))
	var waiting := bool(l.get("waiting", false))
	var me := client.my_id if client != null else -1
	for p in players:
		if int((p as Dictionary).get("id", -2)) == me:
			_show_ready(bool((p as Dictionary).get("ready", false)))   # der Gastgeber entscheidet (N4)
	for i in players.size():
		var p: Dictionary = players[i]
		var row := ScreenKit.hbox(12)
		row.custom_minimum_size = Vector2(0, 58)
		var kind := str(p.get("kind", "app"))
		var av := ScreenKit.avatar(i, str(p.get("name", "?")), "bot" if kind == "bot" else "human", 46.0)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(av)
		var n := ScreenKit.label(str(p.get("name", "")) + (("  " + I18n.t("(du)")) if int(p.get("id", -2)) == me else ""), "", UiFonts.size("text"))
		n.add_theme_font_override("font", UiFonts.text(700))
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var tag: String = I18n.t({"app": "App", "web": "Browser", "bot": "Computer"}.get(kind, kind))
		if int(p.get("id", -1)) == int(l.get("host_id", -2)):
			tag = I18n.t("Gastgeber")
		if bool(p.get("waiting", false)):
			tag += " · " + I18n.t("wartet auf einen Platz")
		if bool(p.get("away", false)):
			tag += " · " + I18n.t("kurz in einer anderen App")
		elif not bool(p.get("connected", true)):
			tag += " · " + I18n.t("getrennt")
		elif bool(p.get("ready", false)):
			tag += " · " + I18n.t("bereit")
		var tl := ScreenKit.label(tag, "HintLabel", UiFonts.size("hinweis"))
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tl)
		_lobby_list.add_child(row)
	var rules: Variant = l.get("rules", {})
	var cfg := RuleSets.load_config(rules)
	var welcomed := client.client.host_name if client != null and client.client != null else ""
	host_name = RuleSets.host_name_in_lobby(l, welcomed if welcomed != "" else I18n.t("Gastgeber"))
	_lobby_rules.text = "\n".join(PackedStringArray(cfg.describe()))
	_lobby_hint.text = lobby_hint(host_name)
	if waiting:
		# mitten in der Partie auf der Warteliste: der Gastgeber holt einen gleich an den Tisch
		_lobby_hint.text = I18n.t("Du bist auf der Warteliste. Der Gastgeber holt dich gleich an den Tisch.")
		_status.text = I18n.t("Das Spiel läuft schon. Der Gastgeber kann dich dazuholen – bleib hier, du erscheinst bei ihm auf der Warteliste.")
	if _ready_btn != null:
		_ready_btn.visible = not waiting
	# Regeln des Gastgebers zum Speichern bereithalten (gemerkt werden sie erst am Tisch)
	if rules is Dictionary and not (rules as Dictionary).is_empty():
		host_rules = cfg
		if _save_box != null and is_instance_valid(_save_box):
			_save_box.update_rules(cfg)
	_refresh_save_btn()


# Knopf „Bereit“ ohne Rückmeldung an den Gastgeber stellen
func _show_ready(on: bool) -> void:
	if _ready_btn == null:
		return
	_ready_btn.set_pressed_no_signal(on)
	_ready_btn.text = I18n.t("Bereit ✓") if on else I18n.t("Bereit")


# „Regeln speichern“ bzw. „Gespeichert“, wenn die Regeln des Gastgebers schon einem eigenen Satz entsprechen. Dazu der Regelkopf
# (zeigt dann den Namen des Satzes).
func _refresh_save_btn() -> void:
	if _save_btn == null:
		return
	_save_btn.disabled = host_rules == null
	var saved := RuleSets.match_name(host_rules) if host_rules != null else ""
	_save_btn.text = I18n.t("Gespeichert") if saved != "" else I18n.t("Regeln speichern")
	_save_btn.tooltip_text = (I18n.t("Gespeichert als „%s“") % saved) if saved != "" else I18n.t("Diese Regeln als eigenen Satz speichern")
	if _lobby_head != null:
		_lobby_head.text = lobby_head(host_rules, host_name) if host_rules != null else ""


# Regeln des Gastgebers als eigenen Satz speichern (Vorschlag „Regeln von <Gastgeber>“ bzw. der vorhandene Satz)
func save_rules() -> void:
	if host_rules == null or (_save_box != null and is_instance_valid(_save_box)):
		return
	var suggestion := RuleSets.match_name(host_rules)
	if suggestion == "":
		suggestion = RuleSets.suggestion_for_host(host_name)
	_save_box = RuleSetSaveBox.ask(self, host_rules, suggestion, host_name)
	_save_box.saved.connect(_on_box_saved)
	_save_box.cancelled.connect(_on_box_cancelled)


func _on_box_saved(n: String) -> void:
	_save_box = null
	_refresh_save_btn()
	toast(I18n.t("Gespeichert: „%s“ – zu finden unter „Regeln“ bei „Gespeichert“.") % n)


func _on_box_cancelled() -> void:
	_save_box = null


# Hinweis über den Knöpfen: wo die Regeln des Gastgebers nach dem Spielen stehen
static func lobby_hint(host: String) -> String:
	var where := ("„%s“" % RuleSets.host_title(host)) if host != "" else "„" + I18n.t("Zuletzt gespielt bei …") + "“"
	return I18n.t("Der Gastgeber setzt die Plätze und startet. Beim Spielen merkt sich dein Gerät seine Regeln unter „Regeln“ als %s.") % where


# Kopfzeile der Regeln für Gäste: „Familie · 116 Karten · mit Kartentausch“; eigene Regeln des Gastgebers heißen nach einem
# passenden eigenen Satz („Oma-Regeln · …“), sonst „Regeln von Lena · 124 Karten · mit …“ (ohne Gastgeber: „Eigene Regeln“).
static func lobby_head(cfg: RuleConfig, host := "") -> String:
	var title := RulesBar.preset_title(cfg)
	if cfg.preset_name() == "":
		var saved := RuleSets.match_name(cfg)
		if saved != "":
			title = saved
		elif host != "":
			title = I18n.t("Regeln von %s") % host
	var t := I18n.t("%s · %d Karten") % [title, cfg.card_count()]
	var names := RulesBar.extra_names(cfg)
	if not names.is_empty():
		t += " · " + I18n.t("mit") + " " + RulesBar.join_and(names)
	return t


# Die Partie beginnt: ein offener Speichern-Dialog wandert samt getipptem Namen an den Tisch
func _on_started(_seat: int) -> void:
	if _started or client == null:
		return
	_started = true
	_stop_search()
	var box: RuleSetSaveBox = _save_box if _save_box != null and is_instance_valid(_save_box) and not _save_box.is_queued_for_deletion() else null
	_save_box = null
	if box != null:
		if box.saved.is_connected(_on_box_saved):
			box.saved.disconnect(_on_box_saved)
		if box.cancelled.is_connected(_on_box_cancelled):
			box.cancelled.disconnect(_on_box_cancelled)
	var ts := TableScreen.create(client)
	nav.replace(ts)
	if box != null:
		ts.adopt_save_box(box)


func on_back() -> bool:
	if _save_box != null and is_instance_valid(_save_box):
		_save_box.cancel()
		_save_box = null
		return true
	if client != null:
		_status_hold = false
		_back_to_search()
		return true
	return false


func on_leave() -> void:
	if nav != null and not nav.stack.has(self):
		_stop_search()
		if client != null and not _started:
			client.leave()
