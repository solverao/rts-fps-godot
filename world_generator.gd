extends Node3D
class_name TerrainChunkSystem

# --- Configuración de Chunks ---
@export_group("Chunk Settings")
@export var chunk_size: int = 32  # Tamaño de cada chunk (vértices)
@export var render_distance: int = 4  # Cuántos chunks cargar alrededor del jugador
@export var chunk_scale: float = 2.0  # Separación entre vértices
@export var chunks_per_frame: int = 2  # Chunks a generar por frame
@export var update_interval: float = 0.5  # Segundos entre actualizaciones

@export_group("Terrain Settings")
@export var height_multiplier: float = 15.0
@export var noise_frequency: float = 0.05
@export var noise_seed: int = -1  # -1 = aleatorio
@export var octaves: int = 4
@export var lacunarity: float = 2.0
@export var gain: float = 0.5

@export_group("Biome Settings")
@export var enable_biomes: bool = false
@export var biome_scale: float = 0.001  # Escala del ruido de biomas (más bajo = biomas más grandes)
@export var biome_blend_distance: float = 10.0  # Distancia de transición entre biomas

@export_group("Visual Settings")
@export var terrain_color: Color = Color(0.45, 0.38, 0.28)
@export var roughness: float = 0.95
@export var enable_shadows: bool = true
@export var use_frustum_culling: bool = true

@export_group("Collision Settings")
@export var enable_collision: bool = true
@export var collision_layer: int = 1  # Capa de colisión (por defecto layer 1)
@export var collision_mask: int = 1  # Máscara de colisión

@export_group("Player Reference")
@export var player: Node3D  # Arrastra aquí tu jugador o cámara

# Almacenamiento de chunks
var loaded_chunks: Dictionary = {}  # {Vector2i: ChunkData}
var noise: FastNoiseLite = FastNoiseLite.new()
var biome_noise: FastNoiseLite = FastNoiseLite.new()  # Ruido para controlar biomas

# Definición de biomas
var biomes: Array[BiomeData] = []

# Para generación asíncrona optimizada
var chunk_queue: Array[Vector2i] = []
var chunks_to_unload: Array[Vector2i] = []
var last_player_chunk: Vector2i = Vector2i.MAX
var update_timer: float = 0.0

# Material compartido (optimización)
var shared_material: StandardMaterial3D

# Clase interna para definir biomas
class BiomeData:
	var name: String
	var height_multiplier: float
	var octaves: int
	var frequency: float
	var min_threshold: float  # Valor mínimo del ruido de bioma
	var max_threshold: float  # Valor máximo del ruido de bioma
	var color: Color
	
	func _init(p_name: String, p_height: float, p_octaves: int, p_freq: float, p_min: float, p_max: float, p_color: Color = Color.WHITE):
		name = p_name
		height_multiplier = p_height
		octaves = p_octaves
		frequency = p_freq
		min_threshold = p_min
		max_threshold = p_max
		color = p_color
	
	func matches(biome_value: float) -> bool:
		return biome_value >= min_threshold and biome_value < max_threshold

# Clase interna para datos del chunk
class ChunkData:
	var mesh_instance: MeshInstance3D
	var collision_shape: CollisionShape3D
	var static_body: StaticBody3D
	var position: Vector2i
	var last_visible: float = 0.0
	var dominant_biome: String = ""  # Para debugging
	
	func _init(p_mesh: MeshInstance3D, p_pos: Vector2i):
		mesh_instance = p_mesh
		position = p_pos
		last_visible = Time.get_ticks_msec() / 1000.0

func _ready():
	setup_noise()
	setup_biomes()
	setup_material()
	
	# Si no hay jugador asignado, usar la posición actual
	if player == null:
		player = self
		push_warning("TerrainChunkSystem: No se asignó jugador, usando posición del nodo")
	
	# Generar chunks iniciales
	update_chunks_immediate()

