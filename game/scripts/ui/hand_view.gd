class_name HandView
extends Node2D
# Die eigene Hand (docs/BETA1_PLAN.md Abschnitt 7, docs/recherche/06_hand_ux_effekte.md Abschnitte 1 und 2).
# Drei Stufen nach Kartenzahl (HandLayout): Fächer bis 7, Lupe beim Gleiten 8–15, ab 16 Bogen-Karussell mit Fischauge, Schwung,
# Einrasten (kritisch gedämpfte Feder) und Gummiband; zurück erst bei ≤ 13. Jede Karte folgt ihrem Layoutziel mit einer Feder,
# Unterbrechungen (neue Karte, Umsortieren, Flip mitten im Scrollen) ruckeln deshalb nie.
# Gesten (HandLayout.Gesture, 8 dp Toleranz, Winkelentscheidung):
#   Tipp hebt an (Auswahl), zweiter Tipp oder Doppeltipp spielt aus; Wischen/Ziehen nach oben spielt aus (Schwelle oder Schnippen).
#   Seitlich gleiten: Lupe (B) bzw. Karussell drehen (C). Halten 350 ms: Großansicht – die Karte steigt vergrößert über den Finger,
#   darunter erscheint im frei gewordenen Raum ein „?“. Danach: nach oben = ausspielen, seitlich = umsortieren (schaltet auf
#   „manuell“), kurz nach unten auf das „?“ (~40 dp) = Kartenhilfe. Loslassen ohne Zug lässt die Großansicht offen, mit „?“-Knopf.
# Koordinaten: layout_rect ist der Handbereich im lokalen System dieses Nodes. Solange der Tisch ihn nicht setzt, folgt er dem
# unteren Rand des sichtbaren Bereichs (auch 19:9); die Karten ragen nach unten aus dem Bild, sichtbar ist der obere Teil.
# Signale liefern globale Positionen (Fingerposition).
# Zeichenreihenfolge: über die Kindreihenfolge, nicht über große z_index-Werte. Ruhende Karten haben z_index 0; gezogene,
# große und ausgespielte Karten samt Abdunklung und Geisterbild liegen bei TOP_Z (≤ 100) über der Tisch-UI derselben Ebene.
# Tisch-Overlays (Farbwahl, Hilfe, Sichtschutz, Rundenende) gehören in eine CanvasLayer mit höherer Nummer.
# Der Tisch (Modul F1b/F2) setzt Karten, spielbare Karten und Ablage; Ausspielen ist optimistisch: Die Karte verlässt die Hand
# sofort, cancel_play(id) holt sie zurück (Host lehnt ab), take_card(id) übergibt den Knoten an die Regie, set_cards ohne sie
# blendet aus. Neue Runde (view.round) und Spielerwechsel (view.seat bzw. reset_for_player) räumen die Hand sofort.
# Persönliche Einstellung „Spielbare Karten hervorheben“ (App.settings "hervorheben", Standard an, live über settings.changed;
# AGENTS.md Nr. 24): aus = kein Rand, kein Leuchten, kein Anheben, kein Abdunkeln; jede Karte lässt sich hochziehen, eine
# unpassende springt schüttelnd zurück (play_denied, keine Strafe). Gilt für jede Hand auf diesem Gerät, auch beim Weitergeben.

signal play_requested(id: int, drop_global: Vector2)
signal help_requested(id: int, face: String)
signal drag_started(id: int, face: String)
signal drag_moved(global: Vector2)
signal drag_ended(id: int, global: Vector2, played: bool)
signal order_changed(ids: Array)
signal selection_changed(id: int)
signal play_denied(id: int)             # Ausspielen versucht, Karte nicht spielbar: Karte schüttelt, Hinweis zeigt der Tisch
signal sort_mode_changed(mode: String)  # Sortierung hat sich ohne set_sort_mode geändert (Umsortieren → "manuell", Spielerwechsel)
signal big_view_changed(id: int)        # Großansicht geöffnet (Kartenkennung) bzw. geschlossen (−1)
signal drag_armed(id: int, armed: bool) # Ziehen nach oben ist scharf: Loslassen spielt aus (Geisterbild auf der Ablage)
signal pick_changed(ids: Array)          # Auswahl „Farbe mit ablegen“ geändert (gewählte Kennungen)

const DP := HandLayout.DP
const LIFT_PLAYABLE := 8.0 * DP
const LIFT_SELECTED := 23.0 * DP
const LIFT_REORDER := 30.0 * DP
const ARC_LIFT := 20.0 * DP             # weite Wege beim Umsortieren laufen über einen Bogen
const BIG_SCALE := 1.4                  # Großansicht
const BIG_GAP := 10.0 * DP              # Abstand Kartenunterkante – Finger
const BADGE_R := 15.0 * DP              # „?“
const BADGE_HIT := 26.0 * DP
const SHIMMER_S := 3.0
const DEAL_STAGGER_S := 0.05            # Austeilen: Abstand je Karte
const STAGGER_S := 0.015                # Versatz je Karte beim Umsortieren
const FLIP_WAVE_S := 0.02               # Welle beim Wenden
const FLIP_CARD_S := 0.2
const FLIP_PAUSE_S := 0.1               # Pause nach dem Flip, bevor die Hand neu sortiert
const PLAY_TIMEOUT_MS := 4000.0         # ausgespielt, aber keine Antwort: zurück in die Hand
const OMEGA := 17.0                     # Federn der Karten
const ZETA := 0.8
const DRAG_OMEGA := 40.0
const SCROLL_OMEGA := 5.0               # Einrasten (ω > 1/τ: kein Überschwingen)
const TICK_MS := 35.0                   # Haptik-Raster höchstens alle 35 ms
const EDGE_SCROLL := 6.0                # Karten/s beim Umsortieren am Rand des Karussells
const TILT_PER_SPEED := 0.02            # Schwung-Neigung: Scherung (rad) je Karte/s …
const TILT_MAX := deg_to_rad(12.0)      # … höchstens ±12°, federt zurück
const FLING_STOP := 2.0                 # Karten/s: ein Tipp in einen schnelleren Schwung hält nur an
const TOP_Z := 50                       # z_index der obersten Schicht (gezogen, groß, ausgespielt, Abdunklung); höchstens 100
const TOP_KEY := 1000000                # Sortierschlüssel ab hier = oberste Schicht
const GHOST_ALPHA := 0.45               # Geisterbild auf der Ablage
const DEFAULT_RECT := Rect2(270, 500, 1060, 220)
const SIDE_MARGIN := 270.0              # Standard-Handbereich: links/rechts frei für die Knöpfe …
const HAND_H := 220.0                   # … und 220 px hoch am unteren Rand

var layout_rect := DEFAULT_RECT: set = set_layout_rect
var sort_mode := "farbe"
var enforce_playable := true            # nur Karten aus set_playable dürfen ausgespielt werden
var dim_unplayable := true              # nicht spielbare Karten leicht abdunkeln, solange etwas spielbar ist
var deselect_on_outside := true         # Tipp außerhalb der Hand hebt die Auswahl auf
var play_target := Vector2.INF: set = set_play_target    # global: Ablage, zu der ausgespielte Karten fliegen (INF = bleiben)
var play_target_scale := 0.66
var spawn_from := Vector2.INF: set = set_spawn_from      # global: woher neue Karten kommen (Nachziehstapel); INF = von oben
var haptics := true
var reduced := false: set = set_reduced # Effektstufe „reduziert“: kein Glanzstreifen, keine Neigung, keine Bögen
var night := -1.0: set = set_night      # −1 = automatisch nach der aktiven Seite (hell = Tag); sonst 0 = Tag … 1 = Nacht
var color_rim := true                   # spielbare Karten mit Rand in der aktuellen Farbe (apply_view: view.color)
var highlight := true: set = set_highlight   # persönliche Einstellung „Spielbare Karten hervorheben“ (App.settings "hervorheben")
var show_playable := true: set = set_show_playable   # Tisch: aus, wenn ohnehin jede Karte geht (Einsatz im Glücksspiel)
var accent := Color(0, 0, 0, 0)         # aktuelle Farbe für den Rand (Alpha 0 = Standardglühen)
var clock_ms := -1.0                    # Testuhr (≥ 0 ersetzt Time.get_ticks_msec)
var dp := DP                            # Pixel je dp für Gestenschwellen (aus der Bildschirmdichte)

