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
@export var biome_blend_distance: float = 0.15  # Distancia de transición entre biomas

@export_group("Visual Settings")
@export_group("Visual Settings")
@export var shader_resource: Shader
@export var tex_grass: Texture2D
@export var tex_rock: Texture2D
@export var tex_sand: Texture2D

@export var uv_scale: float = 10.0:
	set(value):
		uv_scale = value
		_update_shader_param("uv_scale", value)
		
@export var slope_sharpness: float = 12.0:
	set(value):
		slope_sharpness = value
		_update_shader_param("slope_sharpness", value)

@export var sand_height: float = 2.5:
	set(value):
		sand_height = value
		_update_shader_param("sand_height", value)
		
@export var sand_blend_range: float = 3.0:
	set(value):
		sand_blend_range = value
		_update_shader_param("sand_blend_range", value)

@export var terrain_color: Color = Color(0.45, 0.38, 0.28):
	set(value):
		terrain_color = value
		_update_shader_param("terrain_color", value)

@export var roughness: float = 0.95:
	set(value):
		roughness = value
		_update_shader_param("roughness", value)
		
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
var shared_material: ShaderMaterial

# Clase interna para definir biomas
class BiomeData:
	var name: String
	var height_multiplier: float
	var min_core: float
	var max_core: float
	var blend_range: float
	var color: Color
	var noise: FastNoiseLite # <-- AÑADIR ESTO

	func _init(p_name: String, p_height: float, p_octaves: int, p_freq: float, p_min_core: float, p_max_core: float, p_blend: float, p_color: Color = Color.WHITE):
		name = p_name
		height_multiplier = p_height
		min_core = p_min_core
		max_core = p_max_core
		blend_range = p_blend
		color = p_color
		
		# Crear y configurar su PROPIO objeto de ruido
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_PERLIN
		noise.seed = randi() # O puedes pasarlo como parámetro
		noise.fractal_octaves = p_octaves
		noise.frequency = p_freq
		# Puedes copiar más parámetros del 'noise' global si lo deseas

	# NUEVA FUNCIÓN para calcular el peso (de 0.0 a 1.0)
	func get_weight(biome_value: float) -> float:
		# 1. Calcular los límites totales del bioma (núcleo + difuminado)
		# Nota: nos aseguramos de no pasarnos de -1.0 o 1.0
		var min_total = max(min_core - blend_range, -1.0)
		var max_total = min(max_core + blend_range, 1.0)

		# 2. Si está fuera del rango total, el peso es 0
		if biome_value < min_total or biome_value > max_total:
			return 0.0

		# 3. Si está dentro del núcleo, el peso es 1
		if biome_value >= min_core and biome_value <= max_core:
			return 1.0
			
		# 4. Si está en la zona de difuminado de entrada (izquierda)
		if biome_value < min_core:
			# smoothstep(edge0, edge1, x) -> Interpola suavemente de 0 a 1 cuando x va de edge0 a edge1
			return smoothstep(min_total, min_core, biome_value)
			
		# 5. Si está en la zona de difuminado de salida (derecha)
		if biome_value > max_core:
			# Invertimos la lógica: va de 1 (en max_core) a 0 (en max_total)
			return 1.0 - smoothstep(max_core, max_total, biome_value)
			
		return 0.0 # No debería llegar aquí

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
	"""Configura los biomas predefinidos CON TRANSICIONES SUAVES"""
	biomes.clear()
	
	# Este es el valor clave: cuánto se difumina cada bioma (en espacio de ruido)
	# Un valor más alto = transiciones más largas y suaves.
	# ¡Tu variable @export biome_blend_distance = 10.0 NO sirve aquí!
	# Te sugiero borrar esa variable y usar este valor, o cambiar
	# el valor por defecto de tu @export a 0.15.
	var blend_amount: float = biome_blend_distance

	# Bioma 1: Llanuras
	# Núcleo: [-1.0, -0.4]
	# Total (con blend): [-1.0, -0.25]
	biomes.append(BiomeData.new(
		"Llanuras", 2.0, 1, 0.1,
		-1.0,	 # min_core
		-0.4,	 # max_core
		blend_amount,
		Color(0.4, 0.7, 0.3)
	))
	
	# Bioma 2: Colinas
	# Núcleo: [-0.3, 0.3]
	# Total (con blend): [-0.45, 0.45]
	biomes.append(BiomeData.new(
		"Colinas", 12.0, 3, 0.04,
		-0.3,	 # min_core
		0.3,	 # max_core
		blend_amount,
		Color(0.35, 0.5, 0.25)
	))
	
	# Bioma 3: Montañas
	# Núcleo: [0.4, 1.0]
	# Total (con blend): [0.25, 1.0]
	biomes.append(BiomeData.new(
		"Montañas", 65.0, 6, 0.02,
		0.4,	 # min_core
		1.0,	 # max_core
		blend_amount,
		Color(0.5, 0.4, 0.35)
	))
	
	# NOTA DE CÓMO FUNCIONA:
	# Llanuras (total) = [-1.0, -0.25]
	# Colinas (total)  = [-0.45, 0.45]
	# Montañas (total) = [0.25, 1.0]
	#
	# Hay solapamiento entre [-0.45, -0.25] (Llanuras y Colinas se mezclan)
	# y entre [0.25, 0.45] (Colinas y Montañas se mezclan)
	
