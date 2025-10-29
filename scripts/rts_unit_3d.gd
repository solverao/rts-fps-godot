extends CharacterBody3D
class_name RTSUnit3D

## Configuración de movimiento
@export_group("Movement")
@export_range(1.0, 20.0, 0.5) var speed: float = 6.0
@export_range(1.0, 15.0, 0.5) var rotation_speed: float = 8.0
@export_range(0.0, 50.0, 0.5) var gravity: float = 20.0

## Configuración de evitación
@export_group("Avoidance")
@export_range(0.5, 5.0, 0.1) var avoidance_radius: float = 2.5
@export_range(0.5, 4.0, 0.1) var separation_radius: float = 2.0
@export_range(0.1, 3.0, 0.1) var max_avoidance_force: float = 1.5
@export_range(1.0, 10.0, 0.5) var push_strength: float = 6.0

## Configuración de detección de atasco
@export_group("Stuck Detection")
@export_range(0.1, 2.0, 0.05) var stuck_threshold: float = 0.5
@export_range(0.5, 3.0, 0.1) var stuck_time_limit: float = 1.0

## Estado de la unidad
var is_selected: bool = false
var is_moving: bool = false
var target_position: Vector3 = Vector3.ZERO
var current_flow_direction: Vector3 = Vector3.ZERO

## Identificación y detección de atasco
var unit_id: int = 0
var last_position: Vector3 = Vector3.ZERO
var stuck_timer: float = 0.0

## Referencias en caché
var _flow_field: FlowField3D = null
var _space_state: PhysicsDirectSpaceState3D = null

## Nodos hijos
@onready var mesh: MeshInstance3D = $Body
@onready var selection_ring: MeshInstance3D = $SelectionIndicator

# Constantes para optimización
const ARRIVAL_THRESHOLD: float = 1.0
const MIN_DIRECTION_LENGTH: float = 0.01
const SEPARATION_WEIGHT: float = 1.5
const PUSH_MULTIPLIER_IDLE: float = 2.0
const MAX_SEPARATION_CHECKS: int = 10
const MAX_PUSH_CHECKS: int = 8
const RAY_ANGLES: Array[float] = [-30.0, -15.0, 0.0, 15.0, 30.0]
const RAY_HEIGHT_OFFSET: float = 0.5


func _ready() -> void:
	_initialize_unit()
	_setup_physics()
	_cache_references()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	
	if not is_moving:
		_stop_movement()
		return
	
	if not _validate_flow_field():
		return
	
	_update_movement(delta)


## Inicialización
func _initialize_unit() -> void:
	unit_id = randi()
	last_position = global_position


func _setup_physics() -> void:
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(45.0)
	floor_snap_length = 0.5


func _cache_references() -> void:
	_flow_field = get_node_or_null("../FlowField3D")
	_space_state = get_world_3d().direct_space_state


## Selección visual
func set_selected(value: bool) -> void:
	is_selected = value
	if selection_ring:
		selection_ring.visible = value


## Control de movimiento
func set_target(pos: Vector3) -> void:
	target_position = pos
	is_moving = true
	stuck_timer = 0.0


func stop() -> void:
	is_moving = false
	velocity = Vector3.ZERO
	stuck_timer = 0.0


## Física y gravedad
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _stop_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


## Validación
func _validate_flow_field() -> bool:
	if not _flow_field:
		_flow_field = get_node_or_null("../FlowField3D")
		if not _flow_field:
			move_and_slide()
			return false
	return true


## Actualización de movimiento principal
func _update_movement(delta: float) -> void:
	# Obtener dirección del flow field
	current_flow_direction = _flow_field.get_flow_direction(global_position)
	
	if current_flow_direction == Vector3.ZERO:
		stop()
		return
	
	# Calcular fuerzas
	var desired_direction: Vector3 = current_flow_direction
	var separation_force: Vector3 = _calculate_separation_force()
	var avoidance_force: Vector3 = _calculate_obstacle_avoidance()
	
	# Combinar fuerzas
	var final_direction: Vector3 = (
		desired_direction + 
		separation_force * SEPARATION_WEIGHT + 
		avoidance_force
	).normalized()
	
	# Manejo de atasco
	if _is_stuck(delta):
		final_direction = _handle_stuck_state(final_direction)
	
	# Aplicar rotación y movimiento
	_rotate_towards_direction(final_direction, delta)
	_apply_velocity(final_direction)
	
	move_and_slide()
	_push_nearby_units(delta)
	
	# Verificar llegada
	_check_arrival()


