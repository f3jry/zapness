extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.announcer = self
	visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
func announcement(announce_text):
	$Panel/Label.text = announce_text
	visible = true
	await get_tree().create_timer(2.0).timeout
	visible = false
