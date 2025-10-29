extends Node3D
class_name FlowField3D

## Sistema de Flow Field 3D para RTS
## Genera un campo vectorial de navegación que dirige múltiples unidades
## hacia un objetivo común, considerando obstáculos y costos de terreno.

## Configuración del grid
@export_group("Grid Configuration")
@export_range(0.5, 5.0, 0.1) var cell_size: float = 2.0
@export_range(10, 200, 5) var grid_width: int = 50
@export_range(10, 200, 5) var grid_depth: int = 50

## Configuración de visualización
@export_group("Debug Visualization")
@export var debug_draw: bool = true
@export_range(0.1, 2.0, 0.1) var debug_arrow_height: float = 0.5
@export var debug_arrow_scale: float = 0.4
@export var obstacle_color: Color = Color.RED
@export var flow_color: Color = Color.GREEN

## Campos de datos
var cost_field: PackedInt32Array
var integration_field: PackedInt32Array
var flow_field: PackedVector3Array

## Constantes
const INF: int = 999999
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                    Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),   Vector2i(1, 1)
]

## Visualización debug
var _debug_mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _debug_material: StandardMaterial3D

## Cache para optimización
var _grid_size: int = 0
var _half_cell_size: float = 0.0
var _last_target: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_calculate_cache()
	_initialize_fields()
	_setup_debug_visualization()


## Inicialización
func _calculate_cache() -> void:
	_grid_size = grid_width * grid_depth
	_half_cell_size = cell_size * 0.5


func _initialize_fields() -> void:
	# Usar PackedArrays para mejor rendimiento
	cost_field = PackedInt32Array()
	integration_field = PackedInt32Array()
	flow_field = PackedVector3Array()
	
	cost_field.resize(_grid_size)
	integration_field.resize(_grid_size)
	flow_field.resize(_grid_size)
	
	# Inicializar con valores por defecto
	cost_field.fill(1)
	integration_field.fill(INF)
	flow_field.fill(Vector3.ZERO)


func _setup_debug_visualization() -> void:
	if not debug_draw:
		return
	
	_immediate_mesh = ImmediateMesh.new()
	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.mesh = _immediate_mesh
	
	_debug_material = StandardMaterial3D.new()
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.vertex_color_use_as_albedo = true
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_mesh_instance.material_override = _debug_material
	
	add_child(_debug_mesh_instance)


## Conversión de coordenadas
func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(world_pos.x / cell_size),
		int(world_pos.z / cell_size)
	)


func grid_to_world(grid_pos: Vector2i, y_height: float = 0.0) -> Vector3:
	return Vector3(
		grid_pos.x * cell_size + _half_cell_size,
		y_height,
		grid_pos.y * cell_size + _half_cell_size
	)


