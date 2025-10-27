extends CharacterBody3D
class_name RTSUnit3D

## --------------------------------------------------------------------------
## CONFIGURACIÓN GENERAL
## --------------------------------------------------------------------------

@export var move_speed: float = 5.0           # Velocidad de movimiento (unidades por segundo)
@export var rotation_speed: float = 10.0      # Velocidad de rotación (grados por segundo)
@export var arrival_distance: float = 1.0     # Distancia mínima para considerar que la unidad llegó a su destino
@export var ground_check_distance: float = 10.0 # Distancia vertical para detectar el suelo mediante raycast

## --------------------------------------------------------------------------
## VARIABLES DE ESTADO
## --------------------------------------------------------------------------

var flow_field: FlowField3D                   # Referencia al FlowField (campo vectorial de navegación)
var target_position: Vector3 = Vector3.ZERO   # Posición objetivo actual
var is_moving: bool = false                   # Indica si la unidad está actualmente en movimiento

## --------------------------------------------------------------------------
## SELECCIÓN Y VISUALIZACIÓN
## --------------------------------------------------------------------------

@onready var selection_indicator: MeshInstance3D = $SelectionIndicator  # Círculo o marcador bajo la unidad
var is_selected: bool = false                                            # Estado de selección de la unidad

## --------------------------------------------------------------------------
## CICLO DE VIDA
## --------------------------------------------------------------------------

func _ready():
	"""
	Inicializa la unidad al cargar la escena.
	Busca el FlowField más cercano o un nodo relativo y oculta el indicador de selección.
	"""
	
	# Intenta obtener el FlowField de la escena (ajusta esta ruta según tu estructura)
	flow_field = $"../FlowField3D"
	
	# Ocultar el indicador de selección al inicio
	if selection_indicator:
		selection_indicator.visible = false

## --------------------------------------------------------------------------
## COMANDOS EXTERNOS
## --------------------------------------------------------------------------

func set_target(target: Vector3) -> void:
	"""
	Asigna un nuevo objetivo de movimiento a la unidad.
	@param target: posición destino en el mundo.
	"""
	target_position = target
	is_moving = true

func set_selected(selected: bool) -> void:
	"""
	Cambia el estado de selección visual de la unidad.
	@param selected: true para seleccionada, false para no seleccionada.
	"""
	is_selected = selected
	if selection_indicator:
		selection_indicator.visible = selected

func stop() -> void:
	"""
	Detiene cualquier movimiento activo.
	"""
	is_moving = false
	velocity = Vector3.ZERO

## --------------------------------------------------------------------------
## PROCESO PRINCIPAL DE FÍSICA
## --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	"""
	Actualiza el movimiento, rotación y altura de la unidad en cada frame físico.
	"""
	
	# Si no hay movimiento o no existe flow field, no hacer nada
	if not is_moving or not flow_field:
		return
	
	# ----------------------------------------------------------------------
	# 1. Comprobar si la unidad ha llegado a su destino
	# ----------------------------------------------------------------------
	var flat_distance = Vector3(
		global_position.x - target_position.x,
		0,
		global_position.z - target_position.z
	).length()
	
	if flat_distance < arrival_distance:
		stop()
		return
	
	# ----------------------------------------------------------------------
	# 2. Obtener dirección del flow field o dirección directa
	# ----------------------------------------------------------------------
	var flow_direction: Vector3 = flow_field.get_flow_direction(global_position)
	
	if flow_direction.length() > 0.01:
		# Movimiento guiado por flow field
		var target_velocity = flow_direction * move_speed
		velocity.x = target_velocity.x
		velocity.z = target_velocity.z
		rotate_towards_direction(flow_direction, delta)
	else:
		# Fallback: moverse directamente hacia el objetivo
		var direction = (target_position - global_position).normalized()
		direction.y = 0  # Mantener movimiento en plano XZ
		if direction.length() > 0.01:
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			rotate_towards_direction(direction, delta)
	
	# ----------------------------------------------------------------------
	# 3. Aplicar gravedad si no está en el suelo
	# ----------------------------------------------------------------------
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	
	# ----------------------------------------------------------------------
	# 4. Aplicar movimiento físico
	# ----------------------------------------------------------------------
	move_and_slide()
	
	# ----------------------------------------------------------------------
	# 5. Ajustar altura al terreno
	# ----------------------------------------------------------------------
	adjust_to_ground()

## --------------------------------------------------------------------------
## ROTACIÓN Y ALTURA
## --------------------------------------------------------------------------

func rotate_towards_direction(direction: Vector3, delta: float) -> void:
	"""
	Rota suavemente a la unidad hacia la dirección deseada.
	@param direction: vector de dirección objetivo (en el plano XZ)
	@param delta: tiempo transcurrido del frame físico
	"""
	if direction.length() < 0.01:
		return
	
	var target_rotation = atan2(direction.x, direction.z)
	var current_rotation = rotation.y
	
	# Interpolación angular suave
	var new_rotation = lerp_angle(current_rotation, target_rotation, rotation_speed * delta)
	rotation.y = new_rotation

func adjust_to_ground() -> void:
	"""
	Ajusta la posición Y de la unidad al terreno usando raycast hacia abajo.
	Mantiene la unidad pegada al suelo, útil para terrenos irregulares.
	"""
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 2.0,
		global_position + Vector3.DOWN * ground_check_distance
	)
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Suaviza el ajuste vertical para evitar saltos bruscos
		var target_y = result.position.y
		global_position.y = lerp(global_position.y, target_y, 0.1)

## --------------------------------------------------------------------------
## INFORMACIÓN PARA INTERFAZ O DEPURACIÓN
## --------------------------------------------------------------------------

func get_unit_info() -> Dictionary:
	"""
	Devuelve información del estado actual de la unidad.
	Puede usarse para paneles de UI o depuración.
	"""
	return {
		"position": global_position,
		"is_moving": is_moving,
		"target": target_position,
		"selected": is_selected
	}
