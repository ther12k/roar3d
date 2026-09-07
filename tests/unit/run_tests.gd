extends Node
## Unit test runner: `godot --headless --path . res://tests/unit/run_tests.tscn`


func _ready() -> void:
	var harness := TestHarness.new()
	var suites: Array = [
		preload("res://tests/unit/test_domain.gd").new(),
		preload("res://tests/unit/test_state_machine.gd").new(),
		preload("res://tests/unit/test_save_file.gd").new(),
	preload("res://tests/unit/test_app_services.gd").new(),
	]
	for suite in suites:
		suite.run(harness)
	var exit_code := harness.report("UNIT TESTS")
	get_tree().quit(exit_code)
