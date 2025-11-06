# ============================================
# 1. SCRIPT DEL BARCO CON TIMÓN REALISTA
# boat.gd - Asignar a CharacterBody3D
# ============================================
extends CharacterBody3D

@export_group("Referencias")
@export var ocean: Ocean
@export var foam_particles: GPUParticles3D  # Espuma en la proa
@export var wake_particles: GPUParticles3D  # Estela trasera

@export_group("Física de Flotación")
@export var float_strength: float = 5.0
@export var rotation_strength: float = 3.0
@export var buoyancy_offset: float = 0.5
@export var float_points: Array[Vector3] = [
	Vector3(-1, 0, 2),   # Proa izquierda
	Vector3(1, 0, 2),    # Proa derecha
	Vector3(-1, 0, -2),  # Popa izquierda
	Vector3(1, 0, -2)    # Popa derecha
]

@export_group("Control de Navegación")
@export var max_speed: float = 15.0
@export var acceleration: float = 2.0
@export var deceleration: float = 4.0

##Velocidad de giro del timón
@export var turn_speed: float = 1.5

##Ángulo máximo del timón en grados
@export var max_turn_angle: float = 45.0

##Resistencia del agua
@export var drag_coefficient: float = 0.3

# Variables internas
var current_speed: float = 0.0
var rudder_angle: float = 0.0  # Ángulo actual del timón (-1 a 1)
var target_rudder_angle: float = 0.0

func _ready():
	# Configurar partículas inicialmente apagadas
	if foam_particles:
		foam_particles.emitting = false
	if wake_particles:
		wake_particles.emitting = false

func _physics_process(delta):
	if not ocean:
		return
	
	# Control de entrada
	handle_input(delta)
	
	# Física de navegación
	apply_boat_physics(delta)
	
	# Flotación y rotación
	apply_buoyancy(delta)
	
	# Efectos visuales
	update_particle_effects()
	
	move_and_slide()

func handle_input(delta):
	# Aceleración (W/S o flechas arriba/abajo)
	var throttle = Input.get_axis("ui_down", "ui_up")
	
	if throttle != 0:
		current_speed += throttle * acceleration * delta
		current_speed = clamp(current_speed, -max_speed * 0.5, max_speed)
	else:
		# Desaceleración natural
		current_speed = move_toward(current_speed, 0, deceleration * delta)
	
	# Control del timón (A/D o flechas izq/der)
	target_rudder_angle = Input.get_axis("ui_left", "ui_right")
	
	# Suavizar el movimiento del timón
	rudder_angle = lerp(rudder_angle, target_rudder_angle, turn_speed * delta * 5.0)

func apply_boat_physics(delta):
	# El giro solo es efectivo cuando hay velocidad
	var turn_effectiveness = abs(current_speed) / max_speed
	var turn_rate = rudder_angle * deg_to_rad(max_turn_angle) * turn_effectiveness * delta
	
	# Rotar el barco
	rotate_y(turn_rate)
	
	# Aplicar velocidad en la dirección actual
	var forward = -transform.basis.z
	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed
	
	# Drag lateral (resistencia al deslizamiento lateral)
	var lateral = transform.basis.x
	var lateral_velocity = velocity.dot(lateral)
	velocity -= lateral * lateral_velocity * drag_coefficient

func apply_buoyancy(delta):
	var average_height = 0.0
	var point_count = 0
	
	# Calcular altura promedio
	for point in float_points:
		var world_point = global_position + transform.basis * point
		var wave_height = ocean.get_wave_height(world_point)
		average_height += wave_height
		point_count += 1
	
	if point_count > 0:
		average_height /= point_count
	
	# Flotación vertical
	var target_y = average_height + buoyancy_offset
	global_position.y = lerp(global_position.y, target_y, float_strength * delta)
	
	# Rotación según las olas
	var wave_normal = ocean.get_wave_normal(global_position)
	var up = wave_normal
	var right = -transform.basis.z.cross(up).normalized()
	var forward = right.cross(up).normalized()
	
	# Crear y ORTOGONALIZAR la base target
	var target_basis = Basis(right, up, -forward).orthonormalized()
	
	# Interpolar suavemente (ahora sí funcionará)
	transform.basis = transform.basis.slerp(target_basis, rotation_strength * delta)

func update_particle_effects():
	var speed_threshold = 2.0  # Velocidad mínima para generar espuma
	var is_moving = abs(current_speed) > speed_threshold
	
	if foam_particles:
		foam_particles.emitting = is_moving
		# Ajustar cantidad de espuma según velocidad
		var speed_ratio = clamp(abs(current_speed) / max_speed, 0.0, 1.0)
		foam_particles.amount_ratio = speed_ratio
	
	if wake_particles:
		wake_particles.emitting = is_moving
		var speed_ratio = clamp(abs(current_speed) / max_speed, 0.0, 1.0)
		wake_particles.amount_ratio = speed_ratio * 0.8
