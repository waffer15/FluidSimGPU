extends RigidBody2D

@export var movement_speed: float = 6

var _dragging : bool = false
var _previous_mouse_velocity: Vector2 = Vector2.ZERO
var _previous_mouse_pos: Vector2

var _velocity: Vector2 = Vector2.ZERO
var _target_rotation: float
	
func _physics_process(delta: float) -> void:
	if _dragging:
		var current_position : Vector2 = self.global_position
		var mouse_position : Vector2 = get_global_mouse_position()
		
		var distance : float = current_position.distance_to(mouse_position)
		var direction : Vector2 = current_position.direction_to(mouse_position)
		
		var speed : float = movement_speed * distance / delta
		
		var velocity : Vector2 = direction * speed
		_velocity = velocity * delta
		
		#_target_rotation = 0 # Upright (0 radians)
		#rotation = lerp_angle(rotation, _target_rotation, 0.2)  # Smooth rotation

		## Add some spring-like bounce effect
		#if abs(rotation - _target_rotation) > 0.01:
			#var bounce_amount = sin((rotation - _target_rotation) * 10) * 0.1
			#rotation += bounce_amount * delta
		
		apply_leaning_effect(delta)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _velocity != Vector2.ZERO:
		state.linear_velocity = _velocity

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and  _dragging and not event.pressed:
		_dragging = false
		_velocity = Vector2.ZERO

func _on_draggable_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		_dragging = event.pressed
		if not _dragging:
			_velocity = Vector2.ZERO

# Function to apply leaning effect
func apply_leaning_effect(delta):
	const UPRIGHT_MUG_SPEED: float = 300
	var MAX_MUG_ROTATION: float = 25

	var velocity = _velocity.normalized()
	var speed = _velocity.length()
	_target_rotation = velocity.x * 45
	
	if speed <= UPRIGHT_MUG_SPEED:
		_target_rotation = 0
	
	else:
		_target_rotation = MAX_MUG_ROTATION * (_velocity.x / 1000)
	
	var rotate_speed: float = 10
	rotation_degrees += (_target_rotation - rotation_degrees) * delta * rotate_speed
	# rotation = lerp_angle(rotation, target_rotation, 0.2)
