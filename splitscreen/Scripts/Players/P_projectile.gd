extends CharacterBody2D

@export var raycast : RayCast2D
@export var damage = 10
var speed = 10000
var charged = false
var dir = Vector2.ZERO
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	velocity = dir * speed * delta
	var col = move_and_collide(velocity)
	if col and col.get_collider() and col.get_collider().is_in_group("player"):
		col.get_collider().damage(damage)
		queue_free()
	elif col:
		queue_free()