## Detección de atasco
func _is_stuck(delta: float) -> bool:
	var distance_moved: float = global_position.distance_to(last_position)
	
	if distance_moved < stuck_threshold * delta:
		stuck_timer += delta
		return stuck_timer > stuck_time_limit
	else:
		stuck_timer = 0.0
		last_position = global_position
		return false


func _handle_stuck_state(current_direction: Vector3) -> Vector3:
	var unstuck_dir: Vector3 = _get_unstuck_direction()
	stuck_timer = 0.0
	last_position = global_position
	return (current_direction + unstuck_dir).normalized()


func _get_unstuck_direction() -> Vector3:
	var perpendicular := Vector3(-current_flow_direction.z, 0, current_flow_direction.x)
	var random_side: float = 1.0 if randf() > 0.5 else -1.0
	return perpendicular * random_side * 2.0


## Separación de unidades
func _calculate_separation_force() -> Vector3:
	if not _space_state:
		_space_state = get_world_3d().direct_space_state
		if not _space_state:
			return Vector3.ZERO
	
	var separation := Vector3.ZERO
	
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = separation_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 1 << 1  # Layer 2: Units
	query.exclude = [self]
	
	var results: Array[Dictionary] = _space_state.intersect_shape(query, MAX_SEPARATION_CHECKS)
	
	for result in results:
		var collider: Node3D = result.get("collider")
		if not collider or collider == self or not collider is CharacterBody3D:
			continue
		
		var away := global_position - collider.global_position
		away.y = 0.0
		
		var distance: float = away.length()
		if distance > MIN_DIRECTION_LENGTH and distance < separation_radius:
			var strength: float = 1.0 - (distance / separation_radius)
			separation += away.normalized() * strength
	
	if separation.length() > max_avoidance_force:
		separation = separation.normalized() * max_avoidance_force
	
	return separation


## Evitación de obstáculos
func _calculate_obstacle_avoidance() -> Vector3:
	if not _space_state:
		return Vector3.ZERO
	
	var avoidance := Vector3.ZERO
	var forward := -transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	var rays_hit: int = 0
	
	for angle_deg in RAY_ANGLES:
		var angle: float = deg_to_rad(angle_deg)
		var direction: Vector3 = forward.rotated(Vector3.UP, angle)
		
		var from: Vector3 = global_position + Vector3.UP * RAY_HEIGHT_OFFSET
		var to: Vector3 = from + direction * avoidance_radius
		
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = (1 << 0) | (1 << 3)  # Terrain + Obstacles
		query.exclude = [self]
		
		var result: Dictionary = _space_state.intersect_ray(query)
		
		if result:
			rays_hit += 1
			var hit_normal: Vector3 = result.get("normal", Vector3.UP)
			hit_normal.y = 0.0
			if hit_normal.length() > MIN_DIRECTION_LENGTH:
				avoidance += hit_normal.normalized()
	
	if rays_hit > 0:
		avoidance = avoidance.normalized() * max_avoidance_force
	
	return avoidance


## Sistema de empuje
func _push_nearby_units(delta: float) -> void:
	if not _space_state:
		return
	
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 1 << 1  # Layer 2: Units
	query.exclude = [self]
	
	var results: Array[Dictionary] = _space_state.intersect_shape(query, MAX_PUSH_CHECKS)
	
	for result in results:
		var collider: Node3D = result.get("collider")
		if not collider or collider == self or not collider is RTSUnit3D:
			continue
		
		_apply_push_to_unit(collider as RTSUnit3D, delta)


func _apply_push_to_unit(other: RTSUnit3D, delta: float) -> void:
	var push_dir: Vector3 = other.global_position - global_position
	push_dir.y = 0.0
	
	var distance: float = push_dir.length()
	if distance < MIN_DIRECTION_LENGTH or distance >= 1.5:
		return
	
	push_dir = push_dir.normalized()
	
	var force_multiplier: float = PUSH_MULTIPLIER_IDLE if not other.is_moving else 1.0
	var push_amount: float = push_strength * (1.0 - distance / 1.5) * force_multiplier
	
	other.global_position += push_dir * push_amount * delta


## Rotación y movimiento
func _rotate_towards_direction(direction: Vector3, delta: float) -> void:
	if direction.length() < MIN_DIRECTION_LENGTH:
		return
	
	var target_rot: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rot, delta * rotation_speed)


func _apply_velocity(direction: Vector3) -> void:
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed


## Verificación de llegada
func _check_arrival() -> void:
	var distance_xz: float = Vector2(
		global_position.x - target_position.x,
		global_position.z - target_position.z
	).length()
	
	if distance_xz < ARRIVAL_THRESHOLD:
		stop()
