extends CharacterBody3D
class_name RTSUnit3D

@export var speed: float = 6.0
@export var rotation_speed: float = 8.0
@export var avoidance_radius: float = 2.5
@export var separation_radius: float = 2.0
@export var gravity: float = 20.0
@export var push_strength: float = 6.0
@export var max_avoidance_force: float = 1.5
@export var stuck_threshold: float = 0.5  # Velocidad mínima para considerar "trabado"
@export var stuck_time_limit: float = 1.0  # Tiempo antes de buscar alternativa

var is_selected: bool = false
var is_moving: bool = false
var target_position: Vector3 = Vector3.ZERO
var current_flow_direction: Vector3 = Vector3.ZERO
var unit_id: int
var last_position: Vector3 = Vector3.ZERO
var stuck_timer: float = 0.0

@onready var mesh: MeshInstance3D = $Body
@onready var selection_ring: MeshInstance3D = $SelectionIndicator

func _ready():
	unit_id = randi()
	last_position = global_position
	# Configurar propiedades de CharacterBody3D
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(45)

# ---------------------------
# 🔹 Selección visual
# ---------------------------
func set_selected(value: bool):
	is_selected = value
	if selection_ring:
		selection_ring.visible = value

# ---------------------------
# 🔹 Ordenar movimiento
# ---------------------------
func set_target(pos: Vector3):
	target_position = pos
	is_moving = true
	stuck_timer = 0.0

# ---------------------------
# 🔹 Movimiento principal CON empuje
# ---------------------------
func _physics_process(delta: float):
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	if not is_moving:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	
	var flow_field: FlowField3D = get_node_or_null("../FlowField3D")
	if not flow_field:
		move_and_slide()
		return
	
	# Obtener dirección del flow field
	current_flow_direction = flow_field.get_flow_direction(global_position)
	
	if current_flow_direction == Vector3.ZERO:
		is_moving = false
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	# Calcular todas las fuerzas
	var desired_direction = current_flow_direction
	var separation_force = get_separation_force()
	var avoidance_force = get_obstacle_avoidance()
	
	# Combinar fuerzas (separation tiene más peso)
	var final_direction = (desired_direction + separation_force * 1.5 + avoidance_force).normalized()
	
	# Detectar si está trabado
	var distance_moved = global_position.distance_to(last_position)
	if distance_moved < stuck_threshold * delta:
		stuck_timer += delta
		if stuck_timer > stuck_time_limit:
			# Forzar movimiento lateral para desatascarse
			final_direction += get_unstuck_direction()
			final_direction = final_direction.normalized()
			stuck_timer = 0.0
	else:
		stuck_timer = 0.0
	
	last_position = global_position
	
	# Rotar hacia la dirección
	if final_direction.length() > 0.01:
		var target_rot = atan2(final_direction.x, final_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * rotation_speed)
	
	# Aplicar velocidad
	velocity.x = final_direction.x * speed
	velocity.z = final_direction.z * speed
	
	# Mover Y aplicar empuje a otros
	move_and_slide()
	push_nearby_units()
	
	# Verificar llegada
	var distance_xz = Vector2(
		global_position.x - target_position.x,
		global_position.z - target_position.z
	).length()
	
	if distance_xz < 1.0:
		is_moving = false
		velocity = Vector3.ZERO

# ---------------------------
# 🔹 Separación de unidades cercanas
# ---------------------------
func get_separation_force() -> Vector3:
	var separation = Vector3.ZERO
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = separation_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 1 << 1  # Layer 2: Units
	query.exclude = [self]
	
	var results = space_state.intersect_shape(query, 10)
	
	for result in results:
		var collider = result.get("collider")
		if collider and collider != self and collider is CharacterBody3D:
			var away = global_position - collider.global_position
			away.y = 0
			
			var distance = away.length()
			if distance > 0.01 and distance < separation_radius:
				# Más fuerte cuando más cerca
				var strength = 1.0 - (distance / separation_radius)
				separation += away.normalized() * strength
	
	if separation.length() > max_avoidance_force:
		separation = separation.normalized() * max_avoidance_force
	
	return separation

# ---------------------------
# 🔹 Evitación de obstáculos estáticos
# ---------------------------
func get_obstacle_avoidance() -> Vector3:
	var avoidance = Vector3.ZERO
	var space_state = get_world_3d().direct_space_state
	
	# Raycast múltiple en forma de abanico
	var forward = -transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var angles = [-30, -15, 0, 15, 30]  # Grados
	var rays_hit = 0
	
	for angle_deg in angles:
		var angle = deg_to_rad(angle_deg)
		var direction = forward.rotated(Vector3.UP, angle)
		
		var from = global_position + Vector3.UP * 0.5
		var to = from + direction * avoidance_radius
		
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = (1 << 0) | (1 << 3)  # Terrain + Obstacles
		query.exclude = [self]
		
		var result = space_state.intersect_ray(query)
		
		if result:
			rays_hit += 1
			# Calcular dirección de evasión perpendicular
			var hit_normal = result.get("normal", Vector3.UP)
			hit_normal.y = 0
			if hit_normal.length() > 0.01:
				avoidance += hit_normal.normalized()
	
	# Si detectó obstáculos, normalizar la dirección de evasión
	if rays_hit > 0:
		avoidance = avoidance.normalized() * max_avoidance_force
	
	return avoidance

# ---------------------------
# 🔹 Empujar unidades cercanas físicamente
# ---------------------------
func push_nearby_units():
	"""Empuja activamente a las unidades que están bloqueando"""
	if not is_moving:
		return
	
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.5
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 1 << 1  # Layer 2: Units
	query.exclude = [self]
	
	var results = space_state.intersect_shape(query, 8)
	
	for result in results:
		var collider = result.get("collider")
		if collider and collider != self and collider is RTSUnit3D:
			var other: RTSUnit3D = collider
			
			var push_dir = (other.global_position - global_position)
			push_dir.y = 0
			
			var distance = push_dir.length()
			if distance > 0.01 and distance < 1.5:
				push_dir = push_dir.normalized()
				
				# Si la otra unidad no se está moviendo, empujarla más fuerte
				var force_multiplier = 1.0
				if not other.is_moving:
					force_multiplier = 2.0
				
				# Aplicar empuje directo a la posición
				var push_amount = push_strength * (1.0 - distance / 1.5) * force_multiplier
				other.global_position += push_dir * push_amount * get_physics_process_delta_time()

# ---------------------------
# 🔹 Dirección para desatascarse
# ---------------------------
func get_unstuck_direction() -> Vector3:
	"""Genera una dirección aleatoria para salir de un atasco"""
	var perpendicular = Vector3(-current_flow_direction.z, 0, current_flow_direction.x)
	var random_side = 1.0 if randf() > 0.5 else -1.0
	return perpendicular * random_side * 2.0

# ---------------------------
# 🔹 Método para detener
# ---------------------------
func stop():
	is_moving = false
	velocity = Vector3.ZERO
	stuck_timer = 0.0
