extends Node
## Autoload "Settings" — small persisted user-preference store.
## No options menu exists yet: toggle use_gif_art via user://settings.cfg,
## or live during a debug run through the Remote scene tree's Inspector
## (this node is exported, so it's editable there without a menu).

const CONFIG_PATH := "user://settings.cfg"

@export var use_gif_art: bool = true:
	set(value):
		if value == use_gif_art:
			return
		use_gif_art = value
		_save()


func _ready() -> void:
	_load()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		use_gif_art = config.get_value("art", "use_gif_art", use_gif_art)


func _save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # preserve any other sections/keys already on disk
	config.set_value("art", "use_gif_art", use_gif_art)
	config.save(CONFIG_PATH)
