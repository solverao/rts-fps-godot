extends Node3D
class_name FlowField3D

# Configuración del grid
@export var cell_size: float = 2.0
@export var grid_width: int = 50
@export var grid_depth: int = 50
@export var debug_draw: bool = true
@export var debug_arrow_height: float = 0.5

# Capas de información
var cost_field: Array = []  # Costo de cada celda
var integration_field: Array = []  # Distancia acumulada al objetivo
var flow_field: Array = []  # Direcciones de movimiento (Vector3 en plano XZ)

const INF = 999999
const DIRECTIONS = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                   Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1)
]

# Para visualización
var debug_mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var material: StandardMaterial3D

func _ready():
	initialize_fields()
	setup_debug_visualization()

func initialize_fields():
	"""Inicializa los campos con valores por defecto"""
	cost_field.clear()
	integration_field.clear()
	flow_field.clear()
	
	for z in range(grid_depth):
		var cost_row = []
		var integration_row = []
		var flow_row = []
		for x in range(grid_width):
			cost_row.append(1)  # Costo base
			integration_row.append(INF)
			flow_row.append(Vector3.ZERO)
		cost_field.append(cost_row)
		integration_field.append(integration_row)
		flow_field.append(flow_row)

func setup_debug_visualization():
	"""Configura la malla para debug"""
	if not debug_draw:
		return
	
	immediate_mesh = ImmediateMesh.new()
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.mesh = immediate_mesh
	
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mesh_instance.material_override = material
	
	add_child(debug_mesh_instance)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	"""Convierte coordenadas 3D del mundo a coordenadas de grid 2D (X, Z)"""
	return Vector2i(
		int(world_pos.x / cell_size),
		int(world_pos.z / cell_size)
	)

func grid_to_world(grid_pos: Vector2i, y_height: float = 0.0) -> Vector3:
	"""Convierte coordenadas de grid a coordenadas del mundo 3D"""
	return Vector3(
		grid_pos.x * cell_size + cell_size / 2.0,
		y_height,
		grid_pos.y * cell_size + cell_size / 2.0
	)

func is_valid_cell(pos: Vector2i) -> bool:
	"""Verifica si una celda está dentro de los límites del grid"""
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_depth

func set_obstacle(world_pos: Vector3, is_obstacle: bool = true):
	"""Marca una celda como obstáculo"""
	var grid_pos = world_to_grid(world_pos)
	if is_valid_cell(grid_pos):
		cost_field[grid_pos.y][grid_pos.x] = INF if is_obstacle else 1

func set_obstacle_area(world_pos: Vector3, radius: int = 1, is_obstacle: bool = true):
	"""Marca un área circular como obstáculo"""
	var center = world_to_grid(world_pos)
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + z * z <= radius * radius:
				var pos = Vector2i(center.x + x, center.y + z)
				if is_valid_cell(pos):
					cost_field[pos.y][pos.x] = INF if is_obstacle else 1

func set_cost_area(world_pos: Vector3, radius: int = 1, cost: int = 1):
	"""Establece el costo de un área (para terrenos difíciles)"""
	var center = world_to_grid(world_pos)
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + z * z <= radius * radius:
				var pos = Vector2i(center.x + x, center.y + z)
				if is_valid_cell(pos):
					cost_field[pos.y][pos.x] = cost

func detect_obstacles_from_physics(space_state: PhysicsDirectSpaceState3D, obstacle_layer: int = 1):
	"""Detecta obstáculos usando raycasts desde cada celda del grid"""
	for z in range(grid_depth):
		for x in range(grid_width):
			var world_pos = grid_to_world(Vector2i(x, z), 10.0)  # Raycast desde arriba
			
			var query = PhysicsRayQueryParameters3D.create(
				world_pos,
				world_pos + Vector3.DOWN * 20.0
			)
			query.collision_mask = obstacle_layer
			
			var result = space_state.intersect_ray(query)
			
			if result:
				# Hay un obstáculo
				cost_field[z][x] = INF
			else:
				# Celda libre (o recuperar costo según altura/material)
				cost_field[z][x] = 1

func generate_flow_field(target_world_pos: Vector3):
	"""Genera el flow field completo hacia una posición objetivo"""
	var target_grid = world_to_grid(target_world_pos)
	
	if not is_valid_cell(target_grid):
		push_warning("Target position outside grid bounds")
		return
	
	# Resetear integration field
	for z in range(grid_depth):
		for x in range(grid_width):
			integration_field[z][x] = INF
	
	# Generar Integration Field
	generate_integration_field(target_grid)
	
	# Generar Flow Field
	generate_flow_directions()
	
	# Actualizar visualización
	if debug_draw:
		update_debug_visualization()

