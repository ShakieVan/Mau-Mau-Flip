class_name NetProtocol
extends RefCounted

# Netzprotokoll (docs/BETA1_PLAN.md Abschnitt 5): JSON-Textrahmen über WebSocket, Begrüßung mit Protokoll- und Spielversion,
# Nachrichtenprüfung je Typ, Namensfilter, Format der Suche (UDP) und Adressrechnung. Reine Daten und Rechnungen, kein Netz, keine
# Szene – alle Funktionen sind statisch und ohne geteilten Zustand, also auch aus dem Netz-Thread des Servers aufrufbar (auto_reply).
#
# Client → Host: hello {proto, game, name, kind, token?} · act {seq, a} · lobby_ready {ready} · ping {ts} · log {text}
# Host → Client: welcome {id, token, host_name} · reject {code, text} · lobby {rev, players, rules, host_id} · start {seat}
#                state {seq_ack?, events, view} · err {text} · pong {ts} · bye {text}
# Zahlen: JSON kennt nur float; decode() wandelt ganzzahlige Werte in int (Kennungen, Plätze, Zeitstempel in ms).

const PROTO := 1                          # Protokollversion: bei jeder inkompatiblen Änderung erhöhen
const GAME_ID := "mau-mau-flip"
const PORT := 24690                       # TCP: HTTP, APK und WebSocket auf einem Port
const PORT_LAST := 24699                  # Rückfall, falls belegt
const DISCOVERY_PORT := 24692             # UDP: Suche „MMF?“ (eigener Port-Raum, kein Konflikt mit TCP 24692)
const DISCOVERY_QUERY := "MMF?"
const DISCOVERY_MAGIC := "MMF"
const MAX_DISCOVERY_BYTES := 1024
const WS_PATH := "/ws"
const MAX_PLAYERS := 10                   # alle Plätze: Gastgeber, Mitspieler und Computergegner
const MAX_CLIENT_MESSAGE := 8192          # Byte je Client-Nachricht
const MAX_HOST_MESSAGE := 1024 * 1024     # Byte je Host-Nachricht (Client-Seite, großzügig: Sicht mit 112 Karten passt in ~20 KB)
const MAX_RATE := 20                      # Client-Nachrichten je Sekunde
const MAX_NAME := 14                      # Zeichen je Name
const MAX_LOG_TEXT := 1000                # Zeichen je Browser-Logzeile
const TOKEN_LENGTH := 24
const KINDS := ["app", "web"]
const REJECT_CODES := ["version", "full", "running", "proto"]
# Felder einer Spielaktion (Abschnitt 4) mit Typ: andere Felder werden verworfen.
const ACTION_FIELDS := {"a": TYPE_STRING, "card": TYPE_INT, "color": TYPE_STRING, "target": TYPE_INT}
const MAX_DEPTH := 12

# --- Online-Spiel über einen Vermittler (docs/online/ENTWURF.md) ---
const RELAY_DEFAULT := ""                 # Standard-Vermittler; setzt der Nutzer nach seiner Bereitstellung
const RELAY_CONN_BASE := 1000000          # Verbindungsnummern der Online-Gäste beim Gastgeber: RELAY_CONN_BASE + c
const RELAY_PROTO := 1
const RELAY_PING_MS := 25000              # Online-Herzschlag: Text „ping“, der Vermittler antwortet „pong“
const RELAY_TIMEOUT_MS := 70000           # so lange Stille → getrennt
const RELAY_HOST_AWAY_MS := 10000         # Code 4503 (Gastgeber kurz weg): so lange warten, dann neu verbinden
const RELAY_MAX_HOST_MESSAGE := 256 * 1024
const CLOSE_ROOM_UNKNOWN := 4404
const CLOSE_HOST_AWAY := 4503
const CLOSE_ROOM_FULL := 4409
const CLOSE_RATE := 4429
const CLOSE_BAD_TOKEN := 4403
const CLOSE_ROOM_ENDED := 1001
const APK_RELEASE_URL := "https://github.com/ShakieVan/Mau-Mau-Flip/releases/latest"
const APK_BETA_URL := "https://github.com/ShakieVan/Mau-Mau-Flip-Beta/releases/latest"

