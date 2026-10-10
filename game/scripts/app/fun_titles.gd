class_name FunTitles
extends RefCounted
# Spaßtitel (Beta 1.4.4) in „Deine Statistik“: werden aus den Zählern abgeleitet, nichts wird zusätzlich gespeichert.
# Jeder Titel hat einen Zähler und eine Schwelle; der Wert geteilt durch die Schwelle ist die „Stärke“ (ab 1,0 verdient). Angezeigt
# werden die MAX_SHOWN stärksten verdienten Titel (bei Gleichstand in der Reihenfolge der Liste).

const MAX_SHOWN := 3
# [Schlüssel des Zählers, Schwelle, Titel (msgid), Erklärung (msgid)]
const LIST := [
	["gezogen", 60, "Ziehkönig", "Die meisten Karten gezogen"],
	["erwischt_selbst", 5, "Erwischt-Meister", "Andere beim Vergessen von „Mau!“ erwischt"],
	["gluecksspiel_max", 8, "Glücksritter", "Beim Glücksspiel hoch gepokert und getroffen"],
	["aussetzen", 10, "Schnurrkatze", "Oft ausgesetzt, dafür gut ausgeschlafen"],
	["flip", 10, "Flipper", "Die Welt oft auf den Kopf gestellt"],
	["kartentausch", 5, "Tauschbörse", "Hände reihum weitergegeben"],
]


# Verdiente Titel als [{key, title, why, power}], stärkste zuerst (Texte schon in der Sprache der App)
static func earned(data: Dictionary) -> Array:
	var out: Array = []
	for i in LIST.size():
		var row: Array = LIST[i]
		var v := float(int(data.get(str(row[0]), 0)))
		var power := v / float(row[1])
		if power >= 1.0:
			out.append({"key": str(row[0]), "title": I18n.t(str(row[2])), "why": I18n.t(str(row[3])), "power": power, "order": i})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["power"]), float(b["power"])):
			return float(a["power"]) > float(b["power"])
		return int(a["order"]) < int(b["order"]))
	return out.slice(0, MAX_SHOWN)