func is_valid_cell(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_depth


func _get_index(pos: Vector2i) -> int:
	return pos.y * grid_width + pos.x


## Manejo de obstáculos y terrenos
func set_obstacle(world_pos: Vector3, is_obstacle: bool = true) -> void:
	var grid_pos := world_to_grid(world_pos)
	if is_valid_cell(grid_pos):
		var idx := _get_index(grid_pos)
		cost_field[idx] = INF if is_obstacle else 1


func set_obstacle_area(world_pos: Vector3, radius: int = 1, is_obstacle: bool = true) -> void:
	var center := world_to_grid(world_pos)
	var cost_value := INF if is_obstacle else 1
	var radius_sq := radius * radius
	
	for z in range(-radius, radius + 1):
		var z_sq := z * z
		for x in range(-radius, radius + 1):
			if x * x + z_sq <= radius_sq:
				var pos := Vector2i(center.x + x, center.y + z)
				if is_valid_cell(pos):
					var idx := _get_index(pos)
					cost_field[idx] = cost_value


func set_cost_area(world_pos: Vector3, radius: int = 1, cost: int = 1) -> void:
	var center := world_to_grid(world_pos)
	var radius_sq := radius * radius
	
	for z in range(-radius, radius + 1):
		var z_sq := z * z
		for x in range(-radius, radius + 1):
			if x * x + z_sq <= radius_sq:
				var pos := Vector2i(center.x + x, center.y + z)
				if is_valid_cell(pos):
					var idx := _get_index(pos)
					cost_field[idx] = cost


## Generación del Flow Field
func generate_flow_field(target_world_pos: Vector3) -> void:
	var target_grid := world_to_grid(target_world_pos)
	
	if not is_valid_cell(target_grid):
		push_warning("⚠️ Target fuera de los límites del grid.")
		return
	
	# Evitar recalcular si el target es el mismo
	if target_grid == _last_target:
		return
	
	_last_target = target_grid
	
	# Reset del integration field
	integration_field.fill(INF)
	
	_generate_integration_field(target_grid)
	_generate_flow_directions()
	
	if debug_draw:
		_update_debug_visualization()


## Calcula el costo acumulado desde cada celda hasta la celda objetivo (target).
## Utiliza un algoritmo de búsqueda en anchura (similar a Dijkstra) para propagar los costos.
func _generate_integration_field(target: Vector2i) -> void:
	var open_list: Array[Vector2i] = [target]
	var target_idx := _get_index(target)
	integration_field[target_idx] = 0
	
	while open_list.size() > 0:
		var current: Vector2i = open_list.pop_front() # Nota: Corregido a Vector2i
		var current_idx := _get_index(current)
		var current_cost := integration_field[current_idx]
		
		for dir in DIRECTIONS:
			var neighbor: Vector2i = current + dir # Nota: Corregido a Vector2i
			if not is_valid_cell(neighbor):
				continue
			
			var neighbor_idx := _get_index(neighbor)
			
			if cost_field[neighbor_idx] == INF:
				continue

			# --- INICIO DEL CÓDIGO INTEGRADO ---
			
			# Obtenemos el costo base del terreno (que normalmente es 1)
			var cost_to_neighbor := cost_field[neighbor_idx]

			# Calculamos el ángulo desde el 'target' (objetivo) a la 'vecina' (neighbor)
			var angle = Vector2(target).angle_to_point(Vector2(neighbor))
			
			# Comparamos el ángulo con el ángulo "snap" más cercano a 90 grados (PI/2).
			# PI / 12 equivale a 15 grados.
			# Si la diferencia es mayor a 15 grados, significa que NO es un movimiento
			# puramente cardinal (recto).
			if abs(angle - snappedf(angle, PI / 2.0)) > PI / 12.0:
				# Si no es un movimiento recto, le añadimos un costo extra.
				cost_to_neighbor += 1

			# Calculamos el nuevo costo usando el costo modificado
			var new_cost := current_cost + cost_to_neighbor
			
			# --- FIN DEL CÓDIGO INTEGRADO ---
			
			if new_cost < integration_field[neighbor_idx]:
				integration_field[neighbor_idx] = new_cost
				open_list.append(neighbor)


## Genera los vectores de dirección para cada celda del grid basándose en el campo de integración.
func _generate_flow_directions() -> void:
	# 1. Itera sobre cada fila del grid (coordenada Z).
	for z in range(grid_depth):
		# 2. Itera sobre cada columna del grid (coordenada X).
		for x in range(grid_width):
			# 3. Calcula el índice 1D correspondiente a la coordenada (x, z).
			var idx := z * grid_width + x
			
			# 4. Si la celda actual es un obstáculo...
			if cost_field[idx] == INF:
				# 5. ...asigna un vector nulo (sin movimiento) y...
				flow_field[idx] = Vector3.ZERO
				# 6. ...salta a la siguiente celda del bucle.
				continue
			
			# 7. Crea una variable 'current' con la posición 2D de la celda actual.
			var current := Vector2i(x, z)
			
			# 8. 'best_dir' almacenará la dirección hacia la mejor vecina (la más barata).
			#    Se inicializa a un vector cero.
			var best_dir := Vector2.ZERO
			
			# 9. 'lowest' almacenará el costo de la mejor vecina encontrada hasta ahora.
			#    Se inicializa con el costo de la PROPIA celda actual.
			var lowest := integration_field[idx]
			
			# 10. Itera a través de las 8 direcciones para encontrar las celdas vecinas.
			for dir in DIRECTIONS:
				# 11. Calcula la posición de la celda vecina.
				var neighbor := current + dir
				
				# 12. Si la vecina está fuera del grid, la ignora y continúa.
				if not is_valid_cell(neighbor):
					continue
				
				# 13. Obtiene el índice de la vecina.
				var neighbor_idx := _get_index(neighbor)
				# 14. Obtiene el costo de integración de la vecina.
				var neighbor_cost := integration_field[neighbor_idx]
				
				# 15. Compara: si el costo de esta vecina es menor que el más bajo que hemos encontrado...
				if neighbor_cost < lowest:
					# 16. ...actualiza 'lowest' con este nuevo costo más bajo.
					lowest = neighbor_cost
					# 17. ...y guarda la dirección ('dir') que nos llevó a esta mejor vecina.
					best_dir = Vector2(dir)
			
			# 18. Después de revisar todas las vecinas, si 'best_dir' ya no es un vector cero...
			#     (es decir, si encontramos una vecina con un costo menor).
			if best_dir.length_squared() > 0:
				# 19. ...convierte la dirección 2D a un vector 3D (Y=0), normalízalo (para que solo
				#     represente dirección, no magnitud) y guárdalo en el flow_field.
				flow_field[idx] = Vector3(best_dir.x, 0, best_dir.y).normalized()
			else:
				# 20. Si no se encontró ninguna vecina mejor (estamos en un mínimo local o una meseta),
				#     asigna un vector de movimiento nulo.
				flow_field[idx] = Vector3.ZERO


func get_flow_direction(world_pos: Vector3) -> Vector3:
	var grid_pos := world_to_grid(world_pos)
	if not is_valid_cell(grid_pos):
		return Vector3.ZERO
	
	var idx := _get_index(grid_pos)
	return flow_field[idx]


## Depuración visual
func _update_debug_visualization() -> void:
	if not debug_draw or not _immediate_mesh:
		return
	
	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for z in range(grid_depth):
		for x in range(grid_width):
			var idx := z * grid_width + x
			var world_pos := grid_to_world(Vector2i(x, z), debug_arrow_height)
			
			# Obstáculos en rojo
			if cost_field[idx] == INF:
				_draw_debug_cube(world_pos, obstacle_color)
				continue
			
			# Direcciones del flow field
			var dir := flow_field[idx]
			if dir.length_squared() > 0.001:
				_draw_arrow(world_pos, dir)
	
	_immediate_mesh.surface_end()


func _draw_arrow(start: Vector3, direction: Vector3) -> void:
	var arrow_end := start + direction * cell_size * debug_arrow_scale
	
	# Línea principal
	_immediate_mesh.surface_set_color(flow_color)
	_immediate_mesh.surface_add_vertex(start)
	_immediate_mesh.surface_add_vertex(arrow_end)
	
	# Punta de flecha
	var right := direction.cross(Vector3.UP).normalized() * 0.2
	var back := -direction * 0.3
	
	_immediate_mesh.surface_add_vertex(arrow_end)
	_immediate_mesh.surface_add_vertex(arrow_end + back + right)
	_immediate_mesh.surface_add_vertex(arrow_end)
	_immediate_mesh.surface_add_vertex(arrow_end + back - right)


func _draw_debug_cube(center: Vector3, color: Color) -> void:
	var half := cell_size * 0.4
	_immediate_mesh.surface_set_color(color)
	
	var corners := [
		center + Vector3(-half, 0, -half),
		center + Vector3(half, 0, -half),
		center + Vector3(half, 0, half),
		center + Vector3(-half, 0, half)
	]
	
	for i in range(4):
		_immediate_mesh.surface_add_vertex(corners[i])
		_immediate_mesh.surface_add_vertex(corners[(i + 1) % 4])


func clear_debug() -> void:
	if _immediate_mesh:
		_immediate_mesh.clear_surfaces()


func toggle_debug() -> void:
	debug_draw = not debug_draw
	if debug_draw:
		_update_debug_visualization()
	else:
		clear_debug()


## Utilidades
func clear_all_obstacles() -> void:
	cost_field.fill(1)
	_last_target = Vector2i(-1, -1)


func get_cell_cost(world_pos: Vector3) -> int:
	var grid_pos := world_to_grid(world_pos)
	if not is_valid_cell(grid_pos):
		return INF
	
	var idx := _get_index(grid_pos)
	return cost_field[idx]


func get_grid_info() -> Dictionary:
	return {
		"grid_width": grid_width,
		"grid_depth": grid_depth,
		"cell_size": cell_size,
		"total_cells": _grid_size
	}
