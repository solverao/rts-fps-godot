extends Node3D

## Referencias de nodos
@onready var flow_field: FlowField3D = $FlowField3D
@onready var camera: Camera3D = $GameManager/RTScamera
@onready var selection_box: SelectionBoxUI = $SelectionUILayer/SelectionBoxUI

## Configuración
@export_group("Scene References")
@export var unit_scene: PackedScene

@export_group("Layers")
@export_flags_3d_physics var ground_layer: int = 1
@export_flags_3d_physics var unit_layer: int = 2

@export_group("Unit Spawning")
@export_range(1, 100) var initial_unit_count: int = 20
@export var spawn_grid_columns: int = 4
@export var spawn_spacing: float = 3.0
@export var spawn_start_position: Vector3 = Vector3(5, 1, 5)

@export_group("Formation")
@export_range(0.5, 10.0, 0.5) var formation_spread_radius: float = 2.0

## Estado de selección
var selected_units: Array[RTSUnit3D] = []
var all_units: Array[RTSUnit3D] = []

## Box selection
var is_selecting: bool = false
var selection_start: Vector2 = Vector2.ZERO
var selection_end: Vector2 = Vector2.ZERO

## Cache
var _space_state: PhysicsDirectSpaceState3D = null

## Constantes
const MAX_RAYCAST_DISTANCE: float = 1000.0


func _ready() -> void:
	_cache_references()
	_setup_obstacles()
	_spawn_units()


func _cache_references() -> void:
	_space_state = get_world_3d().direct_space_state


## Configuración inicial
func _setup_obstacles() -> void:
	# Ejemplo de obstáculos predefinidos
	flow_field.set_obstacle_area(Vector3(20, 0, 15), 3, true)
	flow_field.set_obstacle_area(Vector3(40, 0, 25), 4, true)
	
	# Áreas de terreno difícil
	flow_field.set_cost_area(Vector3(30, 0, 30), 5, 3)


func _spawn_units() -> void:
	if not unit_scene:
		push_error("❌ No unit scene assigned to GameManager")
		return
	
	for i in range(initial_unit_count):
		var unit: RTSUnit3D = unit_scene.instantiate()
		add_child(unit)
		
		var col := i % spawn_grid_columns
		var row : int = i / spawn_grid_columns
		
		var spawn_pos := spawn_start_position + Vector3(
			col * spawn_spacing,
			0,
			row * spawn_spacing
		)
		
		unit.global_position = spawn_pos
		all_units.append(unit)


## Input handling
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_click(event)
	elif event is InputEventMouseMotion and is_selecting:
		selection_end = event.position


