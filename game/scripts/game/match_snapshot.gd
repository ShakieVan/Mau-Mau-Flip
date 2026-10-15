class_name MatchSnapshot
extends RefCounted
# Mau-Mau Flip (Beta 1.6.1, Gastgeber-Übergabe): Spielstand-Schnappschuss einer Netzpartie (docs/module/uebergabe.md Abschnitt 1),
# nur statische Funktionen. Derselbe Stand liegt beim Gastgeber in TableSource.NET_SAVE_PATH (role "host") und geht als Sicherung
# {t:"bk", z} an die App-Gäste (z = base64(gzip(JSON)), NetProtocol.pack_snapshot). Form (format 2):
#   {format, mode:"host", role:"host"|"guest", gid, gen, epoch, parent:[gen, epoch, seq], seq, saved_unix, saved,
#    game: MauGame.to_dict(), seats: [{name, kind, host, net, token, link}] (ohne id), host_seat,
#    substitute: [Platz …], gone_names: [Name …], waiting: [{name, net, token}], join_open, heirs: [Token …], bk_to: [Token …],
#    wlan_humans, online: {relay, room, token, conns, max_c, created_unix} | {}, wlan: {port, addrs}, my_seat (nur Gast-Datei)}
# Das Token des Gastgebers ist seats[host_seat].token (kein eigenes Feld). bk_to (Ergänzung zum Entwurf): Tokens der Gäste, die diesen
# Stand als Sicherung bekamen – auf sie wartet die Einschwingzeit nach dem Fortsetzen (Abschnitt 1.4).
# Mau-Mau Flip (Beta 1.6.2, WLAN und Spiel-WLAN, Abschnitt 10.2; format bleibt 2): je Platz zusätzlich addr (IPv4, unter der der
# Gastgeber den Platz zuletzt im WLAN sah, "" = unbekannt), hp (Port, auf dem das Gerät als Gastgeber lauschen würde, 0 = unbekannt)
# und ap: {ok, perm} (kann ein Spiel-WLAN öffnen / Erlaubnis erteilt; ältere Apps ohne Feld: beides false). wlan wird zu
# {port, addrs, ap, ap_seat, past}: ap = die Partie läuft in einem Spiel-WLAN, ap_seat = Platz, dessen Handy es führt (−1 = keins;
# Dateien von 1.6.1 ohne Feld: host_seat, 10.8), past = frühere Gastgeber-Adressen "ip:port" über die ganze Kette, höchstens
# PAST_MAX, die neuesten zuletzt (Herkunftsprüfung 10.9).

const FORMAT := 2
const MODE := "host"
const PAST_MAX := 16             # Beta 1.6.2: höchstens so viele frühere Gastgeber-Adressen in wlan.past (= NetProtocol.PAST_MAX)
const EXTRA_KEYS := ["gid", "gen", "epoch", "parent", "seq", "substitute", "gone_names", "waiting", "join_open", "heirs", "bk_to",
	"wlan_humans", "online", "wlan"]


# Schnappschuss aus den Teilen der Spielsteuerung (HostTable._snapshot). seats werden kopiert, ohne Sitzungs-id.
static func make(game_dict: Dictionary, seats: Array, host_seat: int, extra: Dictionary, now_unix: int, role := "host") -> Dictionary:
	var out_seats: Array = []
	for p in seats:
		var d: Dictionary = (p as Dictionary).duplicate(true)
		d.erase("id")
		out_seats.append(d)
	var d := {"format": FORMAT, "mode": MODE, "role": role, "saved_unix": now_unix, "saved": Time.get_datetime_string_from_system(),
		"game": game_dict, "seats": out_seats, "host_seat": host_seat}
	for k in EXTRA_KEYS:
		if extra.has(k):
			d[k] = extra[k]
	return d