func _process(delta):
	update_timer += delta
	
	# Actualizar chunks solo después del intervalo
	if player and update_timer >= update_interval:
		update_timer = 0.0
		var current_chunk = world_to_chunk(player.global_position)
		
		# Solo actualizar si el jugador cambió de chunk
		if current_chunk != last_player_chunk:
			last_player_chunk = current_chunk
			update_chunks()
	
	# Generar chunks en cola (distribuido en frames)
	generate_queued_chunks()

func setup_noise():
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = noise_seed if noise_seed >= 0 else randi()
	noise.frequency = noise_frequency
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = gain
	
	# Configurar ruido de biomas
	biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	biome_noise.seed = noise.seed + 1000  # Diferente pero determinista
	biome_noise.frequency = biome_scale
	biome_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN

func setup_biomes():
	"""Configura los biomas predefinidos"""
	biomes.clear()
	
# Bioma 1: Llanuras (Rango: 0.6 de ancho)
	biomes.append(BiomeData.new(
		"Llanuras",
		2.0,      # Altura
		1,        # Octavas
		0.1,      # Frecuencia
		-1.0,     # min_threshold
		-0.4,     # max_threshold (ANTES ERA -0.2)
		Color(0.4, 0.7, 0.3)
	))
	
	# Bioma 2: Colinas (Rango: 0.7 de ancho)
	biomes.append(BiomeData.new(
		"Colinas",
		12.0,     # Altura
		3,        # Octavas
		0.04,     # Frecuencia
		-0.4,     # min_threshold (ANTES ERA -0.2)
		0.3,      # max_threshold (ANTES ERA 0.4)
		Color(0.35, 0.5, 0.25)
	))
	
	# Bioma 3: Montañas (Rango: 0.7 de ancho)
	biomes.append(BiomeData.new(
		"Montañas",
		35.0,     # Altura
		6,        # Octavas
		0.02,     # Frecuencia
		0.3,      # min_threshold (ANTES ERA 0.4)
		1.0,      # max_threshold
		Color(0.5, 0.4, 0.35)
	))

func setup_material():
	shared_material = StandardMaterial3D.new()
	shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	shared_material.roughness = roughness
	shared_material.metallic = 0.0
	shared_material.cull_mode = BaseMaterial3D.CULL_BACK
	
	# Habilitar vertex colors si los biomas están activos
	if enable_biomes:
		shared_material.vertex_color_use_as_albedo = true
		shared_material.albedo_color = Color.WHITE  # Blanco para que los vertex colors se vean
	else:
		shared_material.albedo_color = terrain_color
		shared_material.vertex_color_use_as_albedo = false

func update_chunks():
	if player == null:
		return
	
	var player_chunk = world_to_chunk(player.global_position)
	
	# Limpiar listas
	chunk_queue.clear()
	chunks_to_unload.clear()
	
	# Determinar qué chunks deben estar cargados
	var chunks_needed: Dictionary = {}
	var chunks_to_load: Array[Vector2i] = []
	
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var chunk_pos = player_chunk + Vector2i(x, z)
			chunks_needed[chunk_pos] = true
			
			# Si el chunk no existe, agregarlo a la lista
			if not loaded_chunks.has(chunk_pos):
				chunks_to_load.append(chunk_pos)
	
	# Ordenar chunks por distancia (cargar los más cercanos primero)
	chunks_to_load.sort_custom(func(a, b): 
		return player_chunk.distance_squared_to(a) < player_chunk.distance_squared_to(b)
	)
	chunk_queue = chunks_to_load
	
	# Determinar qué chunks descargar
	for chunk_pos in loaded_chunks.keys():
		if not chunks_needed.has(chunk_pos):
			chunks_to_unload.append(chunk_pos)
	
	# Descargar chunks lejanos
	for chunk_pos in chunks_to_unload:
		unload_chunk(chunk_pos)

func update_chunks_immediate():
	"""Versión inmediata para carga inicial"""
	if player == null:
		return
	
	var player_chunk = world_to_chunk(player.global_position)
	last_player_chunk = player_chunk
	
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var chunk_pos = player_chunk + Vector2i(x, z)
			if not loaded_chunks.has(chunk_pos):
				generate_chunk(chunk_pos)