static func normalize_room_code(text: String) -> String:
	# Raumcode wie normalizeCode in relay/src/core.js: Großbuchstaben, Ä/Ö/Ü/ß → AE/OE/UE/SS, Leer-/Unterstrich, Punkt oder fehlender
	# Strich → „WORT-ZZ“. Gültig: 3–6 Buchstaben A–Z, zwei Ziffern 10–99. "" = ungültig. Ob das Wort in der Liste des Vermittlers
	# (relay/src/words.js) steht, prüft erst der Vermittler (/info?room= → open:false).
	if text.length() > 40:
		return ""
	var t := text.strip_edges().to_upper()
	t = t.replace("Ä", "AE").replace("Ö", "OE").replace("Ü", "UE").replace("ẞ", "SS").replace("ß", "SS").replace("ä", "AE").replace("ö", "OE").replace("ü", "UE")
	var letters := ""
	var digits := ""
	for ch in t:
		if ch >= "A" and ch <= "Z":
			if digits != "":
				return ""
			letters += ch
		elif ch >= "0" and ch <= "9":
			if letters == "":
				return ""
			digits += ch
		elif ch in [" ", "\t", "-", "_", "–", "."]:
			continue
		else:
			return ""
	if letters.length() < 3 or letters.length() > 6 or digits.length() != 2 or digits.begins_with("0"):
		return ""
	return letters + "-" + digits

static func normalize_relay_url(text: String) -> String:
	# Vermittler-Adresse → „https://host[:port]“ (ohne Pfad und Schrägstrich am Ende). Ohne Schema gilt https; „http://“ nur
	# ausdrücklich (lokaler Nachbau). "" = leer oder ungültig.
	var t := text.strip_edges()
	if t == "":
		return ""
	var scheme := "https"
	var low := t.to_lower()
	for pre in [["https://", "https"], ["http://", "http"], ["wss://", "https"], ["ws://", "http"]]:
		if low.begins_with(pre[0]):
			scheme = pre[1]
			t = t.substr(pre[0].length())
			break
	if t.contains("://"):
		return ""
	for cut in ["/", "?", "#"]:
		var i := t.find(cut)
		if i >= 0:
			t = t.left(i)
	t = t.to_lower()
	if t == "" or t.length() > 200 or t.contains("@"):
		return ""
	var host := t
	var colon := t.rfind(":")
	if colon >= 0:
		var p := t.substr(colon + 1)
		if not p.is_valid_int() or int(p) <= 0 or int(p) > 65535:
			return ""
		host = t.left(colon)
	if host == "" or host.begins_with(".") or host.ends_with(".") or host.begins_with("-"):
		return ""
	for ch in host:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "." or ch == "-"):
			return ""
	return "%s://%s" % [scheme, t]

static func relay_host(relay_url: String) -> String:
	# „https://x.workers.dev“ → „x.workers.dev“ (für Anzeige und App-Link v=; http bleibt mit Schema erhalten)
	var u := normalize_relay_url(relay_url)
	return u.trim_prefix("https://") if u.begins_with("https://") else u

static func relay_ws_url(relay_url: String, query: String) -> String:
	# WebSocket-Adresse des Vermittlers: https → wss, http → ws
	var u := normalize_relay_url(relay_url)
	if u == "":
		return ""
	var ws := ("wss://" + u.substr(8)) if u.begins_with("https://") else ("ws://" + u.substr(7))
	return ws + WS_PATH + "?" + query

static func room_link(relay_url: String, code: String) -> String:
	# Link für Gäste (QR, Teilen): https://<vermittler>/?r=KATZE-42
	var u := normalize_relay_url(relay_url)
	var c := normalize_room_code(code)
	return "" if u == "" or c == "" else "%s/?r=%s" % [u, c]

static func parse_room_link(text: String) -> Dictionary:
	# Raum-Link „https://<vermittler>/?r=CODE“ → {relay, room}; {} = kein Raum-Link
	var t := text.strip_edges()
	var low := t.to_lower()
	if not (low.begins_with("https://") or low.begins_with("http://")):
		return {}
	var q := t.find("?")
	if q < 0:
		return {}
	var room := ""
	for pair in t.substr(q + 1).split("&", false):
		if pair.to_lower().begins_with("r="):
			room = normalize_room_code(pair.substr(2).uri_decode())
	var relay := normalize_relay_url(t.left(q))
	if room == "" or relay == "":
		return {}
	return {"relay": relay, "room": room}

static func apk_page_url(version := "") -> String:
	# APK für Online-Gäste: GitHub-Release-Seite (Beta-Versionen enden nicht auf .0)
	var v := version if version != "" else game_version()
	return APK_RELEASE_URL if v.ends_with(".0") else APK_BETA_URL

static func relay_auto_reply(text: String) -> String:
	# Herzschlag des Vermittlers (setWebSocketAutoResponse „ping“ → „pong“)
	return "pong" if text == "ping" else ""

static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# --- Kodierung ---

static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)