# Geprüfte, bereinigte Kopie (JSON macht aus Zahlen float); {} = unbrauchbar. Ältere Gastgeber-Stände (format 1, bis 1.6.0) gehen
# auch durch, dann ohne gid (die Spielsteuerung beginnt eine neue Abstammung).
static func clean(data: Dictionary) -> Dictionary:
	if str(data.get("mode", "")) != MODE or not data.get("game") is Dictionary or not data.get("seats") is Array:
		return {}
	var seats: Array = data.seats
	var hs := _int(data.get("host_seat"), -1)
	if seats.size() < MauGame.MIN_PLAYERS or seats.size() > MauGame.MAX_PLAYERS or hs < 0 or hs >= seats.size():
		return {}
	for p in seats:
		if not p is Dictionary or not (p as Dictionary).get("name") is String:
			return {}
	var d := data.duplicate(true)
	d.host_seat = hs
	for p in d.seats:
		_clean_seat_net(p)
	d.format = _int(data.get("format"), 1)
	d.role = "guest" if str(data.get("role", "")) == "guest" else "host"
	d.gid = str(data.get("gid", "")) if data.get("gid") is String and str(data.gid).is_valid_hex_number() else ""
	d.gen = maxi(_int(data.get("gen"), 0), 0)
	d.epoch = str(data.get("epoch", "")) if data.get("epoch") is String else ""
	d.seq = maxi(_int(data.get("seq"), 0), 0)
	var parent := NetProtocol.clean_bk_mark(data.get("parent"))
	d.parent = parent if not parent.is_empty() else NetProtocol.BK_NONE.duplicate()
	d.saved_unix = _int(data.get("saved_unix"), 0)
	d.my_seat = _int(data.get("my_seat"), -1)
	d.substitute = _ints(data.get("substitute", []))
	d.gone_names = (data.gone_names as Array).map(func(n): return str(n)) if data.get("gone_names") is Array else []
	var waiting: Array = []
	if data.get("waiting") is Array:
		for w in data.waiting:
			if w is Dictionary and (w as Dictionary).get("name") is String:
				waiting.append({"name": str(w.name), "net": str(w.get("net", "app")), "token": str(w.get("token", ""))})
	d.waiting = waiting
	d.join_open = data.get("join_open") == true
	d.heirs = (data.heirs as Array).map(func(t): return str(t)) if data.get("heirs") is Array else []
	d.bk_to = (data.bk_to as Array).map(func(t): return str(t)) if data.get("bk_to") is Array else []
	d.wlan_humans = data.get("wlan_humans") == true
	var online: Dictionary = {}
	if data.get("online") is Dictionary and str((data.online as Dictionary).get("room", "")) != "":
		var o: Dictionary = data.online
		online = {"relay": str(o.get("relay", "")), "room": str(o.get("room", "")), "token": str(o.get("token", "")),
			"conns": _ints(o.get("conns", [])), "max_c": maxi(_int(o.get("max_c"), 0), 0), "created_unix": maxi(_int(o.get("created_unix"), 0), 0)}
	d.online = online
	var wlan: Dictionary = data.wlan if data.get("wlan") is Dictionary else {}
	# Beta 1.6.2: ap_seat fehlt in Dateien von 1.6.1 → host_seat (10.8); kaputt oder außerhalb der Plätze ebenso.
	var ap_seat := _int(wlan.get("ap_seat"), -2)
	if ap_seat < -1 or ap_seat >= seats.size():
		ap_seat = hs
	d.wlan = {"port": _int(wlan.get("port"), 0), "addrs": (wlan.addrs as Array).map(func(a): return str(a)) if wlan.get("addrs") is Array else [],
		"ap": wlan.get("ap") is bool and bool(wlan.ap), "ap_seat": ap_seat, "past": with_past(wlan.get("past", []))}
	return d


# Beta 1.6.2: Liste früherer Gastgeber-Adressen (wlan.past) bereinigen und optional um entry ("ip:port") ergänzen. Nur gültige
# IPv4:Port, ohne Doppelte (ein erneuter Eintrag rückt ans Ende), höchstens PAST_MAX – die ältesten fallen vorn heraus.
static func with_past(past: Variant, entry := "") -> Array:
	var items: Array = (past as Array).duplicate() if past is Array else []
	if entry != "":
		items.append(entry)
	var out: Array = []
	for x in items:
		var e := host_port(x)
		if e == "":
			continue
		out.erase(e)
		out.append(e)
	return out.slice(maxi(out.size() - PAST_MAX, 0))


# Beta 1.6.2: "ip:port" einer IPv4 mit Port 1–65535 in Normalform (ohne Leerzeichen, Port ohne führende Nullen); "" = ungültig.
static func host_port(v: Variant) -> String:
	if not v is String:
		return ""
	var parts := (v as String).strip_edges().split(":")
	if parts.size() != 2 or not is_ipv4(parts[0]) or not parts[1].is_valid_int():
		return ""
	var p := parts[1].to_int()
	if p < 1 or p > 65535:
		return ""
	return "%s:%d" % [parts[0], p]