func generate_queued_chunks():
	"""Genera chunks de la cola, limitado por chunks_per_frame"""
	var count = 0
	while count < chunks_per_frame and not chunk_queue.is_empty():
		var chunk_pos = chunk_queue.pop_front()
		if not loaded_chunks.has(chunk_pos):
			generate_chunk(chunk_pos)
		count += 1

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	var chunk_world_size = chunk_size * chunk_scale
	return Vector2i(
		int(floor(world_pos.x / chunk_world_size)),
		int(floor(world_pos.z / chunk_world_size))
	)

func chunk_to_world(chunk_pos: Vector2i) -> Vector3:
	var chunk_world_size = chunk_size * chunk_scale
	return Vector3(
		chunk_pos.x * chunk_world_size,
		0,
		chunk_pos.y * chunk_world_size
	)

func generate_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return
	
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	# Posicionar el chunk en el mundo
	mesh_instance.position = chunk_to_world(chunk_pos)
	
	# Generar la geometría del chunk
	var mesh = create_chunk_mesh(chunk_pos)
	mesh_instance.mesh = mesh
	
	# Aplicar material compartido
	mesh_instance.set_surface_override_material(0, shared_material)
	
	# Configurar sombras
	if enable_shadows:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Optimización: frustum culling
	if use_frustum_culling:
		mesh_instance.visibility_range_end_margin = chunk_size * chunk_scale
	
	# Crear colisión si está habilitada
	var static_body: StaticBody3D = null
	var collision_shape: CollisionShape3D = null
	
	if enable_collision:
		static_body = StaticBody3D.new()
		mesh_instance.add_child(static_body)
		
		# Configurar capas de colisión
		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		
		collision_shape = CollisionShape3D.new()
		static_body.add_child(collision_shape)
		
		# Crear shape de colisión desde el mesh
		var collision_mesh = mesh.create_trimesh_shape()
		collision_shape.shape = collision_mesh
	
	# Guardar el chunk
	var chunk_data = ChunkData.new(mesh_instance, chunk_pos)
	chunk_data.static_body = static_body
	chunk_data.collision_shape = collision_shape
	loaded_chunks[chunk_pos] = chunk_data

func create_chunk_mesh(chunk_pos: Vector2i) -> ArrayMesh:
	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var colors: PackedColorArray = []  # Para visualizar biomas
	var indices: PackedInt32Array = []
	
	# Offset global del chunk para el ruido
	var offset_x = chunk_pos.x * chunk_size
	var offset_z = chunk_pos.y * chunk_size
	
	# Pre-calcular tamaño para optimización
	var verts_per_side = chunk_size + 1
	var uv_scale = 1.0 / float(chunk_size)
	
	# Generar vértices (con 1 vértice extra para conectar con chunks vecinos)
	for x in range(verts_per_side):
		for z in range(verts_per_side):
			# Posición global para el ruido
			var world_x = offset_x + x
			var world_z = offset_z + z
			
			var y: float
			var vertex_color: Color = terrain_color
			
			if enable_biomes:
				# Obtener altura basada en biomas
				var height_data = get_biome_height(float(world_x), float(world_z))
				y = height_data.height
				vertex_color = height_data.color
			else:
				# Altura normal sin biomas
				var noise_value = noise.get_noise_2d(float(world_x), float(world_z))
				y = noise_value * height_multiplier
			
			# Posición local del vértice dentro del chunk
			var position = Vector3(float(x) * chunk_scale, y, float(z) * chunk_scale)
			vertices.append(position)
			colors.append(vertex_color)
			
			# UVs optimizados
			uvs.append(Vector2(float(x) * uv_scale, float(z) * uv_scale))
	
	# Generar índices de manera más eficiente
	for x in range(chunk_size):
		for z in range(chunk_size):
			var v0 = x * verts_per_side + z
			var v1 = (x + 1) * verts_per_side + z
			var v2 = x * verts_per_side + (z + 1)
			var v3 = (x + 1) * verts_per_side + (z + 1)
			
			# Primer triángulo
			indices.append(v0)
			indices.append(v1)
			indices.append(v2)
			
			# Segundo triángulo
			indices.append(v1)
			indices.append(v3)
			indices.append(v2)
	
	# Crear la malla
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors  # Agregar colores de vértice
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Generar normales y tangentes
	var st = SurfaceTool.new()
	st.create_from(array_mesh, 0)
	st.generate_normals()
	st.generate_tangents()
	
	return st.commit()

