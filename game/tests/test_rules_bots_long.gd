extends "res://tests/test_rules_bots.gd"
# Modul A: lange Fassung des Bot-Dauerlaufs, 10 000 Partien und Stärketest mit 3 000 Partien (dauert einige Minuten;
# Standardlauf: test_rules_bots.gd).


func game_count() -> int:
	return 10000


func strength_count() -> int:
	return 3000
