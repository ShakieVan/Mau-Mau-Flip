extends "res://tests/test_rules_views.gd"
# Modul A: lange Fassung der Sicht- und Ereignisprüfung mit den vollen Partienzahlen (dauert rund 2 Minuten; Standardlauf:
# test_rules_views.gd). Gehört nicht in einen „alle Tests“-Lauf, sondern wird gezielt gestartet.


func counts() -> Dictionary:
	return {"RULES_JSON_GAMES": 30, "RULES_LEAK_GAMES": 60, "RULES_HINT_GAMES": 16, "RULES_TRIP_GAMES": 40}