func setup_material():
	# 1. Validar el shader
	if shader_resource == null:
		push_error("No se asignó 'shader_resource' en el Inspector.")
		return
		
	# 2. Crear el ShaderMaterial
	shared_material = ShaderMaterial.new()
	shared_material.shader = shader_resource
	
	# 3. Asignar texturas (con validación)
	if tex_grass:
		shared_material.set_shader_parameter("tex_grass", tex_grass)
	else:
		push_warning("Falta la textura 'tex_grass'.")

	if tex_rock:
		shared_material.set_shader_parameter("tex_rock", tex_rock)
	else:
		push_warning("Falta la textura 'tex_rock'.")
		
	if tex_sand:
		shared_material.set_shader_parameter("tex_sand", tex_sand)
	else:
		push_warning("Falta la textura 'tex_sand'.")
	
	# 4. Asignar TODOS los parámetros iniciales desde tus variables @export
	# Los 'setters' no se llaman al inicio, así que los establecemos manualmente.
	shared_material.set_shader_parameter("uv_scale", uv_scale)
	shared_material.set_shader_parameter("slope_sharpness", slope_sharpness)
	shared_material.set_shader_parameter("sand_height", sand_height)
	shared_material.set_shader_parameter("sand_blend_range", sand_blend_range)
	shared_material.set_shader_parameter("terrain_color", terrain_color)
	shared_material.set_shader_parameter("roughness", roughness)
	
	# NOTA: Asegúrate de que tu shader TENGA uniforms llamados:
	# "terrain_color" y "roughness" para que esto funcione.
	
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
	mesh_instance.position = chunk_to_world(chunk_pos)
	
	# 1. Obtener los datos generados
	var mesh_data: Dictionary = create_chunk_mesh(chunk_pos)
	var mesh: ArrayMesh = mesh_data["mesh"]
	var height_map: PackedFloat32Array = mesh_data["heights"]
	
	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, shared_material)
	
	# ... (tu código de sombras y culling no cambia) ...
	
	var static_body: StaticBody3D = null
	var collision_shape: CollisionShape3D = null
	
	if enable_collision:
		static_body = StaticBody3D.new()
		mesh_instance.add_child(static_body)
		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		
		collision_shape = CollisionShape3D.new()
		static_body.add_child(collision_shape)
		
		# 2. ¡LA MAGIA! Crear el HeightMapShape3D (súper rápido)
		var height_shape = HeightMapShape3D.new()
		height_shape.map_width = chunk_size + 1
		height_shape.map_depth = chunk_size + 1
		height_shape.map_data = height_map
		
		# 3. Ajustar el tamaño y posición del shape
		# El HeightMapShape3D se escala desde su centro
		var terrain_size = float(chunk_size) * chunk_scale
		collision_shape.shape = height_shape
		
		# Escalar el shape para que coincida con el mesh
		collision_shape.scale = Vector3(chunk_scale, 1.0, chunk_scale)
		
		# Centrar el shape en el mesh
		# (El mesh va de 0 a terrain_size, el shape centrado va de -terrain_size/2 a +terrain_size/2)
		collision_shape.position = Vector3(terrain_size / 2.0, 0, terrain_size / 2.0)

	# ... (tu código para guardar el chunk_data no cambia) ...
	var chunk_data = ChunkData.new(mesh_instance, chunk_pos)
	chunk_data.static_body = static_body
	chunk_data.collision_shape = collision_shape
	loaded_chunks[chunk_pos] = chunk_data
	
