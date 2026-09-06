class_name TestHarness
extends RefCounted
## Minimal assert harness so the repo carries no third-party test addon
## (addons stay empty unless an approved dependency exists — docs/03 §2).


var passed := 0
var failed := 0
var failures: Array[String] = []
var suite := ""


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append("%s :: %s" % [suite, label])
		printerr("FAIL  %s :: %s" % [suite, label])


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	check(str(actual) == str(expected), "%s (expected %s, got %s)" % [label, str(expected), str(actual)])


func check_near(actual: float, expected: float, epsilon: float, label: String) -> void:
	check(absf(actual - expected) <= epsilon, "%s (expected ~%s, got %s)" % [label, str(expected), str(actual)])


func check_between(value: float, lo: float, hi: float, label: String) -> void:
	check(value >= lo and value <= hi, "%s (expected in [%s, %s], got %s)" % [label, str(lo), str(hi), str(value)])


func report(runner_name: String) -> int:
	print("========================================")
	print("%s: %d passed, %d failed" % [runner_name, passed, failed])
	if failed > 0:
		print("Failures:")
		for failure: String in failures:
			print("  - " + failure)
	print("========================================")
	return 1 if failed > 0 else 0
