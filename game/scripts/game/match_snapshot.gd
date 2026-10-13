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

const FORMAT := 2
const MODE := "host"
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
	d.wlan = {"port": _int(wlan.get("port"), 0), "addrs": (wlan.addrs as Array).map(func(a): return str(a)) if wlan.get("addrs") is Array else []}
	return d


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
static func resumable(data: Dictionary, now_unix: int) -> bool:
	var d := clean(data)
	if d.is_empty() or str((d.game as Dictionary).get("phase", "")) == "game_over":
		return false
	if int(d.saved_unix) <= 0 or age_s(d, now_unix) > NetProtocol.RESUME_MAX_H * 3600:
		return false
	var o: Dictionary = d.online
	if not o.is_empty() and int(o.created_unix) > 0 and now_unix - int(o.created_unix) >= NetProtocol.ROOM_LIFE_S:
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
