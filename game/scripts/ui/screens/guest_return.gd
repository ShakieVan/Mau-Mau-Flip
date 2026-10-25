class_name GuestReturn
extends RefCounted
# Mau-Mau Flip (Beta 1.6.16, Raum behalten, docs/module/raum_behalten.md Abschnitt 3): „Zurück ins Spiel“ für Online-Gäste der App.
# Wer ein Online-Spiel verlässt (Tisch: „Partie verlassen“; Gast-Lobby: Zurück) oder vom Gastgeber verabschiedet wird („bye“, nicht
# herausgenommen), den merkt sich die App in der Einstellung zurueck_ins_spiel {room, relay, host, t}. Das Hauptmenü zeigt dann
# „Zurück ins Spiel“ mit „KATZE-42 · bei Lena · vor 3 min“; ein Tipp öffnet die Beitrittsseite direkt für diesen Raum. Das gemerkte
# Token (NetClient, user://netz_token.json) bringt den Gast auf seinen Platz zurück; hat der Gastgeber mit demselben Raumcode neu
# eröffnet (RoomKeeper), landet er in der neuen Lobby; ist der Gastgeber gerade weg, wartet die Beitrittsseite („Gastgeber kurz weg“).
# Vergessen: beim Beitritt (welcome), beim Eröffnen eines eigenen Spiels, „Nicht mehr anzeigen“, Raum weg (/info open:false im
# Hauptmenü) und nach MAX_AGE_S.

const SETTING := "zurueck_ins_spiel"
const MAX_AGE_S := 10800            # so lange bietet das Hauptmenü den Raum höchstens an (3 h)

static var enabled := false         # App._init: an, außer in Testläufen (die schreiben sonst in die echte Einstellungsdatei)


static func now_unix(now := -1) -> int:
	return now if now >= 0 else int(Time.get_unix_time_from_system())


# Online-Gast merken (vor ClientTable.leave aufrufen: danach gibt es den NetClient nicht mehr). Nicht bei herausgenommenen Gästen.
static func remember(ct: ClientTable, now := -1) -> void:
	if not enabled or ct == null or ct.client == null or not ct.client.is_online() or ct.was_removed():
		return
	var c := ct.client
	var entry: Variant = AppSettings.clean_return({"room": c.room, "relay": c.relay_url, "host": ct.host_name(), "t": now_unix(now)})
	if entry == null:
		return
	var app := UiApp.app()
	if app != null and app.get("settings") is AppSettings:
		(app.settings as AppSettings).set_value(SETTING, entry)


# Gemerkter Raum, solange er nicht zu alt ist ({} = keiner)
static func current(now := -1) -> Dictionary:
	var v: Variant = AppSettings.clean_return(UiApp.setting(SETTING, {}))
	if not v is Dictionary:
		return {}
	var age := now_unix(now) - int(v.t)
	if age < -60 or age > MAX_AGE_S:
		return {}
	return v


static func forget() -> void:
	var app := UiApp.app()
	if app != null and app.get("settings") is AppSettings and (app.settings as AppSettings).has_value(SETTING):
		(app.settings as AppSettings).reset(SETTING)


# Unterzeile im Hauptmenü: „KATZE-42 · bei Lena · vor 3 min“
static func subline(d: Dictionary, now := -1) -> String:
	var age := maxi(1, int(ceil((now_unix(now) - int(d.get("t", 0))) / 60.0)))
	var who := str(d.get("host", ""))
	if who != "":
		return I18n.t("%s · bei %s · vor %d min") % [str(d.get("room", "")), who, age]
	return I18n.t("%s · vor %d min") % [str(d.get("room", "")), age]


# Beitrittsseite direkt für diesen Raum (wie ein App-Link: /info, dann verbinden mit dem gemerkten Token)
static func open(nav: ScreenNav, d: Dictionary) -> void:
	if nav == null or d.is_empty():
		return
	JoinScreen._open_direct(nav, NetProtocol.room_link(str(d.relay), str(d.room)), 0)
