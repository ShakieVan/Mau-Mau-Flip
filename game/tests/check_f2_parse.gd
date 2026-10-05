extends SceneTree
# Hilfsskript F2: lädt alle Bildschirmskripte einzeln (Parse-Fehler mit Zeilennummer)
func _initialize() -> void:
	for f in DirAccess.get_files_at("res://scripts/ui/screens"):
		if f.ends_with(".gd"):
			var s := load("res://scripts/ui/screens/" + f)
			print(f, " -> ", s != null)
	print(load("res://scripts/ui/table_screen.gd") != null)
	print(load("res://tests/test_screens_flow.gd") != null)
	quit(0)