func _handle_mouse_click(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_handle_right_click(event.position)
		
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_left_click_press(event.position)
			else:
				_handle_left_click_release()


func _handle_right_click(mouse_pos: Vector2) -> void:
	var world_pos := _get_world_position_from_mouse(mouse_pos)
	if world_pos != Vector3.ZERO:
		_move_selected_units(world_pos)


func _handle_left_click_press(mouse_pos: Vector2) -> void:
	selection_start = mouse_pos
	is_selecting = true
	
	# Single unit selection sin SHIFT
	if not Input.is_key_pressed(KEY_SHIFT):
		var unit := _get_unit_at_mouse(mouse_pos)
		if unit:
			_clear_selection()
			_select_unit(unit)
			is_selecting = false


func _handle_left_click_release() -> void:
	if is_selecting:
		selection_end = get_viewport().get_mouse_position()
		_perform_box_selection()
		is_selecting = false


## Raycasting
func _get_world_position_from_mouse(mouse_pos: Vector2) -> Vector3:
	if not _space_state:
		_cache_references()
		if not _space_state:
			return Vector3.ZERO
	
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * MAX_RAYCAST_DISTANCE
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ground_layer
	
	var result := _space_state.intersect_ray(query)
	
	return result.position if result else Vector3.ZERO


func _get_unit_at_mouse(mouse_pos: Vector2) -> RTSUnit3D:
	if not _space_state:
		return null
	
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * MAX_RAYCAST_DISTANCE
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = unit_layer
	
	var result := _space_state.intersect_ray(query)
	
	if result and result.collider is RTSUnit3D:
		return result.collider as RTSUnit3D
	
	return null


## Box selection
func _perform_box_selection() -> void:
	var rect := _get_selection_rect()
	
	# Si el rectángulo es muy pequeño, ignorar
	if rect.get_area() < 25.0:
		return
	
	if not Input.is_key_pressed(KEY_SHIFT):
		_clear_selection()
	
	for unit in all_units:
		var screen_pos := camera.unproject_position(unit.global_position)
		if rect.has_point(screen_pos):
			_select_unit(unit)


func _get_selection_rect() -> Rect2:
	var start := selection_start
	var end := selection_end
	
	var min_x : Variant = min(start.x, end.x)
	var min_y : Variant = min(start.y, end.y)
	var width : Variant = abs(end.x - start.x)
	var height : Variant = abs(end.y - start.y)
	
	return Rect2(min_x, min_y, width, height)


## Unit selection
func _select_unit(unit: RTSUnit3D) -> void:
	if unit not in selected_units:
		selected_units.append(unit)
		unit.set_selected(true)


func _clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.set_selected(false)
	selected_units.clear()


## Movement commands
func _move_selected_units(target_pos: Vector3) -> void:
	if selected_units.is_empty():
		return
	
	# Generar flow field
	flow_field.generate_flow_field(target_pos)
	
	# Aplicar formación
	_apply_formation(target_pos)


func _apply_formation(target_pos: Vector3) -> void:
	var unit_count := selected_units.size()
	
	if unit_count == 1:
		selected_units[0].set_target(target_pos)
		return
	
	var angle_step := TAU / float(unit_count)
	
	for i in range(unit_count):
		var unit := selected_units[i]
		var angle := i * angle_step
		var offset := Vector3(
			cos(angle) * formation_spread_radius,
			0,
			sin(angle) * formation_spread_radius
		)
		
		unit.set_target(target_pos + offset)


## Dynamic obstacle management
func add_obstacle_at_position(world_pos: Vector3, radius: int = 2) -> void:
	flow_field.set_obstacle_area(world_pos, radius, true)
	
	# Regenerar flow field si hay unidades en movimiento
	_regenerate_flow_field_if_moving()


func remove_obstacle_at_position(world_pos: Vector3, radius: int = 2) -> void:
	flow_field.set_obstacle_area(world_pos, radius, false)
	_regenerate_flow_field_if_moving()


func _regenerate_flow_field_if_moving() -> void:
	for unit in selected_units:
		if unit.is_moving:
			flow_field.generate_flow_field(unit.target_position)
			break


## Debug y utilidades
func _process(_delta: float) -> void:
	_handle_debug_input()


func _handle_debug_input() -> void:
	# Toggle visualización flow field
	if Input.is_action_just_pressed("ui_accept"):
		flow_field.toggle_debug()
	
	# Añadir obstáculo con Escape
	if Input.is_action_just_pressed("ui_cancel"):
		var mouse_pos := get_viewport().get_mouse_position()
		var world_pos := _get_world_position_from_mouse(mouse_pos)
		if world_pos != Vector3.ZERO:
			add_obstacle_at_position(world_pos, 2)
	
	# Debug: Seleccionar todas las unidades con Ctrl+A
	if Input.is_key_pressed(KEY_CTRL) and Input.is_action_just_pressed("ui_text_select_all"):
		_select_all_units()
	
	# Debug: Detener todas las unidades con S
	if Input.is_action_just_pressed("ui_text_backspace"):
		_stop_all_selected_units()


func _select_all_units() -> void:
	_clear_selection()
	for unit in all_units:
		_select_unit(unit)


func _stop_all_selected_units() -> void:
	for unit in selected_units:
		unit.stop()


## Cleanup
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_selection()
		all_units.clear()