func generate_integration_field(target: Vector2i):
	"""Genera el campo de integración usando Dijkstra"""
	var open_list: Array = []
	integration_field[target.y][target.x] = 0
	open_list.append(target)
	
	while open_list.size() > 0:
		# Encontrar nodo con menor costo
		var current = open_list[0]
		var current_idx = 0
		for i in range(1, open_list.size()):
			if integration_field[open_list[i].y][open_list[i].x] < integration_field[current.y][current.x]:
				current = open_list[i]
				current_idx = i
		
		open_list.remove_at(current_idx)
		
		# Procesar vecinos
		for direction in DIRECTIONS:
			var neighbor = current + direction
			
			if not is_valid_cell(neighbor):
				continue
			
			if cost_field[neighbor.y][neighbor.x] == INF:
				continue
			
			var new_cost = integration_field[current.y][current.x] + cost_field[neighbor.y][neighbor.x]
			
			if new_cost < integration_field[neighbor.y][neighbor.x]:
				integration_field[neighbor.y][neighbor.x] = new_cost
				if neighbor not in open_list:
					open_list.append(neighbor)

func generate_flow_directions():
	"""Genera las direcciones de flujo en el plano XZ"""
	for z in range(grid_depth):
		for x in range(grid_width):
			if cost_field[z][x] == INF:
				flow_field[z][x] = Vector3.ZERO
				continue
			
			var current_pos = Vector2i(x, z)
			var best_direction = Vector2.ZERO
			var lowest_cost = integration_field[z][x]
			
			# Buscar el vecino con menor costo
			for direction in DIRECTIONS:
				var neighbor = current_pos + direction
				
				if not is_valid_cell(neighbor):
					continue
				
				var neighbor_cost = integration_field[neighbor.y][neighbor.x]
				
				if neighbor_cost < lowest_cost:
					lowest_cost = neighbor_cost
					best_direction = Vector2(direction)
			
			# Convertir dirección 2D a Vector3 (plano XZ)
			if best_direction.length() > 0:
				flow_field[z][x] = Vector3(best_direction.x, 0, best_direction.y).normalized()
			else:
				flow_field[z][x] = Vector3.ZERO

func get_flow_direction(world_pos: Vector3) -> Vector3:
	"""Obtiene la dirección de flujo para una posición 3D"""
	var grid_pos = world_to_grid(world_pos)
	
	if not is_valid_cell(grid_pos):
		return Vector3.ZERO
	
	return flow_field[grid_pos.y][grid_pos.x]

func update_debug_visualization():
	"""Actualiza la visualización del flow field"""
	if not debug_draw or not immediate_mesh:
		return
	
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for z in range(grid_depth):
		for x in range(grid_width):
			var world_pos = grid_to_world(Vector2i(x, z), debug_arrow_height)
			
			# Dibujar obstáculos
			if cost_field[z][x] == INF:
				draw_debug_cube(world_pos, Color.RED)
			
			# Dibujar direcciones de flujo
			var direction = flow_field[z][x]
			if direction.length() > 0:
				var arrow_end = world_pos + direction * cell_size * 0.4
				
				# Línea principal
				immediate_mesh.surface_set_color(Color.GREEN)
				immediate_mesh.surface_add_vertex(world_pos)
				immediate_mesh.surface_add_vertex(arrow_end)
				
				# Punta de flecha
				var right = direction.cross(Vector3.UP).normalized() * 0.2
				var back = -direction * 0.3
				
				immediate_mesh.surface_add_vertex(arrow_end)
				immediate_mesh.surface_add_vertex(arrow_end + back + right)
				
				immediate_mesh.surface_add_vertex(arrow_end)
				immediate_mesh.surface_add_vertex(arrow_end + back - right)
	
	immediate_mesh.surface_end()

func draw_debug_cube(center: Vector3, color: Color):
	"""Dibuja un cubo para visualizar obstáculos"""
	var half_size = cell_size * 0.4
	
	immediate_mesh.surface_set_color(color)
	
	# Líneas del cubo (simplificado)
	var corners = [
		center + Vector3(-half_size, -half_size, -half_size),
		center + Vector3(half_size, -half_size, -half_size),
		center + Vector3(half_size, -half_size, half_size),
		center + Vector3(-half_size, -half_size, half_size),
	]
	
	for i in range(4):
		immediate_mesh.surface_add_vertex(corners[i])
		immediate_mesh.surface_add_vertex(corners[(i + 1) % 4])

func clear_debug():
	"""Limpia la visualización de debug"""
	if immediate_mesh:
		immediate_mesh.clear_surfaces()