var _slots := {}                        # id → Slot
var _order: Array[int] = []
var _leaving: Array[Slot] = []
var _gaps := PackedInt32Array()
var _mode: HandLayout.Mode = HandLayout.Mode.FAN
var _scroll := 0.0
var _scroll_v := 0.0
var _scroll_target := 0.0
var _scroll_drag := false
var _scroll_press := 0.0
var _user_scroll := false               # Schwung stammt vom Nutzer (nur dann Haptik-Raster)
var _fling_stop := false                # Berührung hat einen laufenden Schwung angehalten: Tipp wählt nichts
var _focus := -1.0
var _selected := -1
var _deselected_id := -1
var _deselected_ms := -10000.0
var _playable := {}
var _enabled := true
var _peek := false
var _gesture := HandLayout.Gesture.new()
var _touch := -1
var _press_id := -1
var _drag_id := -1
var _drag_kind := ""                    # "play" | "reorder"
var _drag_grab := Vector2.ZERO          # Kartenmitte − Finger
var _drag_changed := false
var _armed_id := -1
var _glided := false                    # die laufende Geste ist seitlich geglitten
var _sticky_press := false              # die laufende Geste begann auf der offenen Großansicht
var _finger := Vector2.ZERO
var _big_id := -1
var _big_sticky := false
var _big_pos := Vector2.ZERO
var _badge_pos := Vector2.ZERO
var _button_pos := Vector2.ZERO
var _help_hot := false
var _last_tick_index := 0
var _last_tick_ms := -1000.0
var _tilt := 0.0                        # Schwung-Neigung der Karussellkarten (Scherung)
var _tilt_prev := 0.0
var _overlay: Overlay
var _ghost: CardView
var _ghost_a := 0.0
var _rect_explicit := false             # layout_rect vom Tisch gesetzt (sonst folgt er dem sichtbaren Bereich)
var _rect_auto := false                 # _fit_to_view setzt layout_rect gerade selbst
var _auto_day := false                  # aktive Seite ist hell (Tagtisch)
var _round := -1
var _seat := -1
var _seat_state := {}                   # Platz → {sort, order}: Sortierung je Spieler beim Weitergeben
var _manual_seed: Array[int] = []       # gemerkte manuelle Reihenfolge für die nächste Hand
var _pick_cands := {}                   # Auswahl „Farbe mit ablegen“ (Phase discard_pick): wählbare Karten …
var _picked := {}                       # … und davon gewählte; leer = keine Auswahl
var _pick_open := false                 # Ablegen-Joker: Ablegefarbe wird durch Antippen gewählt (set_pick(…, true))
var _pick_col := ""                     # … die so gewählte Farbe


class Slot:
	extends RefCounted
	var id := -1
	var face := ""
	var back := ""
	var view: CardView
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rot := 0.0
	var rot_v := 0.0
	var scl := 1.0
	var scl_v := 0.0
	var target := Transform2D.IDENTITY
	var has_target := false
	var delay := 0.0
	var arc_pending := false
	var arc_total := 0.0
	var played := false
	var played_ms := 0.0
	var prev_index := 0
	var fade := 1.0
	var key := 0                        # Zeichenreihenfolge (größer = weiter oben)


func _init() -> void:
	_overlay = Overlay.new()
	add_child(_overlay)


func _ready() -> void:
	dp = _compute_dp()
	_gesture.dp = dp
	reduced = UiApp.reduced_effects()
	highlight = truthy(UiApp.setting("hervorheben", true))
	var app := UiApp.app()
	var st: Variant = app.get("settings") if app != null else null
	if st is Object and (st as Object).has_signal("changed"):
		(st as Object).connect("changed", _on_setting_changed)
	if not get_viewport().size_changed.is_connected(_fit_to_view):
		get_viewport().size_changed.connect(_fit_to_view)
	_fit_to_view()


func _notification(what: int) -> void:
	# Fokusverlust (Benachrichtigungsleiste, Anruf, Systemgeste): laufende Geste abbrechen, nichts ausspielen
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _gesture.is_active() or _big_id != -1 or _drag_id != -1:
			touch_cancel()


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "effekte":
		reduced = str(value) == "reduziert"
	elif key == "hervorheben":
		highlight = truthy(value)


# Einstellungswert als Schalter (bool; zur Sicherheit auch „an“/„true“/1 aus JSON)
static func truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return str(v).to_lower() in ["true", "an", "ja", "1"]


# „Spielbare Karten hervorheben“ aus: kein Rand, kein Leuchten, kein Anheben, kein Abdunkeln. Ausspielen bleibt geprüft: Eine
# unpassende Karte lässt sich trotzdem hochziehen und loslassen; sie springt mit kurzem Schütteln zurück (play_denied).
func set_highlight(on: bool) -> void:
	highlight = on


func set_show_playable(on: bool) -> void:
	show_playable = on


# Spielbare Karten sichtbar markieren?
func marks_playable() -> bool:
	return highlight and show_playable


# ---------------------------------------------------------------- Schnittstelle

# Karten der Hand: [{id, face, back}] (face = aktive Seite). Neue Karten fliegen ein und schimmern 3 s, fehlende blenden aus,
# gewendete Karten (Flip: andere Seite, die alte ist jetzt Rückseite) wenden sich als Welle von links nach rechts; nach 100 ms
# Pause federt die Hand in die neue Sortierung. Eine andere Karte unter derselben Kennung (Kennungen werden je Runde neu
# gemischt) ist kein Flip: Die alte blendet aus, die neue wird ausgeteilt.
func set_cards(cards: Array) -> void:
	var now := _now()
	var incoming := {}
	for c in cards:
		incoming[int(c.id)] = c
	for id in _slots.keys():
		if not incoming.has(id):
			_remove_slot(id)
	var turned: Array[Slot] = []
	var added: Array[Slot] = []
	var live: Array = []
	for c in cards:
		var id := int(c.id)
		var face := str(c.get("face", ""))
		var back := str(c.get("back", ""))
		var s: Slot = _slots.get(id)
		if s != null and s.face != face and not _is_flip(s, face, back):
			_remove_slot(id)
			s = null
		if s == null:
			s = _make_slot(id, face, back)
			added.append(s)
		elif s.face != face:
			# Seitenwechsel: angezeigt bleibt zunächst das alte Gesicht (jetzt Rückseite), dann wendet die Karte.
			# Ohne Rückseiten-Angabe (peek_own_backs aus) ist die neue Rückseite das alte Gesicht.
			var nb := back if back != "" else s.face
			s.view.setup(id, face, nb, s.view.current_key() == face)
			s.face = face
			s.back = nb
			turned.append(s)
		elif back != "" and s.back != back:
			s.back = back
			s.view.setup(id, face, back, s.view.showing_front)
		if s.played and now - s.played_ms < PLAY_TIMEOUT_MS:
			continue
		s.played = false
		live.append({"id": id, "face": s.face, "back": s.back})
	# Austeilen: keine Karte der bisherigen Hand bleibt (leere Hand, neue Runde)
	var dealing := added.size() == cards.size()
	var new_order := _ordered(live)
	_manual_seed.clear()
	var base_delay := _wave(turned, 0.0, FLIP_WAVE_S, FLIP_CARD_S)
	_apply_order(new_order, base_delay, not turned.is_empty())
	# Austeilen: Karten fliegen nacheinander ein (ohne Schimmern); sonst schimmern neue Karten 3 s
	var k := 0
	for id in _order:
		var s: Slot = _slots[id]
		if added.has(s):
			_spawn(s, k * DEAL_STAGGER_S if dealing else 0.0, not dealing)
			k += 1
	if _selected != -1 and not _order.has(_selected):
		_set_selected(-1)


# Kennungen der Karten, die jetzt ausgespielt werden dürfen (hints.playable).
func set_playable(ids: Array) -> void:
	_playable.clear()
	for id in ids:
		_playable[int(id)] = true


# "farbe" | "wert" | "punkte" | "manuell"; automatische Modi sortieren sofort (Federn, 15 ms Versatz, Bogen für weite Wege).
func set_sort_mode(mode: String) -> void:
	if not CardSort.MODES.has(mode) or mode == sort_mode:
		return
	sort_mode = mode
	if mode == "manuell":
		_gaps = PackedInt32Array()
		return
	var before := _order.duplicate()
	_apply_order(_ordered(_live_cards()), 0.0, false)
	if before != _order:
		order_changed.emit(_order.duplicate())


# Eigene Rückseiten ansehen: alle Karten wenden sich zur Rückseite, solange an (Ausspielen ist dann gesperrt).
func set_peek_backs(on: bool) -> void:
	if on == _peek:
		return
	_peek = on
	_close_big()
	_cancel_gesture()
	if on:
		_set_selected(-1)
	var k := 0
	for id in _order:
		var s: Slot = _slots[id]
		if s.back != "":
			_turn(s, not on, k * FLIP_WAVE_S)
			k += 1


# Eingaben an/aus (z. B. Sichtschutz, Flip-Übergang). Laufende Gesten brechen ab, die Karte federt zurück.
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		_cancel_gesture()
		_close_big()
		_focus = -1.0


# Handbereich (lokal) nach der Geometrie des Tisches; danach folgt er nicht mehr automatisch dem sichtbaren Bereich.
func set_layout_rect(r: Rect2) -> void:
	layout_rect = r
	if not _rect_auto:
		_rect_explicit = true
	var w := HandLayout.card_width(r.size.y)
	for s in _slots.values():
		(s as Slot).view.width = w


# Handbereich wieder automatisch am unteren Rand des sichtbaren Bereichs ausrichten.
func use_auto_layout() -> void:
	_rect_explicit = false
	_fit_to_view()


