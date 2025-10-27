extends Node3D

@onready var flow_field: FlowField3D = $FlowField3D
@onready var camera: Camera3D = $RTScamera
@onready var selection_box: SelectionBoxUI = $SelectionUILayer/SelectionBoxUI
@export var unit_scene: PackedScene
@export var ground_layer: int = 1
@export var unit_layer: int = 2

var selection_start: Vector2
var selection_end: Vector2

var selected_units: Array = []
var all_units: Array = []

# Para box selection
var is_selecting: bool = false

func _ready():
	setup_obstacles()
	spawn_test_units()

func setup_obstacles():
	"""Configura obstáculos iniciales"""
	# Ejemplos de obstáculos
	flow_field.set_obstacle_area(Vector3(20, 0, 15), 3, true)
	flow_field.set_obstacle_area(Vector3(40, 0, 25), 4, true)
	flow_field.set_obstacle_area(Vector3(15, 0, 35), 2, true)
	
	# Áreas con costo elevado (terreno difícil)
	flow_field.set_cost_area(Vector3(30, 0, 30), 5, 3)  # Lodo/arena

func spawn_test_units():
	"""Crea unidades de prueba"""
	if not unit_scene:
		push_warning("No unit scene assigned")
		return
	
	for i in range(30):
		var unit = unit_scene.instantiate()
		add_child(unit)
		
		var x = 5 + (i % 4) * 3
		var z = 5 + int(i / 4) * 3
		unit.global_position = Vector3(x, 1, z)
		
		all_units.append(unit)

func _input(event):
	if event is InputEventMouseButton:
		handle_mouse_click(event)
	
	elif event is InputEventMouseMotion and is_selecting:
		selection_end = event.position

func handle_mouse_click(event: InputEventMouseButton):
	"""Maneja clicks del mouse"""
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Click derecho: mover unidades
		var world_pos = get_world_position_from_mouse(event.position)
		if world_pos != Vector3.ZERO:
			move_selected_units(world_pos)
	
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Iniciar selección
			selection_start = event.position
			is_selecting = true
			
			# Verificar si se clickeó una unidad
			if not Input.is_key_pressed(KEY_SHIFT):
				var unit = get_unit_at_mouse(event.position)
				if unit:
					clear_selection()
					select_unit(unit)
					is_selecting = false
		else:
			# Finalizar selección
			if is_selecting:
				selection_end = event.position
				perform_box_selection()
				is_selecting = false

func get_world_position_from_mouse(mouse_pos: Vector2) -> Vector3:
	"""Convierte posición del mouse a coordenadas 3D del mundo"""
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ground_layer
	
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position
	
	return Vector3.ZERO

func get_unit_at_mouse(mouse_pos: Vector2) -> RTSUnit3D:
	"""Obtiene la unidad bajo el cursor del mouse"""
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = unit_layer
	
	var result = space_state.intersect_ray(query)
	
	if result and result.collider is RTSUnit3D:
		return result.collider
	
	return null

func perform_box_selection():
	"""Selecciona unidades dentro del área de selección"""
	var rect = get_selection_rect()
	
	if not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()
	
	for unit in all_units:
		var screen_pos = camera.unproject_position(unit.global_position)
		if rect.has_point(screen_pos):
			select_unit(unit)

func get_selection_rect() -> Rect2:
	"""Crea un rectángulo desde el inicio hasta el final de la selección"""
	var start = selection_start
	var end = selection_end
	
	var min_x = min(start.x, end.x)
	var min_y = min(start.y, end.y)
	var width = abs(end.x - start.x)
	var height = abs(end.y - start.y)
	
	return Rect2(min_x, min_y, width, height)

func select_unit(unit: RTSUnit3D):
	"""Selecciona una unidad"""
	if unit not in selected_units:
		selected_units.append(unit)
		unit.set_selected(true)

func clear_selection():
	"""Limpia la selección actual"""
	for unit in selected_units:
		unit.set_selected(false)
	selected_units.clear()

func move_selected_units(target_pos: Vector3):
	"""Mueve las unidades seleccionadas al objetivo"""
	if selected_units.size() == 0:
		return
	
	# Generar flow field
	flow_field.generate_flow_field(target_pos)
	
	# Aplicar formación (spread circular)
	var spread_radius = 2.0
	var angle_step = TAU / selected_units.size() if selected_units.size() > 1 else 0
	
	for i in range(selected_units.size()):
		var unit = selected_units[i]
		var offset = Vector3.ZERO
		
		if selected_units.size() > 1:
			var angle = i * angle_step
			offset = Vector3(cos(angle), 0, sin(angle)) * spread_radius
		
		unit.set_target(target_pos + offset)

func add_obstacle_at_position(world_pos: Vector3, radius: int = 2):
	"""Añade un obstáculo en tiempo real"""
	flow_field.set_obstacle_area(world_pos, radius, true)
	
	# Regenerar flow field si hay unidades en movimiento
	for unit in selected_units:
		if unit.is_moving:
			flow_field.generate_flow_field(unit.target_position)
			break

func _process(_delta):
	# Debug: Toggle visualización
	if Input.is_action_just_pressed("ui_accept"):
		flow_field.debug_draw = !flow_field.debug_draw
		if flow_field.debug_draw:
			flow_field.update_debug_visualization()
		else:
			flow_field.clear_debug()
	
	# Debug: Añadir obstáculo con tecla O
	if Input.is_action_just_pressed("ui_cancel"):
		var mouse_pos = get_viewport().get_mouse_position()
		var world_pos = get_world_position_from_mouse(mouse_pos)
		if world_pos != Vector3.ZERO:
			add_obstacle_at_position(world_pos, 2)
