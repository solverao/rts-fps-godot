extends Node3D
class_name FlowField3D

# ============================================================
# 🧭 SISTEMA DE FLOW FIELD 3D PARA RTS
# ------------------------------------------------------------
# Este nodo genera un campo vectorial de navegación (flow field)
# que dirige múltiples unidades hacia un objetivo común,
# considerando obstáculos y costos de terreno.
# ============================================================

# -------------------------
# 🧱 CONFIGURACIÓN DEL GRID
# -------------------------
@export var cell_size: float = 2.0        # Tamaño físico de cada celda en el mundo
@export var grid_width: int = 50          # Número de celdas en el eje X
@export var grid_depth: int = 50          # Número de celdas en el eje Z
@export var debug_draw: bool = true       # Si true, dibuja el campo de flujo
@export var debug_arrow_height: float = 0.5  # Altura de las flechas de depuración

# -------------------------
# 🧮 CAMPOS DE DATOS
# -------------------------
var cost_field: Array = []         # Costo de movimiento por celda (1 = libre, INF = obstáculo)
var integration_field: Array = []  # Distancia acumulada desde el objetivo
var flow_field: Array = []         # Direcciones de movimiento (Vector3 normalizado en plano XZ)

const INF = 999999
const DIRECTIONS = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                    Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),   Vector2i(1, 1)
]

# -------------------------
# 🎨 VISUALIZACIÓN DEBUG
# -------------------------
var debug_mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var material: StandardMaterial3D

# ============================================================
# 🔧 INICIALIZACIÓN
# ============================================================

func _ready():
	initialize_fields()
	setup_debug_visualization()

# ------------------------------------------------------------
# Inicializa las matrices del campo de costos, integración y flujo.
# ------------------------------------------------------------
func initialize_fields():
	cost_field.clear()
	integration_field.clear()
	flow_field.clear()

	for z in range(grid_depth):
		var cost_row = []
		var integration_row = []
		var flow_row = []
		for x in range(grid_width):
			cost_row.append(1)          # Costo base
			integration_row.append(INF) # Sin calcular aún
			flow_row.append(Vector3.ZERO)
		cost_field.append(cost_row)
		integration_field.append(integration_row)
		flow_field.append(flow_row)

# ------------------------------------------------------------
# Crea la malla usada para la visualización de depuración.
# ------------------------------------------------------------
func setup_debug_visualization():
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

# ============================================================
# 🧭 CONVERSIÓN ENTRE COORDENADAS
# ============================================================

func world_to_grid(world_pos: Vector3) -> Vector2i:
	"""Convierte una posición del mundo a coordenadas del grid."""
	return Vector2i(
		int(world_pos.x / cell_size),
		int(world_pos.z / cell_size)
	)

func grid_to_world(grid_pos: Vector2i, y_height: float = 0.0) -> Vector3:
	"""Convierte una coordenada del grid a posición mundial."""
	return Vector3(
		grid_pos.x * cell_size + cell_size / 2.0,
		y_height,
		grid_pos.y * cell_size + cell_size / 2.0
	)

func is_valid_cell(pos: Vector2i) -> bool:
	"""Devuelve true si la celda está dentro del grid."""
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_depth

# ============================================================
# 🚧 MANEJO DE OBSTÁCULOS Y TERRENOS
# ============================================================

func set_obstacle(world_pos: Vector3, is_obstacle: bool = true):
	"""Marca una celda individual como obstáculo o libre."""
	var grid_pos = world_to_grid(world_pos)
	if is_valid_cell(grid_pos):
		cost_field[grid_pos.y][grid_pos.x] = INF if is_obstacle else 1

func set_obstacle_area(world_pos: Vector3, radius: int = 1, is_obstacle: bool = true):
	"""Marca un área circular como obstáculo (por ejemplo, una roca o edificio)."""
	var center = world_to_grid(world_pos)
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + z * z <= radius * radius:
				var pos = Vector2i(center.x + x, center.y + z)
				if is_valid_cell(pos):
					cost_field[pos.y][pos.x] = INF if is_obstacle else 1

func set_cost_area(world_pos: Vector3, radius: int = 1, cost: int = 1):
	"""Aumenta el costo de un área (simula terreno difícil)."""
	var center = world_to_grid(world_pos)
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + z * z <= radius * radius:
				var pos = Vector2i(center.x + x, center.y + z)
				if is_valid_cell(pos):
					cost_field[pos.y][pos.x] = cost

# ============================================================
# 🧠 GENERACIÓN DEL FLOW FIELD
# ============================================================

