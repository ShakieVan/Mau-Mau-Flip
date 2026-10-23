class_name NatureTable
extends RefCounted
# Mau-Mau Flip (Beta 1.6.12): „Natur-Überraschungen“ – gemeinsame Datentabelle (docs/module/natur.md Abschnitt 6, Aufgabe T1).
# Quelle der Wahrheit für App und Browser: webclient/natur.js enthält dieselbe Tabelle als JSON zwischen /*NATUR-DATEN*/ und /*ENDE*/,
# test_web_contract.gd vergleicht beide (nach JSON.parse_string(JSON.stringify(...)), so stimmen Ganzzahl und Kommazahl überein).
# Rein und ohne Knoten: Einträge, Zeiten, gewichtete Kandidaten. Den Ablauf (Planer) macht NatureFx (nature_fx.gd).
# Beta 1.6.15: Hoppelhase und Strand mit Palme (Tag), Feuerwerk und Astronaut am Mond (Nacht); das UFO ist nicht mehr scheu und weicht
# beim 1. und 2. Tipp aus, erst der 3. verscheucht es (tipp „ausweichen“, natur.md 3.3 Nr. 18).
# Felder je Ereignis: zufall/nach_flip Gewichte (0 = nie), troedeln Anlass Trödeln (Schnecke), ebene hinten|mitte|vorn, ort Anker
# (Abschnitt 2.2), dauer [min, max] s, ruhig (auch bei „Effekte reduziert“, dann ruhige Variante), tipp Reaktion ("" = keine),
# scheu (geht bei Berührung in scheu_r), fremder_zug (nur, wenn man nicht selbst dran ist), je_partie/je_runde Obergrenzen
# (0 = frei), deckt/deckt_max_s (was die Ebene vorn kurz decken darf), bestand (zeichnet FunFx.SkyNode), form (Sternbild).