# Standard-Handbereich für einen sichtbaren Bereich: unten, 220 px hoch, links/rechts 270 px frei.
static func default_rect(view: Rect2) -> Rect2:
	return Rect2(view.position.x + SIDE_MARGIN, view.end.y - HAND_H, maxf(view.size.x - 2.0 * SIDE_MARGIN, 200.0), HAND_H)


# Ablage (global): ausgespielte Karten fliegen dorthin, das Geisterbild beim Hochziehen liegt dort. INF = aus.
func set_play_target(g: Vector2) -> void:
	play_target = g


# Nachziehstapel (global): neue Karten kommen von dort. INF = von oben.
func set_spawn_from(g: Vector2) -> void:
	spawn_from = g


func set_reduced(on: bool) -> void:
	reduced = on
	if on:
		_tilt = 0.0


# Tag/Nacht des Tisches (0 = heller Papiertisch, 1 = Nacht); −1 = nach der aktiven Seite der Karten.
func set_night(v: float) -> void:
	night = v


func is_peeking() -> bool:
	return _peek


func is_enabled() -> bool:
	return _enabled


# Ziehen nach oben ist scharf (Loslassen spielt aus).
func is_play_armed() -> bool:
	return _armed_id != -1


func get_order() -> Array[int]:
	return _order.duplicate()


func get_selected() -> int:
	return _selected


func get_mode() -> HandLayout.Mode:
	return _mode


func get_scroll() -> float:
	return _scroll


func card_view(id: int) -> CardView:
	var s: Slot = _slots.get(id)
	return s.view if s != null else null


func select(id: int) -> void:
	_set_selected(id if _order.has(id) else -1)


# Ausspielen der angehobenen Karte (z. B. Tipp auf die Ablage). Kurz nach einem Abwählen durch Tipp außerhalb gilt noch die
# zuletzt gewählte Karte, damit die Reihenfolge der Eingabeverarbeitung keine Rolle spielt.
func play_selected() -> bool:
	var id := _selected
	if id == -1 and _now() - _deselected_ms < 400.0:
		id = _deselected_id
	if id == -1 or not _order.has(id):
		return false
	var s: Slot = _slots[id]
	return _try_play(id, s.view.global_position)


# Host hat das Ausspielen abgelehnt: Karte federt zurück an ihren Platz und schüttelt.
func cancel_play(id: int) -> void:
	var s: Slot = _slots.get(id)
	if s == null or not s.played:
		return
	s.played = false
	s.fade = 1.0
	var order: Array[int] = _order.duplicate()
	order.insert(clampi(s.prev_index, 0, order.size()), id)
	if sort_mode != "manuell":
		order = CardSort.sort_ids(_cards_of(order), sort_mode)
	_apply_order(order, 0.0, false)
	s.view.shake()


# Kartenknoten an die Regie übergeben (Flug zur Ablage): ohne Eltern, transform = bisheriges globales Transform.
# Räumt Auswahl, Großansicht und Ziehen dieser Karte auf.
func take_card(id: int) -> CardView:
	var s: Slot = _slots.get(id)
	if s == null:
		return null
	if _drag_id == id:
		_cancel_gesture()
	if _big_id == id:
		_close_big()
	if _armed_id == id:
		_set_armed(-1)
	if _press_id == id:
		_press_id = -1
	if _selected == id:
		_set_selected(-1)
	var xf := s.view.global_transform
	_slots.erase(id)
	_order.erase(id)
	_refresh_mode()
	_gaps = CardSort.group_starts(_faces(_order), sort_mode)
	remove_child(s.view)
	s.view.transform = xf
	s.view.z_index = 0
	s.view.elevation = 0.0
	s.view.skew = 0.0
	s.view.modulate.a = 1.0
	return s.view


# Hand sofort leeren (neue Runde, Sichtschutz): ohne Ausblenden, Gesten/Großansicht/Auswahl/Schwung zurückgesetzt.
# Sortierung und Rückseiten-Ansicht bleiben.
func clear() -> void:
	_save_seat_state()
	_cancel_gesture()
	_close_big()
	_set_armed(-1)
	for s in _slots.values():
		_free_view((s as Slot).view)
	for s in _leaving:
		_free_view(s.view)
	_slots.clear()
	_leaving.clear()
	_order.clear()
	_gaps = PackedInt32Array()
	_mode = HandLayout.Mode.FAN
	_focus = -1.0
	_scroll = 0.0
	_scroll_v = 0.0
	_scroll_target = 0.0
	_scroll_drag = false
	_user_scroll = false
	_tilt = 0.0
	_tilt_prev = 0.0
	_ghost_a = 0.0
	if _ghost != null:
		_ghost.visible = false
	if _selected != -1:
		_set_selected(-1)
	_deselected_id = -1


# Spielerwechsel (Weitergeben): alles vom Vorgänger zurücksetzen – Karten, Rückseiten-Ansicht, Auswahl, Großansicht, Ziehen,
# spielbare Karten. Mit seat ≥ 0 wird die Sortierung je Platz gemerkt und für den neuen Platz wiederhergestellt (auch die
# manuelle Reihenfolge); ein Platz ohne gemerkten Stand behält eine automatische Sortierung, „manuell“ wird zu „farbe“.
# apply_view ruft das selbst auf, wenn view.seat wechselt.
func reset_for_player(seat := -1) -> void:
	clear()
	_peek = false
	_playable.clear()
	_manual_seed.clear()
	var want := sort_mode
	var st: Dictionary = _seat_state.get(seat, {}) if seat >= 0 else {}
	if st.has("sort"):
		want = str(st["sort"])
		if want == "manuell":
			_manual_seed.assign(st.get("order", []))
	elif want == "manuell":
		want = "farbe"
	if seat >= 0:
		_seat = seat
	if want != sort_mode:
		sort_mode = want
		sort_mode_changed.emit(want)


# ---------------------------------------------------------------- Adapter für den Tisch (TableView, Modul F1b; alle optional)

# Sicht des eigenen Platzes übernehmen: Handkarten und spielbare Karten (hints.playable). Neue Runde (view.round) räumt die
# Hand vor dem Austeilen; ein anderer Platz (view.seat, Weitergeben) setzt den Zustand zurück; Sichtschutz (seat < 0) leert.
func apply_view(v: Dictionary) -> void:
	if v.has("seat"):
		var seat := int(v["seat"])
		if seat < 0:
			clear()
			return
		if _seat >= 0 and seat != _seat:
			reset_for_player(seat)
		_seat = seat
	if v.has("round"):
		var r := int(v["round"])
		if _round != -1 and r != _round:
			clear()
		_round = r
	var col := str(v.get("color", ""))
	accent = UiPalette.glow(col) if color_rim and col != "" else Color(0, 0, 0, 0)
	set_cards(v.get("hand", []))
	var hints: Dictionary = v.get("hints", {})
	set_playable(hints.get("playable", []))


# Gezogene Karte kommt an (die Regie hat sie bis from_global geflogen): sofort einsortieren, schimmert 3 s.
func receive_card(card: Dictionary, from_global: Vector2) -> void:
	var id := int(card.get("id", -1))
	if id < 0 or _slots.has(id):
		return
	var s := _make_slot(id, str(card.get("face", "")), str(card.get("back", "")))
	var cards := _live_cards()
	cards.append({"id": id, "face": s.face, "back": s.back})
	var keep := spawn_from
	spawn_from = from_global
	_apply_order(_ordered(cards), 0.0, false)
	_spawn(s, 0.0, true)
	s.scl = 0.8
	s.view.scale = Vector2(s.scl, s.scl)
	spawn_from = keep


# Wohin gezogene Karten fliegen (global): Mitte der Hand, auf Höhe des sichtbaren Streifens.
func landing_point() -> Vector2:
	var h := HandLayout.card_width(layout_rect.size.y) * HandLayout.CARD_ASPECT
	return to_global(Vector2(layout_rect.get_center().x, layout_rect.end.y - h * 0.25))


# Flip-Welle im Takt der Regie: faces = {id: neues Gesicht}; Karte k (von links) wendet nach delay + k·step in dur Sekunden,
# danach 100 ms Pause und Neusortierung nach der neuen Seite.
func flip_wave(delay: float, step_s: float, dur: float, faces: Dictionary) -> void:
	var turned: Array[Slot] = []
	for key in faces:
		var s: Slot = _slots.get(int(key))
		var face := str(faces[key])
		if s == null or face == "" or s.face == face:
			continue
		var old := s.face
		s.view.setup(s.id, face, old, s.view.current_key() == face)
		s.back = old
		s.face = face
		turned.append(s)
	if turned.is_empty():
		return
	var base := _wave(turned, delay, step_s, dur)
	_apply_order(_ordered(_live_cards()), base, true)


func set_input_locked(on: bool) -> void:
	set_enabled(not on)