static func decode(text: String, max_bytes := MAX_CLIENT_MESSAGE) -> Dictionary:
	# Textrahmen → Nachricht mit Typ "t" (String), ganzzahlige Zahlen als int. {} = ungültig (zu groß, kein Objekt, kein Typ).
	if text.length() > max_bytes or text.length() < 2 or text.unicode_at(0) != 0x7B:
		return {}
	if text.to_utf8_buffer().size() > max_bytes:
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var msg = ints(json.data)
	if not msg is Dictionary or not msg.get("t") is String or str(msg.t).length() > 24 or str(msg.t) == "":
		return {}
	return msg

static func ints(value, depth := 0) -> Variant:
	# Ganzzahlige floats (JSON) rekursiv in int wandeln; zu tiefe Verschachtelung wird zu null.
	if depth > MAX_DEPTH:
		return null
	if value is float:
		var f: float = value
		if is_finite(f) and f == floorf(f) and absf(f) <= 9007199254740991.0:
			return int(f)
		return f
	if value is Dictionary:
		var out := {}
		for key in value:
			out[str(key)] = ints(value[key], depth + 1)
		return out
	if value is Array:
		var arr := []
		for item in value:
			arr.append(ints(item, depth + 1))
		return arr
	return value

static func is_int(v) -> bool:
	return v is int

static func clean_client_message(msg: Dictionary) -> Dictionary:
	# Host: Nachricht eines Clients nach Typ prüfen und auf bekannte Felder kürzen. {} = verwerfen.
	var t := str(msg.get("t", ""))
	match t:
		"hello":
			var out := {"t": "hello", "proto": int(msg.proto) if msg.get("proto") is int else -1,
				"game": str(msg.game).left(24) if msg.get("game") is String else "",
				"name": clean_name(str(msg.name)) if msg.get("name") is String else clean_name(""),
				"kind": str(msg.kind) if msg.get("kind") is String and KINDS.has(msg.kind) else "web"}
			if msg.get("token") is String and str(msg.token).length() <= 64:
				out["token"] = str(msg.token)
			return out
		"act":
			var a = msg.get("a")
			if not a is Dictionary:
				return {}
			var action := clean_action(a)
			if action.is_empty():
				return {}
			var out := {"t": "act", "a": action}
			if msg.get("seq") is int and int(msg.seq) >= 0:
				out["seq"] = int(msg.seq)
			return out
		"lobby_ready":
			if not msg.get("ready") is bool:
				return {}
			return {"t": "lobby_ready", "ready": bool(msg.ready)}
		"ping":
			return {"t": "ping", "ts": msg.ts if (msg.get("ts") is int or msg.get("ts") is float) else 0}
		"log":
			if not msg.get("text") is String:
				return {}
			return {"t": "log", "text": strip_controls(str(msg.text), true).left(MAX_LOG_TEXT)}
		_:
			# Unbekannte Typen (künftige Erweiterungen) gehen unverändert an die Spielsteuerung; sie prüft selbst.
			return msg

static func clean_action(a: Dictionary) -> Dictionary:
	# Spielaktion {a, card?, color?, target?}: nur bekannte Felder mit passendem Typ. {} = ungültig.
	if not a.get("a") is String or str(a.a) == "" or str(a.a).length() > 16:
		return {}
	var out := {}
	for key in ACTION_FIELDS:
		if not a.has(key):
			continue
		var v = a[key]
		if ACTION_FIELDS[key] == TYPE_INT and v is int:
			out[key] = int(v)
		elif ACTION_FIELDS[key] == TYPE_STRING and v is String and str(v).length() <= 16:
			out[key] = str(v)
	# Kartenliste (discard_pick): nur ganze Zahlen, höchstens 120 Einträge.
	var cards = a.get("cards")
	if cards is Array and cards.size() <= 120:
		var list: Array = []
		var ok := true
		for c in cards:
			if not c is int:
				ok = false
				break
			list.append(int(c))
		if ok:
			out["cards"] = list
	return out

static func auto_reply(text: String) -> String:
	# Läuft im Netz-Thread des Servers: Lebenszeichen „ping“ sofort beantworten, auch wenn die Hauptschleife steht (App im
	# Hintergrund, docs/recherche/13_gegenpruefung.md Punkt 6). "" = keine Sofortantwort, die Nachricht geht normal weiter.
	if text.length() > 200 or not text.contains("\"ping\""):
		return ""
	var msg := decode(text, 200)
	if msg.get("t") != "ping":
		return ""
	var ts = msg.get("ts", 0)
	return encode({"t": "pong", "ts": ts if (ts is int or ts is float) else 0})

# --- Namen ---

