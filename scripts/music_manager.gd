extends Node


@onready var game_music: AudioStreamPlayer = $GameMusic


func _ready() -> void:
	game_music.play()