# Beta 1.6.2: punktierte IPv4 ohne führende Nullen.
static func is_ipv4(a: String) -> bool:
	var parts := a.split(".")
	if parts.size() != 4:
		return false
	for x in parts:
		if x == "" or x.length() > 3 or not x.is_valid_int() or x.begins_with("+") or x.begins_with("-") or x.to_int() > 255 \
				or (x.length() > 1 and x.begins_with("0")):
			return false
	return true


# Beta 1.6.2: Netzfelder eines Platzes säubern (addr, hp, ap; 10.2). Fehlt ap (ältere App), gilt {ok:false, perm:false}.
static func _clean_seat_net(p: Dictionary) -> void:
	var addr := str(p.get("addr", "")).strip_edges() if p.get("addr") is String else ""
	p["addr"] = addr if is_ipv4(addr) else ""
	var hp := _int(p.get("hp"), 0)
	p["hp"] = hp if hp >= 1024 and hp <= 65535 else 0
	var ap: Dictionary = p.ap if p.get("ap") is Dictionary else {}
	p["ap"] = {"ok": ap.get("ok") is bool and bool(ap.ok), "perm": ap.get("perm") is bool and bool(ap.perm)}


# Stand [gen, epoch, seq] (Vergleich mit hello.bk, NetProtocol.compare_marks).
static func mark(data: Dictionary) -> Array:
	return [_int(data.get("gen"), 0), str(data.get("epoch", "")), _int(data.get("seq"), 0)]


# Token eines Platzes ("" = keiner, z. B. Computergegner).
static func seat_token(data: Dictionary, seat: int) -> String:
	var seats: Array = data.get("seats", []) if data.get("seats") is Array else []
	return str((seats[seat] as Dictionary).get("token", "")) if seat >= 0 and seat < seats.size() else ""


# Token, mit dem sich dieses Gerät wieder anmeldet: Gastgeber-Datei → Gastgeber-Platz, Gast-Datei → eigener Platz (my_seat).
static func own_token(data: Dictionary) -> String:
	if str(data.get("role", "host")) == "guest":
		return seat_token(data, _int(data.get("my_seat"), -1))
	return seat_token(data, _int(data.get("host_seat"), -1))


# Alter des Stands in Sekunden (Wanduhr).
static func age_s(data: Dictionary, now_unix: int) -> int:
	return now_unix - _int(data.get("saved_unix"), now_unix)


# Für „Partie fortsetzen“ anbieten? Nicht nach dem Partie-Ende, höchstens RESUME_MAX_H alt, online höchstens ROOM_LIFE_S seit dem
# Anlegen des Raums (Abschnitt 4.4/4.6).
# Beta 1.6.2: ignore_room = true prüft das Raumalter nicht – Sicherung beim Beitritt über jede Adresse, Fortsetzen in neuem Raum
# (10.6/10.13). Ohne nur dort, wo der alte Raum benutzt werden soll („Raum übernehmen“).
static func resumable(data: Dictionary, now_unix: int, ignore_room := false) -> bool:
	var d := clean(data)
	if d.is_empty() or str((d.game as Dictionary).get("phase", "")) == "game_over":
		return false
	if int(d.saved_unix) <= 0 or age_s(d, now_unix) > NetProtocol.RESUME_MAX_H * 3600:
		return false
	var o: Dictionary = d.online
	if not ignore_room and not o.is_empty() and int(o.created_unix) > 0 and now_unix - int(o.created_unix) >= NetProtocol.ROOM_LIFE_S:
		return false
	return true


# Verpacken für {t:"bk"}/{t:"handover"}; "" = größer als NetProtocol.SNAPSHOT_MAX (nicht verschicken).
static func pack(data: Dictionary) -> String:
	return NetProtocol.pack_snapshot(data)


# Entpacken und prüfen; {} = unbrauchbar.
static func unpack(z: String) -> Dictionary:
	return clean(NetProtocol.unpack_snapshot(z))


static func read(path := TableSource.NET_SAVE_PATH) -> Dictionary:
	return clean(TableSource.load_saved(path))


static func write(path: String, data: Dictionary) -> bool:
	return TableSource.write_saved(path, data)


static func _int(v: Variant, fallback: int) -> int:
	if v is int:
		return v
	if v is float and is_finite(v) and float(v) == floorf(float(v)):
		return int(v)
	return fallback


static func _ints(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			var i := _int(x, -1)
			if i >= 0:
				out.append(i)
	return out
