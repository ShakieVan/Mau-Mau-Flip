class_name RoundEndView
extends Control
# Rundenende und Sieg: Papierkarte (nachts dunkel, night > 0.5) mit „Mau-Mau!“, Gewinner, Platzierungen und Punkten (Runde und gesamt). Der Knopf
# „Nächste Runde“ erscheint nur, wo er erlaubt ist (Platz 0 bzw. Gastgeber; der Tisch entscheidet über can_next).
# ranking: Plätze in Reihenfolge (int oder {seat, points}); scores: Gesamtpunkte je Platz (Array oder Dictionary).

signal next_round

const ROW_H := 50.0

var rows: Array[Dictionary] = []     # {place, seat, name, points, total, me}
var title := "Mau-Mau!"
var subtitle := ""
var scoring := false
var night := 0.0
var note := ""                      # kleiner Satz aus der Statistik („Dein 12. Rundensieg!“, AppStats.round_note), "" = keiner

var _panel_rect := Rect2()
var _button: PillButton
var _wait_label := ""
var _appear := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_button = PillButton.new()
	_button.text = "Nächste Runde"
	_button.icon_name = "pfeil"
	_button.style = "primary"
	_button.night = 0.0
	_button.font_size = UiFonts.px(22)
	_button.pressed.connect(func() -> void: next_round.emit())
	add_child(_button)


static func build_rows(players: Array, ranking: Array, scores: Variant, my_seat: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var place := 0
	for entry in ranking:
		var seat := int(entry["seat"]) if entry is Dictionary else int(entry)
		var pts := int(entry.get("points", 0)) if entry is Dictionary else 0
		place += 1
		seen[seat] = true
		out.append(_row(players, seat, place, pts, scores, my_seat))
	# Rest (nicht platziert) nach Kartenzahl
	var rest: Array = []
	for p in players:
		if not seen.has(int(p.get("seat", -1))):
			rest.append(p)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("count", 0)) < int(b.get("count", 0)))
	for p in rest:
		place += 1
		out.append(_row(players, int(p.get("seat", -1)), place, 0, scores, my_seat))
	return out


static func _row(players: Array, seat: int, place: int, pts: int, scores: Variant, my_seat: int) -> Dictionary:
	var name := I18n.t("Platz %d") % (seat + 1)
	var count := 0
	for p in players:
		if int(p.get("seat", -1)) == seat:
			name = str(p.get("name", name))
			count = int(p.get("count", 0))
	var total := 0
	if scores is Array and seat >= 0 and seat < (scores as Array).size():
		total = int(scores[seat])
	elif scores is Dictionary:
		total = int((scores as Dictionary).get(seat, (scores as Dictionary).get(str(seat), 0)))
	return {"place": place, "seat": seat, "name": name, "points": pts, "total": total, "count": count, "me": seat == my_seat}


