extends SceneTree
# Beta 1.1.1: Nach „Spiel-WLAN schließen“ bindet die Gastgeber-Sitzung wieder wie beim Eröffnen (meist ans WLAN). Ablauf mit dem
# PC-Stub fürs Spiel-WLAN (NetAndroid.wifi_stub, GameWifiPanel.net_stub) und einem Ersatz für NetAndroid in NetAddresses, der die
# echten Regeln (host_plan …) auf erfundene Netzzustände anwendet und nur die Java-Aufrufe mitschreibt.
#   tools/godot_run.ps1 -Script res://tests/test_net_rebind.gd -Headless

const CleanExit := preload("res://tests/clean_exit.gd")
const ANDROID_PATH := "res://scripts/app/net_android.gd"
const PORT := 24916

var ok := 0
var failed := 0


class FakeAndroid:
	extends RefCounted
	var real
	var s := {}
	var calls: Array = []

	func state() -> Dictionary:
		return s.duplicate(true)
	func interfaces() -> Array:
		return s.get("interfaces", [])
	func wifi_handle(st: Dictionary) -> String:
		return real.wifi_handle(st)
	func wifi_addresses(st: Dictionary) -> Array:
		return real.wifi_addresses(st)
	func hotspot_addresses(st: Dictionary) -> Array:
		return real.hotspot_addresses(st)
	func hotspot_handle(st: Dictionary) -> String:
		return real.hotspot_handle(st)
	func host_plan(st: Dictionary, sockets = null) -> Dictionary:
		return real.host_plan(st, sockets)
	func join_binding(st: Dictionary, address: String) -> String:
		return real.join_binding(st, address)
	func in_hotspot(st: Dictionary, address: String) -> bool:
		return real.in_hotspot(st, address)
	func bound_to_wifi(st: Dictionary) -> bool:
		return real.bound_to_wifi(st)
	func wifi_gateway(st := {}) -> String:
		return real.wifi_gateway(st)
	func bind_wifi() -> String:
		calls.append("bind_wifi")
		return ""
	func bind_network(handle: String) -> String:
		calls.append("bind_network " + handle)
		return ""
	func unbind() -> bool:
		calls.append("unbind")
		return true
	func multicast(acquire: bool) -> bool:
		return true


func check(cond: bool, text: String) -> void:
	if cond:
		ok += 1
	else:
		failed += 1
		print("FAIL: ", text)


func _initialize() -> void:
	call_deferred("run")


func home_wifi() -> Dictionary:
	return {"android": true, "bound": null, "networks": [
		{"transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.40/24"], "gateway": "192.168.178.1", "handle": "101",
			"default": true, "internet": true, "validated": true}],
		"interfaces": [{"name": "wlan0", "address": "192.168.178.40", "prefix": 24}]}


# Heim-WLAN plus offenes Spiel-WLAN (Android 15: nur Schnittstelle)
func home_and_game_wifi() -> Dictionary:
	var s := home_wifi()
	s.interfaces.append({"name": "swlan0", "address": "10.94.17.1", "prefix": 24})
	return s


# Nur Spiel-WLAN als eigenes Netz (Android 16), kein WLAN
func game_wifi_only_16() -> Dictionary:
	return {"android": true, "bound": null, "networks": [
		{"transport": "wifi", "iface": "swlan0", "addresses": ["10.94.17.1/24"], "gateway": "", "handle": "303", "local": true,
			"default": false, "internet": false}],
		"interfaces": [{"name": "swlan0", "address": "10.94.17.1", "prefix": 24}]}


func run() -> void:
	if not ResourceLoader.exists(ANDROID_PATH):
		print("RESULT: 0 ok (NetAndroid fehlt – übersprungen)")
		await CleanExit.finish(self, 0)
		return
	var fake := FakeAndroid.new()
	fake.real = load(ANDROID_PATH)
	NetAddresses.set_helper(fake)
	fake.s = home_wifi()
	var host := GameStarter.host()
	root.add_child(host)
	host.use_discovery = false
	host.autosave = false
	check(host.open("Ben", PORT, PORT) == OK, "Gastgeber offen")
	check(NetAddresses.bound_to == "wifi" and fake.calls.has("bind_wifi"), "Eröffnen im Heim-WLAN: ans WLAN gebunden %s" % str(fake.calls))
	var holder := Control.new()
	holder.size = Vector2(1600, 720)
	root.add_child(holder)
	GameWifiPanel.net_stub = {"mode": "wlan", "urls": ["http://192.168.178.40:%d/" % PORT]}
	NetAndroid.wifi_stub = {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "address": "10.94.17.1"}
	var p := GameWifiPanel.new()
	holder.add_child(p)
	p.setup(host)
	# Spiel-WLAN öffnen: Hotspot und WLAN → ungebunden, Server neu auf demselben Port
	fake.calls.clear()
	fake.s = home_and_game_wifi()
	p.open_wifi()
	check(p.mode == "game_wifi" and p.hint == "", "Spiel-WLAN offen, kein Hinweis")
	check(NetAddresses.bound_to == "" and host.port() == PORT and host.session.server != null and host.session.server.running,
		"offen: ungebunden, Server läuft weiter auf %d" % PORT)
	# Spiel-WLAN schließen: zurück ans WLAN, Server neu auf demselben Port
	fake.calls.clear()
	fake.s = home_wifi()
	p.close_wifi()
	check(NetAddresses.bound_to == "wifi" and fake.calls.has("bind_wifi"), "geschlossen: wieder ans WLAN gebunden %s" % str(fake.calls))
	check(host.port() == PORT and host.session.server != null and host.session.server.running and p.hint == "",
		"geschlossen: Server neu auf demselben Port, kein Hinweis")
	fake.calls.clear()
	p.refresh_net(true)
	check(fake.calls.is_empty(), "nur einmal zurückbinden")
	p.queue_free()
	GameWifiPanel.net_stub = null
	NetAndroid.wifi_stub = null
	# Direkt an der Sitzung: ans Spiel-WLAN gebunden (Android 16), Mitspieler verbunden → trotzdem neu, deren Netz ist weg
	var s := host.session
	fake.s = game_wifi_only_16()
	check(s.rebind() == "" and NetAddresses.bound_to == "hotspot", "nur Spiel-WLAN (Android 16): ans Spiel-WLAN gebunden")
	s.players[9999] = {"id": 9999, "name": "Gast", "local": false, "conn": 77}
	fake.s = home_wifi()
	check(s.rebind(true) == "" and NetAddresses.bound_to == "wifi" and host.port() == PORT, "nach dem Schließen trotz Mitspieler ans WLAN")
	# ungebunden mit Mitspielern im WLAN: nicht neu starten, nur Hinweis
	fake.s = home_and_game_wifi()
	check(s.rebind() != "", "Öffnen mit Mitspielern: Hinweis wie bisher")
	fake.s = home_wifi()
	NetAddresses.bound_to = ""
	var h := s.rebind(true)
	check(h.contains("Spiel-WLAN ist zu"), "Schließen mit Mitspielern (ungebunden): Hinweis statt Neustart (%s)" % h)
	s.players.erase(9999)
	host.leave()
	NetAddresses.set_helper(null)
	print("RESULT: %d ok" % ok if failed == 0 else "RESULT: %d ok, %d FAIL" % [ok, failed])
	await CleanExit.finish(self, 1 if failed > 0 else 0)