func generate_flow_field(target_world_pos: Vector3):
	"""Genera el campo de flujo completo hacia el punto objetivo."""
	var target_grid = world_to_grid(target_world_pos)
	if not is_valid_cell(target_grid):
		push_warning("⚠️ Target fuera de los límites del grid.")
		return
	
	# Reset de integración
	for z in range(grid_depth):
		for x in range(grid_width):
			integration_field[z][x] = INF
	
	generate_integration_field(target_grid)
	generate_flow_directions()

	if debug_draw:
		update_debug_visualization()

# ------------------------------------------------------------
# Usa Dijkstra para propagar costos desde el objetivo.
# ------------------------------------------------------------
func generate_integration_field(target: Vector2i):
	var open_list: Array[Vector2i] = [target]
	integration_field[target.y][target.x] = 0

	while open_list.size() > 0:
		# Sacar el primer elemento (FIFO)
		var current = open_list.pop_front()

		for dir in DIRECTIONS:
			var neighbor = current + dir
			if not is_valid_cell(neighbor):
				continue

			if cost_field[neighbor.y][neighbor.x] == INF:
				continue

			var new_cost = integration_field[current.y][current.x] + cost_field[neighbor.y][neighbor.x]

			if new_cost < integration_field[neighbor.y][neighbor.x]:
				integration_field[neighbor.y][neighbor.x] = new_cost
				open_list.append(neighbor)

# ------------------------------------------------------------
# Calcula direcciones de flujo hacia el menor costo vecino.
# ------------------------------------------------------------
func generate_flow_directions():
	for z in range(grid_depth):
		for x in range(grid_width):
			if cost_field[z][x] == INF:
				flow_field[z][x] = Vector3.ZERO
				continue
			
			var current = Vector2i(x, z)
			var best_dir = Vector2.ZERO
			var lowest = integration_field[z][x]

			for dir in DIRECTIONS:
				var neighbor = current + dir
				if not is_valid_cell(neighbor):
					continue
				var neighbor_cost = integration_field[neighbor.y][neighbor.x]
				if neighbor_cost < lowest:
					lowest = neighbor_cost
					best_dir = Vector2(dir)
			
			if best_dir.length() > 0:
				flow_field[z][x] = Vector3(best_dir.x, 0, best_dir.y).normalized()
			else:
				flow_field[z][x] = Vector3.ZERO

# ------------------------------------------------------------
# Devuelve la dirección de flujo para una posición del mundo.
# ------------------------------------------------------------
func get_flow_direction(world_pos: Vector3) -> Vector3:
	var grid_pos = world_to_grid(world_pos)
	if not is_valid_cell(grid_pos):
		return Vector3.ZERO
	return flow_field[grid_pos.y][grid_pos.x]

# ============================================================
# 🎨 DEPURACIÓN VISUAL
# ============================================================

func update_debug_visualization():
	if not debug_draw or not immediate_mesh:
		return
	
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for z in range(grid_depth):
		for x in range(grid_width):
			var world_pos = grid_to_world(Vector2i(x, z), debug_arrow_height)

			# Obstáculos en rojo
			if cost_field[z][x] == INF:
				draw_debug_cube(world_pos, Color.RED)

			# Direcciones del flow field
			var dir = flow_field[z][x]
			if dir.length() > 0:
				var arrow_end = world_pos + dir * cell_size * 0.4
				immediate_mesh.surface_set_color(Color.GREEN)
				immediate_mesh.surface_add_vertex(world_pos)
				immediate_mesh.surface_add_vertex(arrow_end)

				# Punta de flecha
				var right = dir.cross(Vector3.UP).normalized() * 0.2
				var back = -dir * 0.3
				immediate_mesh.surface_add_vertex(arrow_end)
				immediate_mesh.surface_add_vertex(arrow_end + back + right)
				immediate_mesh.surface_add_vertex(arrow_end)
				immediate_mesh.surface_add_vertex(arrow_end + back - right)
	
	immediate_mesh.surface_end()

func draw_debug_cube(center: Vector3, color: Color):
	var half = cell_size * 0.4
	immediate_mesh.surface_set_color(color)
	var corners = [
		center + Vector3(-half, 0, -half),
		center + Vector3(half, 0, -half),
		center + Vector3(half, 0, half),
		center + Vector3(-half, 0, half)
	]
	for i in range(4):
		immediate_mesh.surface_add_vertex(corners[i])
		immediate_mesh.surface_add_vertex(corners[(i + 1) % 4])

func clear_debug():
	if immediate_mesh:
		immediate_mesh.clear_surfaces()