func show_result(players: Array, ranking: Array, scores: Variant, my_seat: int, round_no := 1, can_next := true, with_scores := false, game_over := false, wait_for := "") -> void:
	var was_visible := visible
	rows = build_rows(players, ranking, scores, my_seat)
	scoring = with_scores
	var winner: Dictionary = rows[0] if not rows.is_empty() else {}
	var wname := str(winner.get("name", ""))
	title = "Mau-Mau!"
	if game_over:
		subtitle = I18n.t("Du gewinnst die Partie!") if bool(winner.get("me", false)) else I18n.t("%s gewinnt die Partie") % wname
	else:
		subtitle = I18n.t("Du gewinnst Runde %d!") % round_no if bool(winner.get("me", false)) else I18n.t("%s gewinnt Runde %d") % [wname, round_no]
	_button.visible = can_next
	_button.text = "Neue Partie" if game_over else "Nächste Runde"
	_wait_label = "" if can_next else (I18n.t("Warte auf %s …") % wait_for if wait_for != "" else "")
	visible = true
	if not was_visible:
		_appear = 0.0
		var tw := create_tween()
		tw.tween_property(self, "_appear", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_layout()
	queue_redraw()


# Tag/Nacht des Tisches (TableView.set_night, 1.1.3): Karte nachts dunkel, Knopf dann cremefarben
func set_night(v: float) -> void:
	night = v
	_button.night = 1.0 if v > 0.5 else 0.0
	queue_redraw()


func hide_view() -> void:
	visible = false


func winner_anchor() -> Vector2:
	return Vector2(_panel_rect.get_center().x, _panel_rect.position.y + 70.0)


func _process(_delta: float) -> void:
	if visible and _appear < 1.0:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


# Einstellung „Schriftgröße“ live geändert (UiFonts.rescale_tree)
func on_font_scale() -> void:
	_layout()


# Zusatzhöhe des Kopfs, wenn die Einstellung „Schriftgröße“ Titel und Unterzeile vergrößert
func _head_extra() -> float:
	return (UiFonts.px(64) - 64) * 0.75 + (UiFonts.px(22) - 22) + _note_extra()


# Platz für den Statistik-Satz unter der Unterzeile
func _note_extra() -> float:
	return UiFonts.px(18) + 12.0 if note != "" else 0.0


func _layout() -> void:
	var w := minf(640.0 + (UiFonts.scale - 1.0) * 300.0, size.x - 30.0)
	var h := 170.0 + _head_extra() + rows.size() * ROW_H + 110.0
	h = minf(h, size.y - 30.0)
	_panel_rect = Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)
	_button.font_size = UiFonts.px(22)
	_button.size = Vector2(_button.preferred_width(), PillButton.TOUCH_MIN)
	_button.position = Vector2(_panel_rect.get_center().x - _button.size.x * 0.5, _panel_rect.end.y - 96.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.10, 0.45 * clampf(_appear, 0.0, 1.0)))
	var s := clampf(_appear, 0.0, 1.2)
	var r := _panel_rect
	draw_set_transform(r.get_center() * (1.0 - s), 0.0, Vector2(s, s))
	# Nachts (Tisch auf der dunklen Seite, 1.1.3) dunkle Karte mit heller Schrift, sonst Papier
	var dark := night > 0.5
	var ink := UiPalette.PAPER if dark else UiPalette.INK
	var muted := UiPalette.MUTED_NIGHT if dark else UiPalette.MUTED_DAY
	var sb := UiTheme.box(UiPalette.NIGHT_PANEL, Color(UiPalette.PAPER, 0.25), 2, 34) if dark else UiTheme.box(UiPalette.PAPER, Color(UiPalette.INK, 0.12), 2, 34)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 26
	sb.shadow_offset = Vector2(0, 12)
	draw_style_box(sb, r)
	# Schriftgrößen folgen der Einstellung „Schriftgröße“ (UiFonts.px)
	var fs_title := UiFonts.px(64)
	var fs_sub := UiFonts.px(22)
	var fs_head := UiFonts.px(13)
	var fs_badge := UiFonts.px(17)
	var fs_name := UiFonts.px(22)
	var fs_num := UiFonts.px(20)
	var fs_detail := UiFonts.px(18)
	var y_title := r.position.y + 84.0 + (fs_title - 64) * 0.75
	var tf := UiFonts.mau()
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title).x
	draw_string(tf, Vector2(r.get_center().x - tw * 0.5, y_title), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title, ink)
	var f := UiFonts.text(700, 100.0)
	var sw := f.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sub).x
	draw_string(f, Vector2(r.get_center().x - sw * 0.5, y_title + 38.0 + (fs_sub - 22)), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sub, muted)
	if note != "":
		var fs_note := UiFonts.px(18)
		var nfont := UiFonts.text(800, 90.0)
		var nw := nfont.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_note).x
		var accent := UiPalette.TURN if dark else Color("#B8530A")
		draw_string(nfont, Vector2(r.get_center().x - nw * 0.5, y_title + 38.0 + (fs_sub - 22) + fs_note + 10.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_note, accent)
	var y := r.position.y + 150.0 + _head_extra()
	var nf := UiFonts.text(800, 90.0)
	if scoring:
		var hf := UiFonts.text(700, 85.0)
		draw_string(hf, Vector2(r.end.x - 214.0, y + 4.0), I18n.t("RUNDE"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_head, muted)
		draw_string(hf, Vector2(r.end.x - 108.0, y + 4.0), I18n.t("GESAMT"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_head, muted)
		y += 10.0
	for row in rows:
		var ry := y + ROW_H * 0.5
		if bool(row["me"]):
			var hl := UiTheme.box(Color(UiPalette.FILL["gelb"], 0.22 if dark else 0.35), Color(0, 0, 0, 0), 0, 18)
			draw_style_box(hl, Rect2(r.position.x + 26.0, y + 3.0, r.size.x - 52.0, ROW_H - 6.0))
		var place := int(row["place"])
		var medal := UiPalette.TURN if place == 1 else (Color("#C9CED8") if place == 2 else (Color("#D99A6C") if place == 3 else Color(ink, 0.15)))
		var mc := Vector2(r.position.x + 58.0, ry)
		draw_circle(mc, 17.0, medal)
		var pt := str(place)
		var pw := nf.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_badge).x
		draw_string(nf, mc + Vector2(-pw * 0.5, fs_badge * 0.35), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_badge, UiPalette.INK if place <= 3 else ink)
		var av := Vector2(r.position.x + 104.0, ry)
		draw_circle(av, 18.0, UiPalette.avatar(int(row["seat"])))
		var ini := str(row["name"]).substr(0, 1).to_upper()
		var iw := nf.get_string_size(ini, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_badge).x
		draw_string(nf, av + Vector2(-iw * 0.5, fs_badge * 0.35), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_badge, UiPalette.INK)
		var label := str(row["name"]) + ("  " + I18n.t("(du)") if bool(row["me"]) and not str(row["name"]).to_lower() in ["du", "you"] else "")
		draw_string(f, Vector2(r.position.x + 136.0, ry + fs_name * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_name, ink)
		var detail := I18n.t("fertig") if int(row["count"]) == 0 else (I18n.t("%d Karte") if int(row["count"]) == 1 else I18n.t("%d Karten")) % int(row["count"])
		if scoring:
			var pts := "+%d" % int(row["points"]) if int(row["points"]) > 0 else "–"
			draw_string(nf, Vector2(r.end.x - 214.0, ry + fs_num * 0.38), pts, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_num, ink)
			draw_string(nf, Vector2(r.end.x - 108.0, ry + fs_num * 0.38), str(int(row["total"])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_num, ink)
		else:
			var dw := f.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_detail).x
			draw_string(f, Vector2(r.end.x - 44.0 - dw, ry + fs_detail * 0.38), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_detail, muted)
		y += ROW_H
	if _wait_label != "":
		var fs_wait := UiFonts.px(20)
		var ww := f.get_string_size(_wait_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_wait).x
		draw_string(f, Vector2(r.get_center().x - ww * 0.5, r.end.y - 46.0), _wait_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_wait, muted)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