func create_chunk_mesh(chunk_pos: Vector2i) -> Dictionary: # ¡Ahora devuelve un Diccionario!
	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var colors: PackedColorArray = []
	var indices: PackedInt32Array = []
	
	var verts_per_side = chunk_size + 1
	
	# Array para el HeightMapShape3D
	var height_map_data: PackedFloat32Array = []
	height_map_data.resize(verts_per_side * verts_per_side)
	
	var offset_x = chunk_pos.x * chunk_size
	var offset_z = chunk_pos.y * chunk_size
	var uv_scale = 1.0 / float(chunk_size)
	
	var idx = 0 # Índice para el height_map_data
	for x in range(verts_per_side):
		for z in range(verts_per_side):
			var world_x = offset_x + x
			var world_z = offset_z + z
			
			var y: float
			var vertex_color: Color = terrain_color
			
			if enable_biomes:
				var height_data = get_biome_height(float(world_x), float(world_z))
				y = height_data.height
				vertex_color = height_data.color
			else:
				var noise_value = noise.get_noise_2d(float(world_x), float(world_z))
				y = noise_value * height_multiplier
			
			# Posición local del vértice
			var position = Vector3(float(x) * chunk_scale, y, float(z) * chunk_scale)
			vertices.append(position)
			colors.append(vertex_color)
			uvs.append(Vector2(float(x) * uv_scale, float(z) * uv_scale))
			
			# Guardar altura para la colisión
			# NOTA: HeightMapShape3D está centrado, el mesh no.
			# Ajustamos la posición local.
			height_map_data[z * verts_per_side + x] = y # ¡OJO! Godot lee Z-primero
			
			idx += 1
	
	# ... (tu código para generar índices no cambia) ...
	for x in range(chunk_size):
		for z in range(chunk_size):
			var v0 = x * verts_per_side + z
			var v1 = (x + 1) * verts_per_side + z
			var v2 = x * verts_per_side + (z + 1)
			var v3 = (x + 1) * verts_per_side + (z + 1)
			indices.append(v0); indices.append(v1); indices.append(v2)
			indices.append(v1); indices.append(v3); indices.append(v2)

	# Crear la malla
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	var st = SurfaceTool.new()
	st.create_from(array_mesh, 0)
	st.generate_normals()
	st.generate_tangents()
	
	# ¡Devolver AMBOS, el mesh y los datos de altura!
	return {
		"mesh": st.commit(),
		"heights": height_map_data
	}
	
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
	var biome_value = biome_noise.get_noise_2d(world_x, world_z)
	
	var blend_weights: Array = []
	var total_weight: float = 0.0
	
	for biome in biomes:
		var weight = biome.get_weight(biome_value)
		if weight > 0.0:
			blend_weights.append({"biome": biome, "weight": weight})
			total_weight += weight
	
	if blend_weights.is_empty() or total_weight <= 0.0:
		var noise_value = noise.get_noise_2d(world_x, world_z) # Usar ruido por defecto
		return {"height": noise_value * height_multiplier, "color": terrain_color}
	
	for data in blend_weights:
		data.weight /= total_weight
	
	var final_height: float = 0.0
	var final_color: Color = Color.BLACK
	
	for data in blend_weights:
		var biome: BiomeData = data.biome
		var weight: float = data.weight
		
		# ¡YA NO MODIFICAMOS EL RUIDO GLOBAL!
		# Simplemente usamos el ruido pre-configurado del bioma
		var noise_value = biome.noise.get_noise_2d(world_x, world_z)
		var biome_height = noise_value * biome.height_multiplier
		
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

func add_custom_biome(name: String, height: float, octaves_count: int, freq: float, min_core: float, max_core: float, blend_range: float, color: Color = Color.WHITE):
	"""Agrega un bioma personalizado (versión actualizada para blending)"""
	
	# Pasamos todos los argumentos en el orden correcto
	biomes.append(BiomeData.new(name, height, octaves_count, freq, min_core, max_core, blend_range, color))
	
	if enable_biomes:
		regenerate_all_chunks()

func clear_biomes():
	"""Limpia todos los biomas y vuelve a los predeterminados"""
	biomes.clear()
	setup_biomes()
	if enable_biomes:
		regenerate_all_chunks()

func get_biome_at_position(world_pos: Vector3) -> String:
	"""Retorna el nombre del bioma dominante en una posición"""
	if not enable_biomes or biomes.is_empty():
		return "Sin bioma"
	
	# Usamos la misma lógica de / chunk_scale que ya tenías
	var biome_value = biome_noise.get_noise_2d(world_pos.x / chunk_scale, world_pos.z / chunk_scale)
	
	var dominant_biome: String = "Desconocido"
	var max_weight: float = 0.0
	
	for biome in biomes:
		var weight = biome.get_weight(biome_value)
		if weight > max_weight:
			max_weight = weight
			dominant_biome = biome.name
			
	# Si el peso máximo es 1.0, estamos en un "núcleo"
	if max_weight == 1.0:
		return dominant_biome
	# Si es menor que 1.0 pero mayor que 0, estamos en una zona de mezcla
	elif max_weight > 0.0:
		return "Transición (Dominante: %s)" % dominant_biome
	
	return "Desconocido (Valor: %.2f)" % biome_value
	
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

# Esta función helper actualiza el material SI ya existe.
func _update_shader_param(param_name: StringName, value):
	if shared_material:
		shared_material.set_shader_parameter(param_name, value)
