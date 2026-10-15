extends SceneTree
# Mau-Mau Flip (Beta 1.6.2, Gastgeber-Übergabe im WLAN): Doubles für die Oberflächentests test_ui_handover_wlan.gd und
# test_ui_handover_wlan_shot.gd (beide erben von hier, damit der Hauptschleife kein vorgeladenes Skript bis zum Ende Klassen festhält)
# – ohne Server, ohne Suche, ohne Android (kein test_*, wird von tools/build.ps1 nicht gestartet).
#   FakeHost   HostTable mit einer nie geöffneten NetHostSession (Spieler von Hand), echter MauGame-Partie und seat_assign als Zähler
#   FakeWatch  GameWifiWatch-Ersatz (state, address, auto_open, close, Signale lost/auto_done)
#   FakeSwitch HostSwitch mit resume_new_room als Zähler (sonst entstünde ein echter Gastgeber-Tisch samt Server)
#   RecNav     ScreenNav, der push/replace/home bei record = true nur mitschreibt (die Beitrittsseite startete sonst die Suche)

const GID := "ab12cd34ef567890"


class FakeHost:
	extends HostTable
	var assigned: Array = []

	func seat_assign(waiting_id: int, seat: int) -> bool:
		assigned.append([waiting_id, seat])
		return true


class FakeWatch:
	extends Node
	signal changed
	signal lost(what: String)
	signal auto_done(ok: bool, error: String)
	var host: Object
	var state := {"status": "off"}
	var address := ""
	var hint := ""
	var auto_state := ""
	var auto_error := ""
	var auto_tries := 0
	var foreign_ap := false
	var opened := 0
	var closed := 0

	func auto_open() -> String:
		opened += 1
		auto_state = "running"
		return ""

	func close() -> void:
		closed += 1


class FakeSwitch:
	extends HostSwitch
	var new_rooms := 0

	func resume_new_room() -> bool:
		new_rooms += 1
		return true


class RecNav:
	extends ScreenNav
	var record := false
	var log: Array = []

	func push(screen: AppScreen, animate := true) -> AppScreen:
		if record:
			log.append(["push", screen])
			return screen
		return super(screen, animate)

	func replace(screen: AppScreen, animate := true) -> AppScreen:
		if record:
			log.append(["replace", screen])
			return screen
		return super(screen, animate)

	func home(animate := true) -> void:
		if record:
			log.append(["home"])
			return
		super(animate)

	# mitgeschriebene Bildschirme freigeben
	func drop_log() -> void:
		for e in log:
			if e.size() > 1 and is_instance_valid(e[1]) and (e[1] as Node).get_parent() == null:
				(e[1] as Node).free()
		log.clear()


# Gastgeber Du (Platz 0) im eigenen Spiel-WLAN; Lena (App, verbunden, kann ein Spiel-WLAN öffnen, Erlaubnis fehlt), Ben (Browser,
# getrennt), Minka (Computer); Kim (Browser) wartet auf einen Platz.
static func make_host(ap := true) -> FakeHost:
	var ht := FakeHost.new()
	ht.auto_process = false
	ht.autosave = false
	ht.backup_enabled = false
	ht.use_discovery = false
	var s := NetHostSession.new()
	s.host_id = 1
	s.players = {
		1: {"id": 1, "name": "Du", "kind": "app", "token": "", "connected": true, "ready": true, "seat": 0, "conn": -1, "local": true, "address": ""},
		2: {"id": 2, "name": "Lena", "kind": "app", "token": "t1", "connected": true, "ready": true, "seat": 1, "conn": 3, "local": false,
			"address": "192.168.49.23", "online": false, "bk": [1, "a1b2c3d4", 5], "ap": {"ok": true, "perm": false}},
		3: {"id": 3, "name": "Ben", "kind": "web", "token": "t2", "connected": false, "ready": true, "seat": 2, "conn": -1, "local": false,
			"address": ""},
		4: {"id": 4, "name": "Minka", "kind": "bot", "token": "", "connected": true, "ready": true, "seat": 3, "conn": -1, "local": true, "address": ""},
		5: {"id": 5, "name": "Kim", "kind": "web", "token": "t5", "connected": true, "ready": true, "seat": -1, "conn": 4, "local": false,
			"address": "192.168.49.40", "waiting": true}}
	ht.session = s
	ht.add_child(s)
	ht._seat_ids = [1, 2, 3, 4]
	ht._create_game(RuleConfig.preset("familie"), [
		{"name": "Du", "kind": "human", "host": true, "id": 1, "net": "app", "token": "t0"},
		{"name": "Lena", "kind": "human", "id": 2, "net": "app", "token": "t1", "link": "wlan"},
		{"name": "Ben", "kind": "human", "id": 3, "net": "web", "token": "t2", "link": "wlan"},
		{"name": "Minka", "kind": "bot", "id": 4, "net": "bot", "token": ""}], 7)
	ht.game.set_connected(2, false)
	ht.game.start_round()
	ht.gid = GID
	ht.gen = 1
	ht.epoch = "a1b2c3d4"
	ht.set("_ap", ap)
	ht.set("_ap_seat", 0 if ap else -1)
	ht._last_view = ht.view_of(ht.host_seat)
	return ht


# Sicherung eines App-Gasts (Lena, Platz 1) einer Partie im Spiel-WLAN von ap_seat; Gastgeber Hanna (Platz 0), Erben Anna, Lena.
static func guest_backup(game_dict: Dictionary, ap_seat: int, now: int, online := false) -> Dictionary:
	var seats := [{"name": "Hanna", "kind": "human", "host": true, "net": "app", "token": "t0", "link": "wlan"},
		{"name": "Lena", "kind": "human", "host": false, "net": "app", "token": "t1", "link": "wlan"},
		{"name": "Ben", "kind": "human", "host": false, "net": "web", "token": "t2", "link": "wlan"},
		{"name": "Anna", "kind": "human", "host": false, "net": "app", "token": "t3", "link": "wlan"},
		{"name": "Minka", "kind": "bot", "host": false, "net": "bot", "token": ""}]
	var extra := {"gid": GID, "gen": 2, "epoch": "b2c3d4e5", "seq": 9, "heirs": ["t3", "t1"],
		"wlan": {"port": 24690, "addrs": ["192.168.49.1"], "ap": true, "ap_seat": ap_seat, "past": []}}
	if online:
		extra["online"] = {"relay": "wss://vermittler.test", "room": "KATZE-42", "token": "r", "conns": [1], "max_c": 1, "created_unix": now - 90000}
	var d := MatchSnapshot.clean(MatchSnapshot.make(game_dict, seats, 0, extra, now - 60, "guest"))
	d["my_seat"] = 1
	return d


# Partie für die Sicherungen (vier Menschen und ein Computer, laufende Runde)
static func game_dict() -> Dictionary:
	var seats := [{"name": "Hanna", "kind": "human"}, {"name": "Lena", "kind": "human"}, {"name": "Ben", "kind": "human"},
		{"name": "Anna", "kind": "human"}, {"name": "Minka", "kind": "bot"}]
	var g := MauGame.create(RuleConfig.preset("familie"), seats, 11)
	g.start_round()
	return g.to_dict()


# App-Gast-Tisch ohne Verbindung mit dieser Sicherung
static func guest_table(backup: Dictionary) -> ClientTable:
	var ct := GameStarter.client()
	ct.auto_process = false
	ct.persist_backup = false
	ct.persist_tokens = false
	ct.backup = backup
	return ct