func unload_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		var chunk_data: ChunkData = loaded_chunks[chunk_pos]
		
		# Liberar colisión si existe
		if chunk_data.collision_shape:
			chunk_data.collision_shape.queue_free()
		if chunk_data.static_body:
			chunk_data.static_body.queue_free()
		
		# Liberar mesh
		chunk_data.mesh_instance.queue_free()
		loaded_chunks.erase(chunk_pos)

# --- Funciones de utilidad ---

func get_chunk_count() -> int:
	return loaded_chunks.size()

func get_height_at_position(world_pos: Vector3) -> float:
	"""Obtiene la altura del terreno en una posición del mundo"""
	if enable_biomes:
		var height_data = get_biome_height(world_pos.x / chunk_scale, world_pos.z / chunk_scale)
		return height_data.height
	else:
		var noise_value = noise.get_noise_2d(world_pos.x / chunk_scale, world_pos.z / chunk_scale)
		return noise_value * height_multiplier

func get_biome_height(world_x: float, world_z: float) -> Dictionary:
	"""Calcula la altura y color basándose en biomas con transiciones suaves"""
	# Usar coordenadas directas para el ruido de biomas
	var biome_value = biome_noise.get_noise_2d(world_x, world_z)
	
	# Encontrar biomas adyacentes para hacer blend
	var blend_weights: Array = []
	var total_weight: float = 0.0
	
	for biome in biomes:
		if biome.matches(biome_value):
			# Calcular peso basado en distancia al centro del rango del bioma
			var biome_center = (biome.min_threshold + biome.max_threshold) / 2.0
			var distance_to_center = abs(biome_value - biome_center)
			var biome_range = (biome.max_threshold - biome.min_threshold) / 2.0
			
			# Peso más alto cerca del centro del bioma
			var weight = 1.0 - clamp(distance_to_center / biome_range, 0.0, 1.0)
			blend_weights.append({"biome": biome, "weight": weight})
			total_weight += weight
	
	# Si no encontramos bioma, usar valores por defecto
	if blend_weights.is_empty():
		var noise_value = noise.get_noise_2d(world_x, world_z)
		return {"height": noise_value * height_multiplier, "color": terrain_color}
	
	# Normalizar pesos
	for data in blend_weights:
		data.weight /= total_weight
	
	# Calcular altura final mezclando biomas
	var final_height: float = 0.0
	var final_color: Color = Color.BLACK
	
	for data in blend_weights:
		var biome: BiomeData = data.biome
		var weight: float = data.weight
		
		# Configurar noise temporalmente con parámetros del bioma
		var original_octaves = noise.fractal_octaves
		var original_frequency = noise.frequency
		
		noise.fractal_octaves = biome.octaves
		noise.frequency = biome.frequency
		
		var noise_value = noise.get_noise_2d(world_x, world_z)
		var biome_height = noise_value * biome.height_multiplier
		
		# Restaurar valores originales
		noise.fractal_octaves = original_octaves
		noise.frequency = original_frequency
		
		# Acumular con peso
		final_height += biome_height * weight
		final_color += biome.color * weight
	
	return {"height": final_height, "color": final_color}

func is_chunk_loaded(chunk_pos: Vector2i) -> bool:
	return loaded_chunks.has(chunk_pos)