# Anzahl eigener Karten je Farbe der aktiven Seite (Farbfelder des Wünschers).
# Auswahl „Farbe mit ablegen“ (Phase discard_pick): candidates sind wählbar und anfangs alle gewählt. Tippen (oder Hochziehen)
# wählt ab bzw. wieder an; übrige Karten sind abgedunkelt. Leere Liste bzw. clear_pick() beendet die Auswahl.
# open (Ablegen-Joker, 1.4.9): Die Ablegefarbe ist noch offen. candidates sind alle farbigen Karten, anfangs keine gewählt; das
# Antippen einer Karte wählt ihre Farbe (alle Kandidaten dieser Farbe), weiteres Antippen derselben Farbe wählt einzeln ab/an, eine
# Karte einer anderen Farbe wechselt die Farbe.
func set_pick(candidates: Array, open := false) -> void:
	_pick_cands.clear()
	_picked.clear()
	_pick_open = open
	_pick_col = ""
	for raw in candidates:
		_pick_cands[int(raw)] = true
		if not open:
			_picked[int(raw)] = true
	if not _pick_cands.is_empty() and _selected != -1:
		_set_selected(-1)


func clear_pick() -> void:
	_pick_cands.clear()
	_picked.clear()
	_pick_open = false
	_pick_col = ""


# Offene Ablegefarbe: die zuletzt per Antippen gewählte Farbe ("" = noch keine)
func get_pick_color() -> String:
	return _pick_col


func _card_color(id: int) -> String:
	if not _slots.has(id):
		return ""
	return str(CardSort.parse((_slots[id] as Slot).face).color)


# Antippen bzw. Hochziehen während der Auswahl
func _pick_tap(id: int) -> void:
	if not _pick_open:
		toggle_pick(id)
		return
	if not _pick_cands.has(id) or not _order.has(id):
		return
	var col := _card_color(id)
	if col == "" or col == _pick_col:
		toggle_pick(id)
		return
	_pick_col = col
	_picked.clear()
	for c in _order:
		if _pick_cands.has(c) and _card_color(c) == col:
			_picked[c] = true
	_vibrate(12, 0.4)
	pick_changed.emit(get_pick())


func is_picking() -> bool:
	return not _pick_cands.is_empty()


func get_pick() -> Array:
	var out: Array = []
	for id in _order:
		if _picked.has(id):
			out.append(id)
	return out


func toggle_pick(id: int) -> void:
	if not _pick_cands.has(id) or not _order.has(id):
		return
	if _picked.has(id):
		_picked.erase(id)
	else:
		_picked[id] = true
	_vibrate(8, 0.3)
	pick_changed.emit(get_pick())


func own_color_counts() -> Dictionary:
	var counts := {}
	for id in _order:
		var c := str(CardSort.parse((_slots[id] as Slot).face).color)
		if c != "":
			counts[c] = int(counts.get(c, 0)) + 1
	return counts


# Großansicht öffnen bzw. schließen (z. B. aus der Kartenhilfe zurück).
func close_big_view() -> void:
	_close_big()


func is_big_view_open() -> bool:
	return _big_id != -1


# Kartenmitte in globalen Koordinaten (Regie, Kontrollbilder).
func card_global_position(id: int) -> Vector2:
	var s: Slot = _slots.get(id)
	return s.view.global_position if s != null else Vector2.INF


# Umriss der Handkarten (lokal, auf den Handbereich begrenzt): Schein am eigenen Zug (0.1.4). Leer ohne Karten. Gerechnet aus den
# Zielplätzen, nicht aus den gerade fliegenden Karten, damit der Schein beim Austeilen nicht mitwandert (Nutzerbefund 06.10.2026).
func cards_rect() -> Rect2:
	var r := Rect2()
	var first := true
	for id in _order:
		var s: Slot = _slots.get(id)
		if s == null or s.view == null:
			continue
		var sz := s.view.card_size() * (s.target.get_scale().x if s.has_target else s.scl)
		var c := s.target.origin if s.has_target else s.pos
		var cr := Rect2(c - sz * 0.5, sz)
		r = cr if first else r.merge(cr)
		first = false
	if first:
		return Rect2()
	var lim := layout_rect.grow_individual(0.0, 40.0, 0.0, 400.0)
	return r.intersection(lim) if r.intersects(lim) else Rect2()


# Karten, die gerade in der Hand liegen (ohne die noch anfliegenden der Regie)
func card_count() -> int:
	return _order.size()


# Fliegen noch Karten an (Austeilen, Ziehen) oder sind sie weit vom Zielplatz entfernt?
func is_settling() -> bool:
	for id in _order:
		var s: Slot = _slots.get(id)
		if s == null:
			continue
		if s.delay > 0.0 or s.arc_pending or (s.has_target and s.pos.distance_to(s.target.origin) > 60.0):
			return true
	return false


# „?“ der Großansicht nicht auf diese Flächen legen (global, z. B. der Mau-Knopf; Gerätetest 0.1.3)
var avoid_global: Array[Rect2] = []


func _badge_blocked(p: Vector2) -> bool:
	var gp := to_global(p)
	var gr := BADGE_R * global_scale.x + 6.0
	for r in avoid_global:
		if r.grow(gr).has_point(gp):
			return true
	return false


