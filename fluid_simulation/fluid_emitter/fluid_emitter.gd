extends Node2D

@export var max_flow_rate: int = 5  # particles per second
@export var nozzle_open_value: float = 1
@export var color: Color
@export var initial_velocity: Vector2

var _nozzle_locations: Array[Node2D]
@export var _fluid: Fluid
var _last_particle_spawn: float


func _ready() -> void:
	_set_fluid_node()
	_collect_nozzle_locations()
	_last_particle_spawn = Time.get_ticks_msec()
#
func _physics_process(delta: float) -> void:
	if nozzle_open_value == 0:
		return
#
	# Calculate the actual flow rate based on nozzle_open_value and max_flow_rate
	var flow_rate = max_flow_rate * nozzle_open_value
	
	# Calculate time since the last particle was spawned
	var time_since_last_spawn = (Time.get_ticks_msec() - _last_particle_spawn) / 1000.0  # Convert to seconds

	# Calculate how many particles to spawn based on delta and flow rate
	var particles_to_spawn = flow_rate * time_since_last_spawn
	
	# Spawn the particles
	if particles_to_spawn >= 1:
		_spawn_fluid_particles(particles_to_spawn)
		_last_particle_spawn = Time.get_ticks_msec()  # Reset the last spawn times based on nozzle_open_value and max_flow_rate
#
func _spawn_fluid_particles(particles_to_spawn: float):
	# Iterate over each nozzle location
	var positions: Array[Vector2] = []
	var velocities: Array[Vector2] = []
	var colors: Array[Vector4] = []
	for nozzle: Node2D in _nozzle_locations:
		# Spawn the required number of particles
		for i in range(int(particles_to_spawn)):
			# Calculate particle position, velocity, and color
			positions.append(nozzle.to_global(Vector2(i, 0)))
			velocities.append(initial_velocity)
			colors.append(Vector4(color.r, color.g, color.b, color.a))
			
			# Add particle to the fluid system
	_fluid.add_particles_to_fluid(positions, velocities, colors)

func _set_fluid_node():
	var root: Window = get_tree().root
	var fluid = root.find_children("*", "Fluid")
	if fluid.size() == 0:
		printerr("There is no Fluid node in the scene")
		return

	_fluid = fluid[0]

func _collect_nozzle_locations() -> void:
	for node: Node in get_children():
		if node is Node2D:
			_nozzle_locations.append(node)