const DATA := {
 "zeiten": {"erst_s": [45, 150], "abstand_s": [100, 260], "reduziert_faktor": 2, "neuversuch_s": 5, "ruhe_s": 2,
  "anlass_abstand_s": 25, "keine_wiederholung": 4, "abgang_s": 0.4, "flip_chance": 0.4, "flip_nach_s": 1.5, "flip_bis_s": 6,
  "flip_je_runde": 1, "troedel_s": 35, "troedel_chance": 0.35, "troedel_max_s": 40, "scheu_r": 130, "treffer_min_r": 40,
  "komet_sperre_s": 20, "vorfuehr_tipps": 7, "vorfuehr_fenster_s": 4, "vorfuehr_abstand_s": 12},
 "ereignisse": [
  {"id": "marienkaefer", "seite": "tag", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [9, 12], "ruhig": false, "tipp": "wegfliegen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "biene", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "vorn", "ort": "handkarte", "dauer": [7, 9], "ruhig": false, "tipp": "", "scheu": true, "fremder_zug": true, "je_partie": 0, "je_runde": 0, "deckt": ["hand"], "deckt_max_s": 2, "bestand": false},
  {"id": "libelle", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "tisch_quer", "dauer": [6, 8], "ruhig": false, "tipp": "wegflitzen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "pusteblume", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [12, 15], "ruhig": false, "tipp": "wind", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "papierflieger", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [6, 7], "ruhig": false, "tipp": "looping", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "seifenblasen", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "tisch_quer", "dauer": [8, 11], "ruhig": false, "tipp": "platzen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "spatz", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_hinten", "dauer": [7, 10], "ruhig": false, "tipp": "wegfliegen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "wolke", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "sonne", "dauer": [12, 16], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "regenbogen", "seite": "tag", "zufall": 0, "nach_flip": 1, "troedeln": false, "ebene": "hinten", "ort": "himmel_bogen", "dauer": [7, 7], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 1, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "heissluftballon", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_fern", "dauer": [18, 22], "ruhig": false, "tipp": "aufsteigen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "schnecke", "seite": "tag", "zufall": 0, "nach_flip": 0, "troedeln": true, "ebene": "mitte", "ort": "band_zum_platz", "dauer": [40, 40], "ruhig": false, "tipp": "einziehen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "schmetterling", "seite": "tag", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [9, 9], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": true},
  {"id": "hoppelhase", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [9, 12], "ruhig": false, "tipp": "hochspringen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "strand", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "ecke_unten_rechts", "dauer": [7, 8], "ruhig": false, "tipp": "palme_schuetteln", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "gluehwuermchen", "seite": "nacht", "zufall": 3, "nach_flip": 3, "troedeln": false, "ebene": "mitte", "ort": "tisch_rund", "dauer": [12, 15], "ruhig": false, "tipp": "auseinander", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "eule", "seite": "nacht", "zufall": 3, "nach_flip": 1, "troedeln": false, "ebene": "mitte", "ort": "band_schulter", "dauer": [12, 16], "ruhig": false, "tipp": "kopf_blinzeln", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "fledermaus", "seite": "nacht", "zufall": 2, "nach_flip": 2, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [4, 6], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "mond_muetze", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "mond", "dauer": [10, 12], "ruhig": true, "tipp": "aufwachen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "polarlicht", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [12, 14], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "sternbild", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_frei", "dauer": [9, 10], "ruhig": true, "tipp": "funkeln", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false,
   "form": {"punkte": [[0.12, 0.06], [0.22, 0.20], [0.32, 0.04], [0.08, 0.38], [0.38, 0.34], [0.18, 0.64], [0.22, 0.96], [0.62, 0.48], [0.78, 0.92], [0.97, 0.72], [0.90, 0.38]],
            "linien": [[0, 1], [1, 2], [0, 3], [2, 4], [3, 5], [4, 7], [5, 6], [6, 8], [7, 8], [8, 9], [9, 10]]}},
  {"id": "ufo", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "vorn", "ort": "stapel_oben", "dauer": [7, 8], "ruhig": false, "tipp": "ausweichen", "scheu": false, "fremder_zug": true, "je_partie": 1, "je_runde": 0, "deckt": ["stapel"], "deckt_max_s": 3, "bestand": false},
  {"id": "satellit", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [9, 11], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "motte", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "ablage_ring", "dauer": [6, 8], "ruhig": false, "tipp": "", "scheu": true, "fremder_zug": true, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "igel", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [10, 14], "ruhig": false, "tipp": "einrollen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "komet", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [14, 16], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "lampion", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "aufsteigend", "dauer": [11, 13], "ruhig": false, "tipp": "leuchten", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "sternschnuppe", "seite": "nacht", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [1.2, 1.2], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": true},
  {"id": "feuerwerk", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [5, 6], "ruhig": false, "tipp": "knallen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "astronaut", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "mond", "dauer": [9, 12], "ruhig": false, "tipp": "salto", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false}
 ]
}

const SIDES := ["tag", "nacht"]


static func entries() -> Array:
	return DATA["ereignisse"]


# Eintrag zu einer id ({} = unbekannt)
static func entry(id: String) -> Dictionary:
	for e in DATA["ereignisse"]:
		if str(e["id"]) == id:
			return e
	return {}


# ids einer Seite ("tag" | "nacht"; "" = alle) in Tabellenreihenfolge
static func ids(side := "") -> Array:
	var out: Array = []
	for e in DATA["ereignisse"]:
		if side == "" or str(e["seite"]) == side:
			out.append(str(e["id"]))
	return out


static func timing(key: String) -> Variant:
	return DATA["zeiten"].get(key)


# Zeitspanne [min, max] als Zahl gleichverteilt
static func span(key: String, rng: RandomNumberGenerator) -> float:
	var b: Array = DATA["zeiten"][key]
	return rng.randf_range(float(b[0]), float(b[1]))


# Kandidaten einer Seite als Paare [id, Gewicht] (Abschnitt 4.2 „ziehe“).
#   counts = {"partie": {id: n}, "runde": {id: n}} (Obergrenzen je_partie/je_runde); recent = letzte Ereignisse dieser Seite (ältestes
#   zuerst): die letzten keine_wiederholung werden nicht gezogen, bleibt dadurch nichts übrig, fällt die älteste Sperre weg.
#   exclude = weitere ids (Komet-Sperre, Sternbild nach der Katze, Motte bei Strafplakette, Tiere ohne Zeichnung …).
static func pool(side: String, reduced: bool, my_turn: bool, counts := {}, recent: Array = [], exclude: Array = [], field := "zufall") -> Array:
	var base := _candidates(side, reduced, my_turn, counts, exclude, field)
	if base.is_empty() or recent.is_empty():
		return base
	var k := mini(int(DATA["zeiten"]["keine_wiederholung"]), recent.size())
	while k >= 0:
		var block := recent.slice(recent.size() - k)
		var rest := base.filter(func(p: Array) -> bool: return not block.has(p[0]))
		if not rest.is_empty():
			return rest
		k -= 1
	return base


# Kandidaten nach einem Flip zur Seite side (Gewicht nach_flip, ohne Wiederholungssperre)
static func flip_pool(side: String, reduced := false, my_turn := false, counts := {}, exclude: Array = []) -> Array:
	return _candidates(side, reduced, my_turn, counts, exclude, "nach_flip")


static func _candidates(side: String, reduced: bool, my_turn: bool, counts: Dictionary, exclude: Array, field: String) -> Array:
	var cp: Dictionary = counts.get("partie", {})
	var cr: Dictionary = counts.get("runde", {})
	var out: Array = []
	for e in DATA["ereignisse"]:
		var id := str(e["id"])
		if str(e["seite"]) != side or float(e.get(field, 0)) <= 0.0 or exclude.has(id):
			continue
		if reduced and not bool(e["ruhig"]):
			continue
		if my_turn and bool(e["fremder_zug"]):
			continue
		if int(e["je_partie"]) > 0 and int(cp.get(id, 0)) >= int(e["je_partie"]):
			continue
		if int(e["je_runde"]) > 0 and int(cr.get(id, 0)) >= int(e["je_runde"]):
			continue
		out.append([id, float(e[field])])
	return out


# Gewichtete Wahl aus Paaren [id, Gewicht]; "" bei leerer Liste
static func pick(pairs: Array, rng: RandomNumberGenerator) -> String:
	var sum := 0.0
	for p in pairs:
		sum += float(p[1])
	if sum <= 0.0:
		return ""
	var r := rng.randf() * sum
	for p in pairs:
		r -= float(p[1])
		if r < 0.0:
			return str(p[0])
	return str(pairs[pairs.size() - 1][0])
