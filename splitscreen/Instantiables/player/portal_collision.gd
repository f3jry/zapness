extends Sprite2D
@export var area : Area2D
var all_portal_layers = [2,4,8,16]
# player collision layers
@export var collision_layer_value = 2 
@export var collision_mask_value = 2
# use_calc https://devwhiledead.itch.io/godot-collision-calculator
var def_collision_layer_value = 65 
var def_collision_mask_value = 65
func multiply_layer():
	var index = all_portal_layers.find(collision_layer_value)
	
	var by_index = 0
	if $"../../../..".player_index == 2: by_index = 2
	var edited_index = index + by_index
	print(str(edited_index) + " portal index")
	collision_layer_value = all_portal_layers[edited_index]
	collision_mask_value = all_portal_layers[edited_index]
func add_layers(node):
	node.collision_layer = collision_layer_value
	node.collision_mask = collision_mask_value
	
func _ready() -> void:
	multiply_layer()
	add_layers($forhuman)
	add_layers(get_parent())
func player_enter(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.set_collision_layer(collision_layer_value)
		body.set_collision_mask(collision_mask_value)
func player_exit(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.set_collision_layer(def_collision_layer_value)
		body.set_collision_mask(def_collision_mask_value)
func _physics_process(delta: float) -> void: 
	$portal_pass.global_rotation = 0
	for i in area.get_overlapping_bodies():
		if i.is_in_group("player"):
			i.set_collision_layer(collision_layer_value)
			i.set_collision_mask(collision_mask_value)