# ---------------------------------------------------------------- Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var p := _event_local(st.position)
		if st.pressed:
			if _touch != -1 and st.index == _touch:
				touch_cancel()        # Loslassen ging verloren: neu beginnen
			if _touch == -1 and touch_down(p):
				_touch = st.index
				get_viewport().set_input_as_handled()
		elif st.index == _touch:
			_touch = -1
			if st.canceled:
				touch_cancel()        # vom System abgebrochen (ACTION_CANCEL): nichts ausspielen
			else:
				touch_up(p)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch:
			touch_move(_event_local(sd.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _touch == -1:
		var mm := event as InputEventMouseMotion
		if mm.button_mask == 0 and not DisplayServer.is_touchscreen_available():
			_hover(_event_local(mm.position))


# Finger setzt auf (lokale Koordinaten). true = Geste gehört der Hand.
func touch_down(p: Vector2, t_ms := -1.0) -> bool:
	if not _enabled:
		return false
	var now := _time(t_ms)
	_sticky_press = false
	_fling_stop = false
	if _big_sticky:
		# Großansicht offen: „?“ = Hilfe; auf der Karte nach oben wischen = ausspielen; sonst schließen
		var id := _big_id
		if _button_pos.distance_to(p) <= BADGE_HIT:
			_emit_help(id)
			_close_big()
			return true
		var bs: Slot = _slots.get(id)
		if bs == null or _peek or not bs.view.contains_global_point(to_global(p)):
			_close_big()
			return true
		_sticky_press = true
		_press_id = id
		_finger = p
		_glided = false
		_gesture.press(now, p)
		_gesture.play_dist = _play_dist()
		return true
	var hit := _card_at(p)
	if hit == -1 and not layout_rect.has_point(p):
		if deselect_on_outside and _selected != -1:
			_set_selected(-1)
		return false
	_press_id = hit
	_finger = p
	_glided = false
	_gesture.press(now, p)
	_gesture.play_dist = _play_dist()
	_gesture.help_dist = HandLayout.Gesture.HELP_DP * dp
	if _mode == HandLayout.Mode.CAROUSEL:
		_fling_stop = absf(_scroll_v) > FLING_STOP
		_scroll_press = _scroll
		_scroll_v = 0.0
		_scroll_target = _scroll
	elif _mode == HandLayout.Mode.LENS and not _peek:
		_focus = _focus_at(p.x)
	return true


func touch_move(p: Vector2, t_ms := -1.0) -> void:
	if not _gesture.is_active():
		return
	_finger = p
	var ev := _gesture.move(_time(t_ms), p)
	if _sticky_press:
		# Druck auf die offene Großansicht: nur Ausspielen nach oben
		if ev == "play_drag":
			_begin_play_drag()
		if _drag_id != -1:
			drag_moved.emit(to_global(p))
			_update_armed()
		return
	match ev:
		"hold":
			_on_hold()
		"horizontal":
			_glided = true
			if _mode == HandLayout.Mode.CAROUSEL:
				_scroll_drag = true
				_user_scroll = true
				_scroll_press = _scroll
		"play_drag":
			_begin_play_drag()
		"reorder":
			_begin_reorder()
		"help_drag":
			pass
	match _gesture.state:
		HandLayout.Gesture.S.HORIZONTAL:
			if _mode == HandLayout.Mode.CAROUSEL:
				var raw := _scroll_press - (p.x - _gesture.start.x) / HandLayout.FISH_S_MAX
				_scroll = HandLayout.rubber_scroll(raw, _order.size(), HandLayout.FISH_S_MAX, layout_rect.size.x)
				_scroll_target = _scroll
			elif _mode == HandLayout.Mode.LENS and not _peek:
				_focus = _focus_at(p.x)
		HandLayout.Gesture.S.PLAY_DRAG:
			if _drag_id != -1:
				drag_moved.emit(to_global(p))
				_update_armed()
		HandLayout.Gesture.S.REORDER:
			_update_reorder()
		HandLayout.Gesture.S.HELP:
			if _gesture.help_armed != _help_hot:
				_help_hot = _gesture.help_armed
				if _help_hot:
					_vibrate(10, 0.3)


func touch_up(p: Vector2, t_ms := -1.0) -> void:
	if not _gesture.is_active():
		return
	_finger = p
	var ev := _gesture.release(_time(t_ms), p)
	if _sticky_press:
		_sticky_press = false
		if _drag_kind == "play":
			_end_play_drag(ev == "play")
		_close_big()
		_press_id = -1
		return
	match ev:
		"tap", "double_tap":
			if not _fling_stop:
				_on_tap(_press_id)
		"play":
			_end_play_drag(true)
		"cancel":
			if _drag_kind == "play":
				_end_play_drag(false)
			_close_big()
		"help":
			_emit_help(_big_id)
			_close_big()
		"hold_release":
			if _big_id != -1:
				_big_sticky = true
				_button_pos = _sticky_button_pos()
		"reorder_end":
			_end_reorder()
		"horizontal_end":
			if _mode == HandLayout.Mode.CAROUSEL and _scroll_drag:
				var v := -_gesture.velocity.x / HandLayout.FISH_S_MAX
				_scroll_target = float(HandLayout.snap(HandLayout.project(_scroll, v), _order.size()))
				_scroll_v = _fling_velocity(v, _scroll_target - _scroll)
	_scroll_drag = false
	if _mode == HandLayout.Mode.CAROUSEL:
		_scroll_target = float(HandLayout.snap(_scroll_target, _order.size()))
	_focus = -1.0
	_press_id = -1
	_fling_stop = false


# Berührung vom System abgebrochen (canceled, Fokusverlust): Geste abbrechen, nichts ausspielen, Großansicht zu.
func touch_cancel() -> void:
	_cancel_gesture()
	_close_big()
	_focus = -1.0
	_fling_stop = false


func _hover(p: Vector2) -> void:
	if not _enabled or _peek or _mode != HandLayout.Mode.LENS or _big_id != -1:
		return
	_focus = _focus_at(p.x) if layout_rect.grow(10.0).has_point(p) else -1.0


func _on_tap(id: int) -> void:
	if is_picking():
		_pick_tap(id)
		return
	if id == -1 or not _order.has(id):
		if _selected != -1:
			_set_selected(-1)
		return
	if _mode == HandLayout.Mode.CAROUSEL:
		_scroll_target = float(_order.find(id))
		_user_scroll = false
	if _peek:
		return
	if id == _selected:
		_try_play(id, (_slots[id] as Slot).view.global_position)
	else:
		_set_selected(id)
		_vibrate(8, 0.3)


# Startgeschwindigkeit des Einrastens: höchstens ω·|Weg| in Richtung des Ziels, sonst überschwingt die kritisch gedämpfte Feder
# (vor allem, wenn das Ziel am Kartenende begrenzt wurde); vom Ziel weg gar nicht.
func _fling_velocity(v: float, to_target: float) -> float:
	if v * to_target <= 0.0:
		return 0.0
	return signf(v) * minf(absf(v), SCROLL_OMEGA * absf(to_target))


func _on_hold() -> void:
	var id := _press_id
	if id == -1 or not _order.has(id):
		return
	_scroll_drag = false
	_scroll_target = float(HandLayout.snap(_scroll, _order.size()))
	_focus = -1.0
	_big_id = id
	_big_sticky = false
	_help_hot = false
	var s: Slot = _slots[id]
	var ch := s.view.card_size().y * BIG_SCALE
	var vr := _view_rect()
	# „?“ unter dem Finger, höchstens so tief, dass es sichtbar bleibt. Scharf wird es, sobald der Finger seine Mitte erreicht;
	# am unteren Rand (Finger schon auf Höhe des „?“) genügt ein kurzer Zug nach unten mit kleinerer Toleranz.
	var help := HandLayout.Gesture.HELP_DP * dp
	var by := minf(_finger.y + help, vr.end.y - BADGE_R * 0.65)
	_badge_pos = Vector2(_finger.x, by)
	var room := vr.end.y - _finger.y
	_gesture.hold_tol = clampf((room - 2.0) * 0.8, 2.5 * dp, _gesture.tol())
	_gesture.help_dist = clampf(by - _finger.y - BADGE_R * 0.35, minf(_gesture.hold_tol, help), help)
	var bottom := minf(_finger.y - BIG_GAP, _badge_pos.y - BADGE_R - 6.0 * DP)
	var half_w := s.view.width * BIG_SCALE * 0.5 + 8.0 * DP
	_big_pos = Vector2(clampf(s.pos.x, vr.position.x + half_w, vr.end.x - half_w), maxf(bottom - ch * 0.5, vr.position.y + ch * 0.5 + 4.0 * DP))
	_vibrate(8, 0.3)
	big_view_changed.emit(id)


# Karte zum Ausspielen: aus der Großansicht die gehaltene, nach seitlichem Gleiten die unter dem Finger (Lupe: die vergrößerte),
# sonst die beim Aufsetzen getroffene.
func _begin_play_drag() -> void:
	var id := _press_id
	if _big_id != -1:
		id = _big_id
	elif _glided:
		if _mode == HandLayout.Mode.LENS and _focus >= 0.0 and not _order.is_empty():
			id = _order[clampi(roundi(_focus), 0, _order.size() - 1)]
		else:
			id = _card_at(_finger)
	if id == -1 or _peek or not _order.has(id):
		_gesture.cancel()
		_close_big()
		return
	var s: Slot = _slots[id]
	_scroll_drag = false
	_scroll_target = float(HandLayout.snap(_scroll, _order.size()))
	_focus = -1.0
	_drag_id = id
	_drag_kind = "play"
	_drag_grab = s.pos - _finger
	if _big_id != -1:
		# aus der Großansicht: Karte rückt an den Finger (Finger hält das untere Drittel)
		_drag_grab = Vector2(0.0, -s.view.card_size().y * 0.3)
		_close_big()
	drag_started.emit(id, s.face)
	drag_moved.emit(to_global(_finger))


func _end_play_drag(played: bool) -> void:
	var id := _drag_id
	_drag_id = -1
	_drag_kind = ""
	_set_armed(-1)
	if id == -1:
		return
	var g := to_global(_finger)
	var ok := played and _enabled and not _peek
	if ok:
		ok = _try_play(id, g)
	drag_ended.emit(id, g, ok)


# Scharf = Loslassen spielt aus (nur spielbare Karten; nicht spielbare würden abgelehnt). Ohne Hervorheben verrät auch das
# Geisterbild nichts: Jede Karte wird scharf, eine unpassende springt beim Loslassen schüttelnd zurück.
func _update_armed() -> void:
	var on := _drag_kind == "play" and _drag_id != -1 and _gesture.play_armed and not _peek \
		and (not enforce_playable or not highlight or _playable.has(_drag_id))
	_set_armed(_drag_id if on else -1)


func _set_armed(id: int) -> void:
	if id == _armed_id:
		return
	var old := _armed_id
	_armed_id = id
	if old != -1:
		drag_armed.emit(old, false)
	if id != -1:
		drag_armed.emit(id, true)


func _begin_reorder() -> void:
	var id := _big_id if _big_id != -1 else _press_id
	_close_big()
	if id == -1 or not _order.has(id):
		_gesture.cancel()
		return
	var s: Slot = _slots[id]
	_drag_id = id
	_drag_kind = "reorder"
	_drag_grab = Vector2(0.0, -s.view.card_size().y * 0.3)
	_drag_changed = false


func _update_reorder() -> void:
	if _drag_id == -1:
		return
	var n := _order.size()
	var cur := _order.find(_drag_id)
	var x := _finger.x - layout_rect.position.x
	var f := HandLayout.index_at(n, x, _scroll, _mode, layout_rect.size.x, layout_rect.size.y, _gaps)
	var idx := clampi(roundi(f), 0, n - 1)
	if idx != cur and absf(f - float(cur)) > 0.6:
		if sort_mode != "manuell":
			sort_mode = "manuell"
			_gaps = PackedInt32Array()
			sort_mode_changed.emit(sort_mode)
		_order.remove_at(cur)
		_order.insert(idx, _drag_id)
		_drag_changed = true
		_vibrate(8, 0.2)


func _end_reorder() -> void:
	var id := _drag_id
	_drag_id = -1
	_drag_kind = ""
	if id != -1 and _mode == HandLayout.Mode.CAROUSEL:
		_scroll_target = float(_order.find(id))
	if _drag_changed:
		order_changed.emit(_order.duplicate())
	_drag_changed = false


func _cancel_gesture() -> void:
	if _drag_kind == "play" and _drag_id != -1:
		drag_ended.emit(_drag_id, to_global(_finger), false)
	elif _drag_kind == "reorder" and _drag_changed:
		order_changed.emit(_order.duplicate())
	_drag_id = -1
	_drag_kind = ""
	_drag_changed = false
	_set_armed(-1)
	_sticky_press = false
	_gesture.cancel()
	_touch = -1
	_press_id = -1
	_scroll_drag = false
	_scroll_target = float(HandLayout.snap(_scroll_target, _order.size()))


func _try_play(id: int, drop_global: Vector2) -> bool:
	if not _order.has(id) or _peek:
		return false
	if is_picking():                     # Auswahl läuft: Hochziehen wählt nur an/ab, gespielt wird nichts
		_pick_tap(id)
		return false
	var s: Slot = _slots[id]
	if enforce_playable and not _playable.has(id):
		s.view.shake()
		_vibrate(15, 0.4)
		if is_inside_tree():
			get_tree().create_timer(0.09).timeout.connect(func() -> void: _vibrate(15, 0.4))
		play_denied.emit(id)
		return false
	s.played = true
	s.played_ms = _now()
	s.prev_index = _order.find(id)
	_order.erase(id)
	if _selected == id:
		_selected = -1
		selection_changed.emit(-1)
	_refresh_mode()
	_gaps = CardSort.group_starts(_faces(_order), sort_mode)
	_vibrate(15, 0.5)
	play_requested.emit(id, drop_global)
	return true


func _emit_help(id: int) -> void:
	var s: Slot = _slots.get(id)
	if s != null:
		help_requested.emit(id, s.view.current_key())


func _close_big() -> void:
	if _big_id == -1:
		return
	_big_id = -1
	_big_sticky = false
	_help_hot = false
	big_view_changed.emit(-1)


func _sticky_button_pos() -> Vector2:
	var s: Slot = _slots.get(_big_id)
	if s == null:
		return _badge_pos
	var size := s.view.card_size() * BIG_SCALE
	var vr := _view_rect()
	var right := _big_pos + Vector2(size.x * 0.5 + BADGE_R + 12.0 * DP, size.y * 0.5 - BADGE_R - 4.0 * DP)
	if right.x + BADGE_R > vr.end.x - 4.0 * DP or _badge_blocked(right):
		right.x = _big_pos.x - size.x * 0.5 - BADGE_R - 12.0 * DP
	return right


func _set_selected(id: int) -> void:
	if id == _selected:
		return
	if _selected != -1:
		_deselected_id = _selected
		_deselected_ms = _now()
	_selected = id
	selection_changed.emit(id)


# ---------------------------------------------------------------- Ablauf

func _process(delta: float) -> void:
	step(delta)


# Ein Schritt der Darstellung (Tests rufen ihn mit fester Schrittweite auf).
func step(dt: float) -> void:
	dt = minf(dt, 0.05)
	var now := _now()
	if _gesture.is_active() and _gesture.tick(now) == "hold" and not _sticky_press:
		_on_hold()
	for id in _slots.keys():
		var s: Slot = _slots[id]
		if s.played and now - s.played_ms >= PLAY_TIMEOUT_MS:
			cancel_play(id)
	_update_scroll(dt)
	_update_cards(dt)
	_update_leaving(dt)
	_update_ghost(dt)
	_update_overlay(dt)
	_arrange()


func _update_scroll(dt: float) -> void:
	var n := _order.size()
	if _mode != HandLayout.Mode.CAROUSEL or n == 0:
		_tilt = 0.0
		_tilt_prev = 0.0
		_scroll = 0.0
		_scroll_v = 0.0
		_scroll_target = 0.0
		_user_scroll = false
		return
	if _drag_kind == "reorder":
		# am Rand des Karussells weiterdrehen
		var edge := 40.0 * DP
		var lx := _finger.x - layout_rect.position.x
		var dir := 0.0
		if lx < edge:
			dir = -(1.0 - lx / edge)
		elif lx > layout_rect.size.x - edge:
			dir = 1.0 - (layout_rect.size.x - lx) / edge
		if dir != 0.0:
			_scroll_target = clampf(_scroll_target + dir * EDGE_SCROLL * dt, 0.0, float(n - 1))
			_update_reorder()
	if not _scroll_drag:
		var r := HandLayout.spring(_scroll, _scroll_v, _scroll_target, SCROLL_OMEGA, 1.0, dt)
		_scroll = r.x
		_scroll_v = r.y
		if _user_scroll and absf(_scroll_v) < 0.05 and absf(_scroll - _scroll_target) < 0.02:
			_user_scroll = false
	# Haptik-Raster nur, wenn der Nutzer dreht (Ziehen oder sein Schwung), nicht bei Verschiebungen durch die Hand selbst
	var idx := roundi(clampf(_scroll, 0.0, float(n - 1)))
	if idx != _last_tick_index:
		_last_tick_index = idx
		var now := _now()
		if (_scroll_drag or _user_scroll) and now - _last_tick_ms >= TICK_MS:
			_last_tick_ms = now
			_vibrate(10, 0.2)
	# Schwung-Neigung aus der tatsächlichen Scrollgeschwindigkeit (auch während des Ziehens)
	var speed := (_scroll - _tilt_prev) / maxf(dt, 0.001)
	_tilt_prev = _scroll
	var tilt_target := 0.0 if reduced else clampf(speed * TILT_PER_SPEED, -TILT_MAX, TILT_MAX)
	_tilt = lerpf(_tilt, tilt_target, 1.0 - exp(-dt * 14.0))


func _update_cards(dt: float) -> void:
	var n := _order.size()
	var size := layout_rect.size
	var xfs := HandLayout.layout(n, _scroll, _focus if _drag_id == -1 else -1.0, _mode, size.x, size.y, _gaps)
	var any_playable := false
	var marks := marks_playable()
	for id in _order:
		if _playable.has(id):
			any_playable = true
			break
	var is_day := _is_day()
	var lens_top := -1
	if _mode == HandLayout.Mode.LENS and _focus >= 0.0 and n > 0:
		lens_top = clampi(roundi(_focus), 0, n - 1)
	for i in n:
		var s: Slot = _slots[_order[i]]
		var xf := xfs[i]
		var rot := xf.get_rotation()
		var scl := xf.get_scale().x
		var lift := 0.0
		if marks and _playable.has(s.id) and not _peek:
			lift += LIFT_PLAYABLE
		if s.id == _selected:
			lift += LIFT_SELECTED
		if _picked.has(s.id):
			lift += LIFT_SELECTED
		var tpos := xf.origin + layout_rect.position + Vector2(0.0, -lift).rotated(rot)
		var t := Transform2D(rot, Vector2(scl, scl), 0.0, tpos)
		var key := i * 2
		var omega := OMEGA
		var zeta := ZETA
		var elev := 0.0
		if s.id == _big_id:
			t = Transform2D(0.0, Vector2(BIG_SCALE, BIG_SCALE), 0.0, _big_pos)
			key = TOP_KEY + 3
			elev = 1.2
		elif s.id == _drag_id:
			var p := _finger + _drag_grab
			if _drag_kind == "reorder":
				p.y = minf(p.y, xf.origin.y + layout_rect.position.y - LIFT_REORDER)
			t = Transform2D(0.0, Vector2(1.06, 1.06), 0.0, p)
			key = TOP_KEY + 3
			omega = DRAG_OMEGA
			zeta = 1.0
			elev = 1.0
		else:
			if s.delay > 0.0:
				s.delay -= dt
				if s.has_target:
					t = s.target
			elif s.arc_pending:
				s.arc_pending = false
				s.arc_total = 0.0 if reduced else absf(t.origin.x - s.pos.x)
			if s.arc_total > 0.0 and s.delay <= 0.0:
				var remaining := absf(t.origin.x - s.pos.x)
				if remaining < 2.0:
					s.arc_total = 0.0
				else:
					var prog := 1.0 - clampf(remaining / s.arc_total, 0.0, 1.0)
					t.origin.y -= ARC_LIFT * sin(PI * prog) + ARC_LIFT * 0.25
					key += n * 2 + 4
			if i == lens_top:
				key = n * 2 + 2
			if s.id == _selected:
				elev = 0.6
			elif marks and _playable.has(s.id):
				elev = 0.25
		s.target = t
		s.has_target = true
		s.key = key
		_spring_slot(s, t, omega, zeta, dt)
		var shade := HandLayout.shade(n, _scroll, _mode, i)
		if marks and dim_unplayable and any_playable and not _playable.has(s.id) and not _peek and s.id != _big_id:
			shade *= 0.92 if is_day else 0.84
		elif is_picking() and not _pick_cands.has(s.id):
			shade *= 0.8 if is_day else 0.7
		s.view.day = is_day
		s.view.playable_tint = accent
		_apply_view(s, shade, elev)
		s.view.skew = _tilt if s.id != _drag_id and s.id != _big_id else 0.0


func _spring_slot(s: Slot, t: Transform2D, omega: float, zeta: float, dt: float) -> void:
	var rx := HandLayout.spring(s.pos.x, s.vel.x, t.origin.x, omega, zeta, dt)
	var ry := HandLayout.spring(s.pos.y, s.vel.y, t.origin.y, omega, zeta, dt)
	s.pos = Vector2(rx.x, ry.x)
	s.vel = Vector2(rx.y, ry.y)
	var rr := HandLayout.spring(s.rot, s.rot_v, t.get_rotation(), omega, zeta, dt)
	s.rot = rr.x
	s.rot_v = rr.y
	var rs := HandLayout.spring(s.scl, s.scl_v, t.get_scale().x, omega, maxf(zeta, 0.9), dt)
	s.scl = rs.x
	s.scl_v = rs.y


func _apply_view(s: Slot, shade: float, elev: float) -> void:
	var v := s.view
	v.position = s.pos
	v.rotation = s.rot
	v.scale = Vector2(s.scl, s.scl)
	v.z_index = TOP_Z if s.key >= TOP_KEY else 0
	v.brightness = shade
	v.elevation = elev
	var st := CardView.State.NORMAL
	if s.id == _selected or _picked.has(s.id) or (s.id == _drag_id and _drag_kind == "play" and _gesture.play_armed):
		st = CardView.State.SELECTED
	elif _playable.has(s.id) and not _peek and marks_playable():
		st = CardView.State.PLAYABLE
	if v.state != st:
		v.state = st
	v.modulate.a = s.fade


func _update_leaving(dt: float) -> void:
	for s in _leaving.duplicate():
		s.fade -= dt / 0.2
		if s.played and play_target != Vector2.INF:
			var t := Transform2D(0.0, Vector2(play_target_scale, play_target_scale), 0.0, to_local(play_target))
			_spring_slot(s, t, OMEGA, 1.0, dt)
		else:
			s.pos.y += 260.0 * dt
		if s.played:
			s.key = TOP_KEY + 2
		_apply_view(s, s.view.brightness, 0.0)
		if s.fade <= 0.0:
			_leaving.erase(s)
			_free_view(s.view)
	# ausgespielte Karten (noch nicht bestätigt): fliegen zur Ablage bzw. warten über der Hand
	for s in _slots.values():
		var sl := s as Slot
		if not sl.played:
			continue
		var t := sl.target
		if play_target != Vector2.INF:
			t = Transform2D(0.0, Vector2(play_target_scale, play_target_scale), 0.0, to_local(play_target))
		else:
			t = Transform2D(0.0, Vector2(1.04, 1.04), 0.0, Vector2(sl.target.origin.x, layout_rect.position.y - sl.view.card_size().y * 0.35))
		sl.target = t
		sl.key = TOP_KEY + 2
		_spring_slot(sl, t, OMEGA, 1.0, dt)
		_apply_view(sl, 1.0, 1.0)


# Geisterbild auf der Ablage, solange das Hochziehen scharf ist (Vorschau, wo die Karte landet).
func _update_ghost(dt: float) -> void:
	var want := _armed_id != -1 and play_target != Vector2.INF and _slots.has(_armed_id)
	if want and _ghost == null:
		_ghost = CardView.new()
		_ghost.width = HandLayout.card_width(layout_rect.size.y)
		_ghost.visible = false
		add_child(_ghost)
	if _ghost == null:
		return
	if want:
		var s: Slot = _slots[_armed_id]
		if _ghost.current_key() != s.view.current_key():
			_ghost.setup(-1, s.view.current_key())
		if _ghost.width != s.view.width:
			_ghost.width = s.view.width
		_ghost.position = to_local(play_target)
		_ghost.scale = Vector2(play_target_scale, play_target_scale)
		_ghost.day = _is_day()
	_ghost_a = move_toward(_ghost_a, 1.0 if want else 0.0, dt / 0.12)
	_ghost.visible = _ghost_a > 0.01
	_ghost.modulate.a = GHOST_ALPHA * _ghost_a
	_ghost.z_index = TOP_Z


func _update_overlay(dt: float) -> void:
	var o := _overlay
	o.view_rect = _view_rect()
	var dim_target := 1.0 if _big_id != -1 else 0.0
	o.dim = move_toward(o.dim, dim_target, dt / 0.15)
	var holding := _big_id != -1 and not _big_sticky
	o.badge = move_toward(o.badge, 1.0 if _big_id != -1 else 0.0, dt / 0.12)
	o.badge_pos = _button_pos if _big_sticky else _badge_pos
	o.badge_hot = move_toward(o.badge_hot, 1.0 if (_help_hot or _big_sticky) else 0.0, dt / 0.08)
	o.badge_button = _big_sticky
	o.hints = 1.0 if holding else 0.0
	o.z_index = TOP_Z
	o.visible = o.dim > 0.001 or o.badge > 0.001
	var s: Slot = _slots.get(_big_id)
	if s != null:
		o.card_rect = Rect2(_big_pos - s.view.card_size() * BIG_SCALE * 0.5, s.view.card_size() * BIG_SCALE)
	if o.visible:
		o.queue_redraw()


# Zeichenreihenfolge über die Kindreihenfolge: ruhende Karten nach Schlüssel (rechts über links, Lupe/Bogen obenauf), dann die
# oberste Schicht (Abdunklung, Geisterbild, ausgespielte, gezogene bzw. große Karte). Umgeordnet wird nur bei Änderungen.
func _arrange() -> void:
	var entries: Array = []
	for s in _slots.values():
		entries.append([(s as Slot).key, (s as Slot).view])
	for s in _leaving:
		entries.append([s.key, s.view])
	entries.append([TOP_KEY, _overlay])
	if _ghost != null:
		entries.append([TOP_KEY + 1, _ghost])
	var count := get_child_count()
	var by_index := PackedInt64Array()
	by_index.resize(count)
	by_index.fill(-1)
	var ok := true
	for e in entries:
		var node: Node = e[1]
		if node.get_parent() != self:
			ok = false
			break
		by_index[node.get_index()] = int(e[0])
	if ok:
		var last := -1
		for k in by_index:
			if k == -1:
				continue
			if k < last:
				ok = false
				break
			last = k
	if ok:
		return
	entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var i := 0
	for e in entries:
		var node: Node = e[1]
		if node.get_parent() != self:
			continue
		if node.get_index() != i:
			move_child(node, i)
		i += 1


# ---------------------------------------------------------------- Hilfsfunktionen

func _make_slot(id: int, face: String, back: String) -> Slot:
	var s := Slot.new()
	s.id = id
	s.face = face
	s.back = back
	s.view = CardView.new()
	s.view.width = HandLayout.card_width(layout_rect.size.y)
	s.view.setup(id, face, back, not (_peek and back != ""))
	s.view.day = _is_day()
	s.key = -1
	add_child(s.view)
	_slots[id] = s
	return s


func _spawn(s: Slot, delay: float, shimmer: bool) -> void:
	if spawn_from != Vector2.INF:
		s.pos = to_local(spawn_from)
		s.scl = 0.66
	else:
		s.pos = Vector2(layout_rect.get_center().x, layout_rect.position.y - 220.0)
		s.scl = 0.8
	s.rot = 0.0
	s.vel = Vector2.ZERO
	s.view.position = s.pos
	s.view.scale = Vector2(s.scl, s.scl)
	# bis zum Start am Ausgangspunkt warten
	s.target = Transform2D(0.0, Vector2(s.scl, s.scl), 0.0, s.pos)
	s.has_target = true
	s.delay = delay
	if shimmer and not reduced:
		s.view.shimmer(SHIMMER_S)


func _remove_slot(id: int) -> void:
	var s: Slot = _slots[id]
	_slots.erase(id)
	_order.erase(id)
	if _drag_id == id:
		_cancel_gesture()
	if _big_id == id:
		_close_big()
	if _armed_id == id:
		_set_armed(-1)
	s.fade = minf(s.fade, 1.0)
	_leaving.append(s)


func _free_view(v: CardView) -> void:
	if v == null or not is_instance_valid(v):
		return
	if v.get_parent() == self:
		remove_child(v)
	v.queue_free()


# Flip: die Karte wechselt die Seite (hell ↔ dunkel), und – soweit bekannt – die neue Rückseite ist das alte Gesicht.
# Sonst liegt unter derselben Kennung eine andere Karte (neue Runde).
func _is_flip(s: Slot, face: String, back: String) -> bool:
	if _side_of(face) == _side_of(s.face):
		return false
	return back == "" or s.back == "" or back == s.face


static func _side_of(face: String) -> String:
	return "dunkel" if face.begins_with("dunkel") else "hell"


func _is_day() -> bool:
	if night >= 0.0:
		return night < 0.5
	return _auto_day


func _save_seat_state() -> void:
	if _seat >= 0 and not _order.is_empty():
		_seat_state[_seat] = {"sort": sort_mode, "order": _order.duplicate()}


func _turn(s: Slot, show_front: bool, delay: float, dur := FLIP_CARD_S) -> void:
	if s.view.showing_front == show_front and not s.view.is_flipping():
		return
	s.view.flip_to(show_front, dur, delay)


# Wende-Welle von links nach rechts; Ergebnis: Wartezeit bis zur Neusortierung (Welle + 100 ms Pause).
func _wave(turned: Array[Slot], delay: float, step_s: float, dur: float) -> float:
	if turned.is_empty():
		return 0.0
	var by_x := turned.duplicate()
	by_x.sort_custom(func(a: Slot, b: Slot) -> bool: return a.pos.x < b.pos.x)
	for k in by_x.size():
		_turn(by_x[k], not _peek, delay + k * step_s, dur)
	return delay + (by_x.size() - 1) * step_s + dur + FLIP_PAUSE_S


func _live_cards() -> Array:
	return _cards_of(_order)


func _cards_of(ids: Array[int]) -> Array:
	var out: Array = []
	for id in ids:
		var s: Slot = _slots[id]
		out.append({"id": id, "face": s.face, "back": s.back})
	return out


# Weg nach oben bis zum Ausspielen: ≈ 25 % der Bildhöhe, begrenzt auf 70–110 dp (180 px bei 720 px Höhe).
func _play_dist() -> float:
	return clampf(_view_rect().size.y * 0.25, 70.0 * DP, 110.0 * DP)


func _ordered(cards: Array) -> Array[int]:
	if sort_mode == "manuell":
		return CardSort.merge_manual(_order if not _order.is_empty() else _manual_seed, cards)
	return CardSort.sort_ids(cards, sort_mode)


# Neue Reihenfolge übernehmen: Karten mit neuem Platz bekommen Versatz (15 ms je Karte), weite Wege einen Bogen.
func _apply_order(new_order: Array[int], base_delay: float, all_delay: bool) -> void:
	var center_id := -1
	if _mode == HandLayout.Mode.CAROUSEL and not _order.is_empty():
		center_id = _order[clampi(roundi(_scroll_target), 0, _order.size() - 1)]
	var m := 0
	for k in new_order.size():
		var s: Slot = _slots[new_order[k]]
		var old := _order.find(new_order[k])
		if old == -1:
			continue
		if old != k or all_delay:
			s.delay = base_delay + m * STAGGER_S
			m += 1
			if absi(old - k) >= 3:
				s.arc_pending = true
	_order = new_order
	_gaps = CardSort.group_starts(_faces(_order), sort_mode)
	if not _order.is_empty():
		_auto_day = _side_of((_slots[_order[0]] as Slot).face) == "hell"
	var old_mode := _mode
	_refresh_mode()
	if _mode == HandLayout.Mode.CAROUSEL:
		var idx := _order.find(center_id) if center_id != -1 else -1
		if old_mode != HandLayout.Mode.CAROUSEL:
			idx = _order.find(_selected) if _selected != -1 else (_order.size() - 1) / 2
			_scroll = float(idx)
			_scroll_target = float(idx)
		elif idx != -1:
			var shift := float(idx) - roundf(_scroll_target)
			_scroll += shift
			_scroll_target += shift
		_scroll_target = clampf(_scroll_target, 0.0, float(_order.size() - 1))
		_tilt_prev = _scroll
		# programmatische Verschiebung: Haptik-Raster mitführen (kein Puls)
		_last_tick_index = roundi(clampf(_scroll, 0.0, float(_order.size() - 1)))


func _refresh_mode() -> void:
	_mode = HandLayout.choose_mode(_order.size(), _mode)
	if _mode == HandLayout.Mode.CAROUSEL:
		_scroll_target = clampf(_scroll_target, 0.0, float(maxi(_order.size() - 1, 0)))


func _faces(ids: Array[int]) -> Array:
	var out: Array = []
	for id in ids:
		out.append((_slots[id] as Slot).face)
	return out


func _focus_at(x_local: float) -> float:
	var n := _order.size()
	if n == 0:
		return -1.0
	var f := HandLayout.index_at(n, x_local - layout_rect.position.x, _scroll, _mode, layout_rect.size.x, layout_rect.size.y, _gaps)
	return clampf(f, 0.0, float(n - 1))


# Oberste Karte unter p (lokal), nach Zeichenreihenfolge; −1 = keine.
func _card_at(p: Vector2) -> int:
	var best := -1
	var best_key := -100000
	var g := to_global(p)
	for id in _order:
		var s: Slot = _slots[id]
		if s.key > best_key and s.view.contains_global_point(g):
			best = id
			best_key = s.key
	return best


# Ohne ausdrücklichen Handbereich: am unteren Rand des sichtbaren Bereichs (folgt Größenänderungen, z. B. 19:9).
func _fit_to_view() -> void:
	if _rect_explicit or not is_inside_tree():
		return
	var r := default_rect(_view_rect())
	if r != layout_rect:
		_rect_auto = true
		layout_rect = r
		_rect_auto = false


func _event_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


# Sichtbarer Bereich in lokalen Koordinaten.
func _view_rect() -> Rect2:
	if not is_inside_tree():
		return Rect2(0, 0, 1600, 720)
	return get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()


func _now() -> float:
	return clock_ms if clock_ms >= 0.0 else float(Time.get_ticks_msec())


func _time(t_ms: float) -> float:
	return t_ms if t_ms >= 0.0 else _now()


func _vibrate(ms: int, strength: float) -> void:
	if not haptics or not is_inside_tree():
		return
	var app := get_node_or_null("/root/App")
	if app != null and app.has_method("vibrate"):
		app.call("vibrate", ms, strength)


# Pixel je dp: Bildschirmdichte (dpi/160) geteilt durch den Maßstab Fenster/Basisauflösung, auf sinnvolle Werte begrenzt.
func _compute_dp() -> float:
	if not is_inside_tree():
		return DP
	var dpi := float(DisplayServer.screen_get_dpi())
	var win := get_viewport().get_visible_rect().size
	var scr := DisplayServer.window_get_size()
	if dpi <= 0.0 or win.y <= 0.0 or scr.y <= 0:
		return DP
	var px_per_dp := dpi / 160.0
	var stretch := float(scr.y) / win.y
	return clampf(px_per_dp / stretch, 1.5, 2.6)


# Abdunkelung, „?“-Ziel bzw. -Knopf und Richtungshinweise der Großansicht.
class Overlay:
	extends Node2D
	var view_rect := Rect2()
	var card_rect := Rect2()
	var dim := 0.0
	var badge := 0.0
	var badge_pos := Vector2.ZERO
	var badge_hot := 0.0
	var badge_button := false
	var hints := 0.0
	var _font: Font

	func _font_q() -> Font:
		if _font != null:
			return _font
		var base: Font = null
		for path in ["res://assets/fonts/Fraunces.ttf", "res://assets/fonts/BricolageGrotesque.ttf"]:
			if ResourceLoader.exists(path):
				base = load(path) as Font
				break
		if base == null:
			_font = ThemeDB.fallback_font
			return _font
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {"wght": 800, "opsz": 12}
		_font = fv
		return _font

	func _draw() -> void:
		if dim > 0.001:
			draw_rect(view_rect, Color(0.02, 0.025, 0.07, 0.6 * dim))
		if hints > 0.0 and dim > 0.5 and card_rect.size.x > 0.0:
			var c := Color(0.96, 0.92, 0.85, 0.55 * dim)
			var cx := card_rect.get_center().x
			var top := card_rect.position.y - 14.0 * DP
			var a := 7.0 * DP
			draw_polyline(PackedVector2Array([Vector2(cx - a, top + a * 0.6), Vector2(cx, top), Vector2(cx + a, top + a * 0.6)]), c, 2.5 * DP, true)
			var my := card_rect.get_center().y
			var l := card_rect.position.x - 12.0 * DP
			var r := card_rect.end.x + 12.0 * DP
			draw_polyline(PackedVector2Array([Vector2(l + a * 0.6, my - a), Vector2(l, my), Vector2(l + a * 0.6, my + a)]), c, 2.5 * DP, true)
			draw_polyline(PackedVector2Array([Vector2(r - a * 0.6, my - a), Vector2(r, my), Vector2(r - a * 0.6, my + a)]), c, 2.5 * DP, true)
		if badge > 0.001:
			var k := badge * (1.0 + 0.22 * badge_hot)
			var rad := BADGE_R * k
			var gold := Color(1.0, 0.80, 0.30)
			var paper := Color(0.996, 0.969, 0.91)
			var ink := Color(0.13, 0.106, 0.173)
			# Glühen
			for i in 4:
				var rr := rad + (4.0 + i * 4.0) * DP * (0.4 + 0.6 * badge_hot)
				draw_circle(badge_pos, rr, Color(gold.r, gold.g, gold.b, 0.07 * badge * (0.4 + 0.6 * badge_hot)))
			var fill := paper.lerp(gold, badge_hot)
			draw_circle(badge_pos, rad, Color(fill.r, fill.g, fill.b, badge))
			draw_arc(badge_pos, rad, 0.0, TAU, 48, Color(ink.r, ink.g, ink.b, badge), 2.0 * DP, true)
			var f := _font_q()
			var fs := int(22.0 * DP * k)
			if fs < 4:
				return
			var sz := f.get_string_size("?", HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			var asc := f.get_ascent(fs)
			var desc := f.get_descent(fs)
			draw_string(f, badge_pos + Vector2(-sz.x * 0.5, (asc - desc) * 0.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink.r, ink.g, ink.b, badge))