static func strip_controls(text: String, keep_newlines := false) -> String:
	# Steuerzeichen, Richtungs- und Nullbreitenzeichen entfernen (keine umgedrehten oder unsichtbaren Namen).
	var out := ""
	for i in range(text.length()):
		var c := text.unicode_at(i)
		if keep_newlines and c == 10:
			out += "\n"
			continue
		if c < 32 or (c >= 127 and c < 160):
			continue
		if (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF:
			continue
		if c >= 0xD800 and c <= 0xDFFF:
			continue
		out += char(c)
	return out

static func clean_name(text: String, fallback := "Gast") -> String:
	# Höchstens MAX_NAME Zeichen, keine Steuerzeichen, Leerraum zusammengefasst, höchstens zwei kombinierende Zeichen hintereinander.
	var plain := strip_controls(text.replace("\t", " ").replace("\n", " ").replace("\r", " "))
	var out := ""
	var marks := 0
	var space := false
	for i in range(plain.length()):
		var c := plain.unicode_at(i)
		if c == 32 or c == 0xA0 or c == 0x3000 or (c >= 0x2000 and c <= 0x200A):
			if not space and out != "":
				out += " "
			space = true
			continue
		space = false
		if (c >= 0x0300 and c <= 0x036F) or (c >= 0x1AB0 and c <= 0x1AFF) or (c >= 0x20D0 and c <= 0x20FF) or (c >= 0xFE20 and c <= 0xFE2F):
			marks += 1
			if marks > 2:
				continue
		else:
			marks = 0
		out += char(c)
	out = out.strip_edges().left(MAX_NAME).strip_edges()
	return out if out != "" else fallback

static func unique_name(wanted: String, taken: Array) -> String:
	# Gleiche Namen bekommen eine Ziffer („Anna“, „Anna 2“ …).
	if not taken.has(wanted):
		return wanted
	for n in range(2, 100):
		var suffix := " %d" % n
		var candidate := wanted.left(MAX_NAME - suffix.length()).strip_edges() + suffix
		if not taken.has(candidate):
			return candidate
	return wanted

# --- Begrüßung ---

static func make_hello(player_name: String, kind := "app", token := "", game := "") -> Dictionary:
	var msg := {"t": "hello", "proto": PROTO, "game": game if game != "" else game_version(), "name": clean_name(player_name),
		"kind": kind if KINDS.has(kind) else "app"}
	if token != "":
		msg["token"] = token
	return msg

static func compare_versions(a: String, b: String) -> int:
	# "0.1.10" > "0.1.9": -1, 0, 1. Nicht-Zahlen zählen als 0.
	var pa := a.split(".")
	var pb := b.split(".")
	for i in range(maxi(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() and pa[i].is_valid_int() else 0
		var y := int(pb[i]) if i < pb.size() and pb[i].is_valid_int() else 0
		if x != y:
			return -1 if x < y else 1
	return 0

static func check_hello(hello: Dictionary, local_game: String, apk_url := "") -> Dictionary:
	# Gastgeber prüft die (bereinigte) Begrüßung: {} = in Ordnung, sonst {code, text, lt}; der Text spricht den Mitspieler an,
	# lt = Bausteine (I18n), damit der Gast ihn in seiner Sprache sieht.
	var lt: Array = []
	if int(hello.get("proto", -1)) != PROTO:
		lt.append(I18n.part("Netzprotokoll passt nicht (Gastgeber %d, dein Gerät %d). Bitte beide auf dieselbe Version von Mau-Mau Flip bringen.",
			[PROTO, int(hello.get("proto", -1))]))
		if apk_url != "":
			lt.append(I18n.part("App vom Gastgeber holen: %s", [apk_url]))
		return I18n.with_lt({"code": "proto"}, lt)
	var game := str(hello.get("game", ""))
	if game != local_game:
		lt.append(I18n.part("Andere Version: Gastgeber %s, dein Gerät %s.", [local_game, game if game != "" else "?"]))
		if game != "" and compare_versions(game, local_game) > 0:
			lt.append("Der Gastgeber sollte seine App aktualisieren (Menü → Update).")
		else:
			if str(hello.get("kind", "")) == "web":
				lt.append("Bitte die Seite neu laden.")
			if apk_url != "":
				lt.append(I18n.part("App vom Gastgeber holen: %s", [apk_url]))
		return I18n.with_lt({"code": "version"}, lt)
	return {}

# --- Gastgeber-Info (/info und Suche) ---

static func make_info(host_name: String, players: int, port: int, extra := {}) -> Dictionary:
	var info := {"game": GAME_ID, "version": game_version(), "proto": PROTO, "name": clean_name(host_name, "Gastgeber"),
		"players": players, "max": MAX_PLAYERS, "port": port}
	info.merge(extra, true)
	return info

static func is_query(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 4 and bytes.size() <= 64 and bytes.slice(0, 4).get_string_from_ascii() == DISCOVERY_QUERY

static func make_reply(info: Dictionary) -> PackedByteArray:
	var data := info.duplicate()
	data["m"] = DISCOVERY_MAGIC
	var bytes := JSON.stringify(data).to_utf8_buffer()
	if bytes.size() > MAX_DISCOVERY_BYTES and data.get("addresses") is Array:
		data.addresses = (data.addresses as Array).slice(0, 4)
		bytes = JSON.stringify(data).to_utf8_buffer()
	return bytes

static func parse_reply(bytes: PackedByteArray) -> Dictionary:
	# Antwort auf „MMF?“ → {name, version, proto, players, max, port, running, sid, addresses, compatible}; {} = fremdes Paket.
	if bytes.size() < 2 or bytes.size() > MAX_DISCOVERY_BYTES or bytes[0] != 0x7B:
		return {}
	for b in bytes:
		if b < 9:
			return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}
	var d: Dictionary = ints(json.data)
	if d.get("m") != DISCOVERY_MAGIC or d.get("game") != GAME_ID or not d.get("port") is int:
		return {}
	var port := int(d.port)
	if port <= 0 or port > 65535:
		return {}
	var addresses := []
	if d.get("addresses") is Array:
		for a in d.addresses:
			if a is String and ipv4_to_int(a) > 0 and addresses.size() < 8:
				addresses.append(a)
	var info := {"name": clean_name(str(d.get("name", "")), "Gastgeber"), "version": str(d.get("version", "?")).left(16),
		"proto": int(d.proto) if d.get("proto") is int else -1, "players": clampi(int(d.players) if d.get("players") is int else 0, 0, 99),
		"max": clampi(int(d.max) if d.get("max") is int else MAX_PLAYERS, 1, 99), "port": port,
		"running": d.get("running") is bool and bool(d.running), "sid": str(d.get("sid", "")).left(32), "addresses": addresses}
	info["compatible"] = info.proto == PROTO and info.version == game_version()
	return info

# --- Adressen ---

static func ipv4_to_int(ip: String) -> int:
	# -1 = keine IPv4-Adresse
	var parts := ip.split(".")
	if parts.size() != 4:
		return -1
	var value := 0
	for p in parts:
		if not p.is_valid_int() or p.length() > 3 or int(p) < 0 or int(p) > 255:
			return -1
		value = (value << 8) | int(p)
	return value

static func int_to_ipv4(value: int) -> String:
	return "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]

static func directed_broadcast(ip: String, prefix := 24) -> String:
	# Gerichteter Rundruf eines Netzes, z. B. 192.168.43.17/24 → 192.168.43.255. "" bei ungültiger Eingabe.
	var value := ipv4_to_int(ip)
	if value < 0 or prefix < 8 or prefix > 30:
		return ""
	return int_to_ipv4(value | ((1 << (32 - prefix)) - 1))

static func usable_ipv4(ip: String) -> bool:
	# Eigene Adresse für Suche und QR: IPv4, nicht 0.0.0.0, nicht Loopback, nicht Link-local (169.254), nicht CLAT (192.0.0.x).
	var value := ipv4_to_int(ip)
	return value > 0 and (value >> 24) != 127 and (value >> 16) != 0xA9FE and (value >> 8) != 0xC00000 and (value >> 28) < 14

static func is_private_ipv4(ip: String) -> bool:
	var v := ipv4_to_int(ip)
	return v > 0 and ((v >> 24) == 10 or (v >> 20) == 0xAC1 or (v >> 16) == 0xC0A8)

static func parse_address(text: String, default_port := PORT) -> Dictionary:
	# "192.168.1.5", "192.168.1.5:24690" oder "http://192.168.1.5:24690/" → {address, port}; {} bei ungültiger Eingabe.
	var t := text.strip_edges().replace(",", ".")
	for scheme in ["http://", "ws://"]:
		if t.to_lower().begins_with(scheme):
			t = t.substr(scheme.length())
	var slash := t.find("/")
	if slash >= 0:
		t = t.left(slash)
	var port := default_port
	var cut := t.rfind(":")
	if cut > 0 and t.count(":") == 1:
		var p := t.substr(cut + 1)
		if not p.is_valid_int() or int(p) <= 0 or int(p) > 65535:
			return {}
		port = int(p)
		t = t.left(cut)
	if ipv4_to_int(t) < 0 and t != "localhost":
		return {}
	return {"address": t, "port": port}
