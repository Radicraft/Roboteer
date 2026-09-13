extends Node3D
## QA preview: the workshop stage with the fixture bot and a workshop-mode camera.
## Run: Godot --path Arena res://qa/stage_preview.tscn -- --roboteer-shots=DIR,3,4 [--roboteer-cam=menu]

func _ready() -> void:
	var stage := WorkshopStage.new()
	stage.name = "Stage"
	add_child(stage)
	var cfg_text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var config: Dictionary = JSON.parse_string(cfg_text)
	var bot_cfg: Dictionary = (config["bots"] as Array)[0]
	stage.show_bot(bot_cfg)
	stage.set_auto_rotate(true)
	var rig_scene: PackedScene = load("res://ui/camera_rig.tscn")
	var rig: Node3D = rig_scene.instantiate()
	rig.name = "CameraRig"
	add_child(rig)
	var mode := "workshop"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-cam="):
			mode = a.substr(15)
	rig.call("set_mode", mode)
	print("stage_preview ready, camera mode ", mode)
