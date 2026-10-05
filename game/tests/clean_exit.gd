extends RefCounted
# Sauberes Beenden der Testläufe (kein Test, wird von tools/build.ps1 nicht als Test gestartet).
#
# Hintergrund: Läuft beim quit() noch ein Ton (z. B. „sieg“ am Rundenende), hält der Audio-Server die Wiedergabe fest. Freigegeben
# wird sie erst im nächsten Bild auf dem Hauptthread, das es nach quit() nicht mehr gibt. Godot meldet dann „ERROR: N resources
# still in use at exit“ (OggPacketSequence/AudioStreamOggVorbis), und tools/build.ps1 wertet den Lauf zu Recht als Fehler.
#
# Verwendung am Ende eines Testskripts (extends SceneTree):
#   const CleanExit := preload("res://tests/clean_exit.gd")
#   await CleanExit.finish(self, 0 if fails == 0 else 1)

const SETTLE_S := 0.3      # echte Zeit für den Audio-Thread (Dummy-Treiber mischt in Blöcken von ~23 ms)


# Hält alle Töne an, gibt die Testknoten frei (Autoloads bleiben), wartet, bis Audio-Server und Knoten aufgeräumt sind, und leert
# die statischen Zwischenspeicher der Oberfläche. Danach quit(code).
static func finish(tree: SceneTree, code: int) -> void:
	await release(tree)
	tree.quit(code)


static func release(tree: SceneTree) -> void:
	Engine.time_scale = 1.0
	_stop_audio(tree.root)
	for child in tree.root.get_children():
		if not ProjectSettings.has_setting("autoload/" + str(child.name)):
			child.queue_free()
	# Zeitgeber unabhängig von Engine.time_scale und Pause
	await tree.create_timer(SETTLE_S, true, false, true).timeout
	await tree.process_frame
	await tree.process_frame
	clear_caches()
	await tree.process_frame


# Jeder AudioStreamPlayer im Baum (auch die Stimmen von App.sound und der Abspieler des Mau-Knopfs) hört auf.
static func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stop()
	for child in node.get_children():
		_stop_audio(child)


# Statische Zwischenspeicher mit Ressourcen (Texturen, Schriften, Thema) leeren.
static func clear_caches() -> void:
	CardTextures.clear_cache()
	UiIcons.clear_cache()
	ScreenKit.clear_cache()
	UiFonts._cache.clear()
	UiTheme._theme = null
