extends RefCounted
# Aufteilung langer Testläufe (tools/build.ps1 startet die Teile parallel): Umgebungsvariable TEIL="k/n" (1 ≤ k ≤ n).
# Teil k übernimmt die Partien mit Nummer i, für die i % n == k - 1 gilt; die festen Einzelprüfungen laufen nur in Teil 1.
# Alle Teile zusammen prüfen also genau dieselben Startwerte wie der ungeteilte Lauf. Ohne TEIL (Einzelaufruf) gilt 1/1 = alles.
# Zählprüfungen eines Dauerlaufs (z. B. „kommt in mehr als der Hälfte der Partien vor“) gelten je Teil für dessen Partien,
# sind damit mindestens so streng wie über alle.


static func _parse() -> Vector2i:
	var raw := OS.get_environment("TEIL").strip_edges()
	if raw == "":
		return Vector2i(1, 1)
	var parts := raw.split("/")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var k := int(parts[0])
		var n := int(parts[1])
		if n >= 1 and k >= 1 and k <= n:
			return Vector2i(k, n)
	push_error("TEIL=%s ungültig (erwartet k/n mit 1 ≤ k ≤ n)" % raw)
	print("FAIL: Umgebungsvariable TEIL=%s ungültig" % raw)
	return Vector2i(1, 1)


# Gehört Partie i zu diesem Teil?
static func mine(i: int) -> bool:
	var p := _parse()
	return i % p.y == p.x - 1


# Feste Einzelprüfungen: nur im ersten Teil.
static func first() -> bool:
	return _parse().x == 1


static func count() -> int:
	return _parse().y


# Abschnitt Nummer j (0, 1, 2 …) reihum auf die Teile verteilt.
static func slot(j: int) -> bool:
	return mine(j)


# „ (Teil 2/4)“ für Ausgaben, leer ohne Aufteilung.
static func label() -> String:
	var p := _parse()
	return "" if p.y == 1 else " (Teil %d/%d)" % [p.x, p.y]