func regenerate_all_chunks():
	"""Fuerza regeneración de todos los chunks (útil si cambias parámetros)"""
	var chunks_to_regen = loaded_chunks.keys()
	for chunk_pos in chunks_to_regen:
		unload_chunk(chunk_pos)
	setup_noise()
	setup_biomes()
	setup_material()  # Recrear material con nuevos parámetros
	update_chunks_immediate()

func clear_all_chunks():
	"""Limpia todos los chunks cargados"""
	for chunk_pos in loaded_chunks.keys():
		unload_chunk(chunk_pos)
	chunk_queue.clear()
	chunks_to_unload.clear()

func set_noise_seed(new_seed: int):
	"""Cambia la semilla del ruido y regenera el terreno"""
	noise_seed = new_seed
	setup_noise()
	setup_biomes()
	regenerate_all_chunks()

func add_custom_biome(name: String, height: float, octaves_count: int, freq: float, min_thresh: float, max_thresh: float, color: Color = Color.WHITE):
	"""Agrega un bioma personalizado"""
	biomes.append(BiomeData.new(name, height, octaves_count, freq, min_thresh, max_thresh, color))
	if enable_biomes:
		regenerate_all_chunks()

func clear_biomes():
	"""Limpia todos los biomas y vuelve a los predeterminados"""
	biomes.clear()
	setup_biomes()
	if enable_biomes:
		regenerate_all_chunks()

func get_biome_at_position(world_pos: Vector3) -> String:
	"""Retorna el nombre del bioma en una posición"""
	if not enable_biomes or biomes.is_empty():
		return "Sin bioma"
	
	var biome_value = biome_noise.get_noise_2d(world_pos.x / chunk_scale, world_pos.z / chunk_scale)
	
	for biome in biomes:
		if biome.matches(biome_value):
			return biome.name
	
	return "Desconocido"

func get_biome_value_at_position(world_pos: Vector3) -> float:
	"""Retorna el valor del ruido de bioma (para debug)"""
	return biome_noise.get_noise_2d(world_pos.x / chunk_scale, world_pos.z / chunk_scale)

func print_biome_info():
	"""Imprime información de debug sobre los biomas"""
	print("=== BIOMAS CONFIGURADOS ===")
	print("Biome scale: ", biome_scale)
	print("Seed: ", biome_noise.seed)
	for i in range(biomes.size()):
		var b = biomes[i]
		print("%d. %s: altura=%.1f, octavas=%d, rango=[%.2f, %.2f]" % [i+1, b.name, b.height_multiplier, b.octaves, b.min_threshold, b.max_threshold])

func toggle_collision(enabled: bool):
	"""Activa o desactiva colisiones en todos los chunks cargados"""
	enable_collision = enabled
	
	for chunk_pos in loaded_chunks.keys():
		var chunk_data: ChunkData = loaded_chunks[chunk_pos]
		
		if chunk_data.static_body:
			chunk_data.static_body.set_collision_layer_value(1, enabled)

func set_collision_layers(layer: int, mask: int):
	"""Cambia las capas de colisión y aplica a todos los chunks"""
	collision_layer = layer
	collision_mask = mask
	
	for chunk_pos in loaded_chunks.keys():
		var chunk_data: ChunkData = loaded_chunks[chunk_pos]
		
		if chunk_data.static_body:
			chunk_data.static_body.collision_layer = layer
			chunk_data.static_body.collision_mask = mask

# Debug
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if player == null:
		warnings.append("No se ha asignado un nodo Player. El terreno usará su propia posición.")
	
	if chunk_size < 8:
		warnings.append("chunk_size muy pequeño puede causar problemas de rendimiento.")
	
	if render_distance > 8:
		warnings.append("render_distance alto puede afectar el rendimiento.")
	
	if enable_collision and chunk_size > 64:
		warnings.append("chunk_size grande con colisiones puede afectar el rendimiento. Considera reducirlo.")
	
	if enable_biomes and biomes.is_empty():
		warnings.append("Biomas activados pero no hay biomas definidos. Se crearán biomas por defecto.")
	
	return warnings
