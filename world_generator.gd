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
	var octaves: int
	var frequency: float
	var min_core: float
	var max_core: float
	var blend_range: float
	var color: Color
	
	# --- NUEVAS PROPIEDADES PARA SPLATMAP ---
	var base_rock_weight: float
	var base_sand_weight: float
	
	# Actualizamos _init para recibir los pesos de textura
	func _init(p_name: String, p_height: float, p_octaves: int, p_freq: float, 
			   p_min_core: float, p_max_core: float, p_blend: float, 
			   p_color: Color = Color.WHITE,
			   p_rock: float = 0.0, p_sand: float = 0.0): # <-- Nuevos parámetros
		
		name = p_name
		height_multiplier = p_height
		octaves = p_octaves
		frequency = p_freq
		min_core = p_min_core
		max_core = p_max_core
		blend_range = p_blend
		color = p_color
		
		# Guardar pesos base
		self.base_rock_weight = p_rock
		self.base_sand_weight = p_sand

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
	"""Configura los biomas predefinidos, incluyendo Playa y Volcán"""
	biomes.clear()
	
	var blend_amount: float = biome_blend_distance # Usamos tu variable @export

	# --- RANGOS AJUSTADOS ---
	# El ruido va de -1.0 a 1.0. Dividimos ese espacio:
	
	# Bioma 1: Playa (Arena 100%)
	# Rango de ruido: [-1.0, -0.8]
	biomes.append(BiomeData.new(
		"Playa", 1.0, 1, 0.05, # Muy bajo y plano
		-1.0,   # min_core
		-0.8,   # max_core
		blend_amount,
		Color("e6d8ad"), # Color arena
		0.0,  # p_rock: 0%
		1.0   # p_sand: 100%
	))

	# Bioma 2: Llanuras (Ajustado)
	# Rango de ruido: [-0.7, -0.4] (Deja espacio para mezclar con Playa)
	biomes.append(BiomeData.new(
		"Llanuras", 2.0, 1, 0.1,
		-0.7,   # min_core (Ajustado)
		-0.4,   # max_core
		blend_amount,
		Color(0.4, 0.7, 0.3),
		0.0,  # p_rock: 0%
		0.05  # p_sand: 5% (Un poco de arena)
	))
	
	# Bioma 3: Colinas (Sin cambios)
	# Rango de ruido: [-0.3, 0.3]
	biomes.append(BiomeData.new(
		"Colinas", 12.0, 3, 0.04,
		-0.3,   # min_core
		0.3,    # max_core
		blend_amount,
		Color(0.35, 0.5, 0.25),
		0.0,  # p_rock: 0% (La roca vendrá de la pendiente)
		0.0   # p_sand: 0%
	))
	
	# Bioma 4: Montañas (Ajustado)
	# Rango de ruido: [0.4, 0.7] (Deja espacio para mezclar con Volcán)
	biomes.append(BiomeData.new(
		"Montañas", 65.0, 6, 0.02,
		0.4,    # min_core
		0.7,    # max_core (Ajustado)
		blend_amount,
		Color(0.5, 0.4, 0.35),
		0.6,  # p_rock: 60%
		0.0   # p_sand: 0%
	))
	
	# Bioma 5: Volcán (Roca 100%)
	# Rango de ruido: [0.8, 1.0]
	biomes.append(BiomeData.new(
		"Volcán", 80.0, 7, 0.015, # Muy alto y detallado
		0.8,    # min_core
		1.0,    # max_core
		blend_amount,
		Color("3d3d3d"), # Color roca oscura
		1.0,  # p_rock: 100%
		0.0   # p_sand: 0%
	))
	
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

# --- FUNCIÓN MODIFICADA ---
func generate_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return
	
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	mesh_instance.position = chunk_to_world(chunk_pos)
	
	# 1. Generar datos CON padding (1 vértice extra en cada lado)
	var padded_data = _generate_padded_data(chunk_pos)
	
	# 2. Obtener los datos del mesh (ahora usa los datos 'padded')
	var mesh_data: Dictionary = create_chunk_mesh(chunk_pos, padded_data)
	var mesh: ArrayMesh = mesh_data["mesh"]
	var height_map: PackedFloat32Array = mesh_data["heights"] # Este es el SIN padding
	
	mesh_instance.mesh = mesh
	
	# 3. Generar el Splatmap ÚNICO (ahora usa los datos 'padded')
	var splatmap_texture = _generate_splatmap_texture(chunk_pos, padded_data)
	
	# 4. DUPLICAR el material base
	var unique_material = shared_material.duplicate()
	
	# 5. Asignar la textura splatmap ÚNICA a este material
	unique_material.set_shader_parameter("tex_splatmap", splatmap_texture)
	
	# 6. Aplicar el material ÚNICO al mesh
	mesh_instance.set_surface_override_material(0, unique_material)
	
	# --- FIN DE LOS CAMBIOS DE COSTURAS ---
	
	# Configurar sombras (sin cambios)
	if enable_shadows:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# ... (código de frustum culling) ...
	
	var static_body: StaticBody3D = null
	var collision_shape: CollisionShape3D = null
	
	if enable_collision:
		# Esta lógica no cambia, ya que 'mesh_data["heights"]'
		# es el array SIN padding del tamaño correcto
		static_body = StaticBody3D.new()
		mesh_instance.add_child(static_body)
		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		
		collision_shape = CollisionShape3D.new()
		static_body.add_child(collision_shape)
		
		var height_shape = HeightMapShape3D.new()
		height_shape.map_width = chunk_size + 1
		height_shape.map_depth = chunk_size + 1
		height_shape.map_data = height_map
		
		var terrain_size = float(chunk_size) * chunk_scale
		collision_shape.shape = height_shape
		collision_shape.scale = Vector3(chunk_scale, 1.0, chunk_scale)
		collision_shape.position = Vector3(terrain_size / 2.0, 0, terrain_size / 2.0)
	
	# Guardar el chunk (sin cambios)
	var chunk_data = ChunkData.new(mesh_instance, chunk_pos)
	chunk_data.static_body = static_body
	chunk_data.collision_shape = collision_shape
	loaded_chunks[chunk_pos] = chunk_data
		
# --- FUNCIÓN MODIFICADA ---
func create_chunk_mesh(chunk_pos: Vector2i, padded_data: Dictionary) -> Dictionary:
	# Extraer datos 'padded'
	var padded_heights: PackedFloat32Array = padded_data["heights"]
	var padded_colors: PackedColorArray = padded_data["colors"]
	var padded_width: int = padded_data["width"]

	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var colors: PackedColorArray = []
	var normals: PackedVector3Array = [] # <-- Array para normales custom
	var indices: PackedInt32Array = []
	
	var verts_per_side = chunk_size + 1 # Tamaño de la malla final
	
	# Array para el HeightMapShape3D (sin padding)
	var height_map_data: PackedFloat32Array = []
	height_map_data.resize(verts_per_side * verts_per_side)
	
	var uv_scale = 1.0 / float(chunk_size)
	
	# 1. Construir Vértices, Normales y Colisión
	# Iteramos sobre el tamaño FINAL (sin padding)
	for x in range(verts_per_side):
		for z in range(verts_per_side):
			
			# Mapeamos (x, z) a los índices del array 'padded'
			# (x=0, z=0) -> (px=1, pz=1)
			var padded_x = x + 1
			var padded_z = z + 1
			var padded_idx = padded_z * padded_width + padded_x
			
			var y = padded_heights[padded_idx]
			var vertex_color = padded_colors[padded_idx]
			
			# Posición local del vértice
			var position = Vector3(float(x) * chunk_scale, y, float(z) * chunk_scale)
			vertices.append(position)
			colors.append(vertex_color)
			uvs.append(Vector2(float(x) * uv_scale, float(z) * uv_scale))
			
			# ¡Calcular y guardar la normal correcta!
			var normal = _calculate_normal_at(padded_heights, padded_x, padded_z, padded_width)
			normals.append(normal)
			
			# Guardar altura para la colisión
			height_map_data[z * verts_per_side + x] = y # (Z-primero)

	# 2. Construir Índices (sin cambios)
	for x in range(chunk_size):
		for z in range(chunk_size):
			var v0 = x * verts_per_side + z
			var v1 = (x + 1) * verts_per_side + z
			var v2 = x * verts_per_side + (z + 1)
			var v3 = (x + 1) * verts_per_side + (z + 1)
			indices.append(v0); indices.append(v1); indices.append(v2)
			indices.append(v1); indices.append(v3); indices.append(v2)

	# 3. Crear la malla
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals # <-- Asignar normales custom
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# 4. Generar Tangentes (¡usando nuestras normales!)
	var st = SurfaceTool.new()
	st.create_from(array_mesh, 0)
	# ¡NO LLAMAR a st.generate_normals()!
	st.generate_tangents() # Esto usará nuestras normales para generar tangentes
	
	# 5. Devolver resultados
	return {
		"mesh": st.commit(), # 'commit' aplica las tangentes
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
	"""Calcula la altura y color basándose en biomas con transiciones suaves"""
	
	# 1. Obtenemos los pesos de bioma
	var blend_weights = get_biome_blend_data(world_x, world_z)
	
	# 2. Si no hay biomas, usar valores por defecto
	if blend_weights.is_empty():
		var noise_value = noise.get_noise_2d(world_x, world_z)
		return {"height": noise_value * height_multiplier, "color": terrain_color}
	
	# 3. Calcular altura final y color (esta parte ya la tenías bien)
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

func add_custom_biome(name: String, height: float, octaves_count: int, freq: float, 
					  min_core: float, max_core: float, blend_range: float, 
					  color: Color = Color.WHITE,
					  rock_weight: float = 0.0, sand_weight: float = 0.0): # <-- Nuevos params
	
	# Pasamos todos los argumentos en el orden correcto
	biomes.append(BiomeData.new(name, height, octaves_count, freq, 
								min_core, max_core, blend_range, 
								color, rock_weight, sand_weight)) # <-- Pasarlos al constructor
	
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

# Esta función crea la textura splatmap para UN chunk
# REEMPLAZA tu vieja _generate_splatmap_texture con esta
# ¡OJO! Ahora recibe "chunk_pos" como primer argumento
# --- FUNCIÓN MODIFICADA ---
# Ahora recibe 'padded_data'
# --- FUNCIÓN MODIFICADA ---
# Ahora recibe 'padded_data'
func _generate_splatmap_texture(chunk_pos: Vector2i, padded_data: Dictionary) -> ImageTexture:
	# Extraer datos 'padded'
	var padded_heights: PackedFloat32Array = padded_data["heights"]
	var padded_width: int = padded_data["width"]

	var verts_per_side = chunk_size + 1 # Tamaño de la imagen final
	var img = Image.create(verts_per_side, verts_per_side, false, Image.FORMAT_RGBA8)

	var p_sand_height = sand_height
	var p_sand_blend = sand_blend_range
	var p_slope_sharp = slope_sharpness
	
	var offset_x = chunk_pos.x * chunk_size
	var offset_z = chunk_pos.y * chunk_size

	# Recorremos cada píxel (que corresponde a un vértice FINAL)
	for x in range(verts_per_side):
		for z in range(verts_per_side):
			
			# Mapeamos (x, z) a los índices del array 'padded'
			var padded_x = x + 1
			var padded_z = z + 1
			var padded_idx = padded_z * padded_width + padded_x
			
			# Posición mundial (sin cambios)
			var world_x = float(offset_x + x)
			var world_z = float(offset_z + z)
			
			# --- 1. Calcular Lógica Global (Altura y Pendiente) ---
			
			# Obtener altura desde los datos 'padded'
			var y = padded_heights[padded_idx]
			
			# ¡Calcular pendiente usando los datos 'padded' y los índices 'padded'!
			var slope = _calculate_slope_at(padded_heights, padded_x, padded_z, padded_width)
			
			# El resto de la lógica de splatmap no necesita cambios
			var global_sand_weight = smoothstep(p_sand_height + p_sand_blend, p_sand_height - p_sand_blend, y)
			var global_rock_weight = pow(slope, p_slope_sharp)
			
			# --- 2. Calcular Lógica de Biomas (sin cambios) ---
			var blend_weights = get_biome_blend_data(world_x, world_z)
			var biome_rock_weight = 0.0
			var biome_sand_weight = 0.0
			
			if not blend_weights.is_empty():
				for data in blend_weights:
					var biome: BiomeData = data.biome
					var weight: float = data.weight
					biome_rock_weight += biome.base_rock_weight * weight
					biome_sand_weight += biome.base_sand_weight * weight
			
			# --- 3. Combinar Lógicas (sin cambios) ---
			var final_rock_weight = max(biome_rock_weight, global_rock_weight)
			var final_sand_weight = max(biome_sand_weight, global_sand_weight)		
				
			# --- 4. Corregir y Normalizar (sin cambios) ---
			final_rock_weight = final_rock_weight * (1.0 - final_sand_weight)
			final_rock_weight = clamp(final_rock_weight, 0.0, 1.0)
			final_sand_weight = clamp(final_sand_weight, 0.0, 1.0)
			
			# 5. Pintar el Píxel (sin cambios)
			img.set_pixel(x, z, Color(final_rock_weight, final_sand_weight, 0.0))

	return ImageTexture.create_from_image(img)
	
# Función helper para calcular la pendiente en un punto del heightmap
# --- FUNCIÓN MODIFICADA ---
# (Eliminamos max() y min() de los índices)
func _calculate_slope_at(height_map: PackedFloat32Array, x: int, z: int, width: int) -> float:
	# Índices de los vecinos (¡SIN CLAMPING!)
	var x_left = x - 1
	var x_right = x + 1
	var z_down = z - 1
	var z_up = z + 1
	
	# Alturas de los vecinos
	var y_L = height_map[z * width + x_left]
	var y_R = height_map[z * width + x_right]
	var y_D = height_map[z_down * width + x]
	var y_U = height_map[z_up * width + x]
	
	# Calcular la normal del vértice
	var normal = Vector3(y_L - y_R, 2.0 * chunk_scale, y_D - y_U).normalized()
	
	# La pendiente es 1.0 - normal.y
	return 1.0 - normal.y

func get_biome_blend_data(world_x: float, world_z: float) -> Array:
	"""Devuelve un array de biomas y sus pesos normalizados en un punto."""
	var biome_value = biome_noise.get_noise_2d(world_x, world_z)
	
	var blend_weights: Array = []
	var total_weight: float = 0.0
	
	# 1. Obtener el peso de CADA bioma
	for biome in biomes:
		var weight = biome.get_weight(biome_value)
		if weight > 0.0:
			blend_weights.append({"biome": biome, "weight": weight})
			total_weight += weight
	
	# 2. Si no encontramos bioma o peso, retornar array vacío
	if blend_weights.is_empty() or total_weight <= 0.0:
		return []
	
	# 3. Normalizar pesos (dividir por el total)
	for data in blend_weights:
		data.weight /= total_weight
		
	return blend_weights



# --- NUEVA FUNCIÓN ---
# Genera los datos de altura y color en una cuadrícula más grande
# (con 1 vértice de padding en todas las direcciones)
func _generate_padded_data(chunk_pos: Vector2i) -> Dictionary:
	var verts_per_side = chunk_size + 1
	var padded_width = verts_per_side + 2 # +2 para el padding de -1 y +1
	var padded_size = padded_width * padded_width
	
	var padded_heights: PackedFloat32Array
	var padded_colors: PackedColorArray
	padded_heights.resize(padded_size)
	padded_colors.resize(padded_size)
	
	var offset_x = chunk_pos.x * chunk_size
	var offset_z = chunk_pos.y * chunk_size
	
	for x in range(padded_width):
		for z in range(padded_width):
			# Restamos 1 para que el bucle (0,0) muestree en (-1, -1)
			var world_x = float(offset_x + x - 1)
			var world_z = float(offset_z + z - 1)
			
			var height_data: Dictionary
			if enable_biomes:
				height_data = get_biome_height(world_x, world_z)
			else:
				var noise_value = noise.get_noise_2d(world_x, world_z)
				height_data = {"height": noise_value * height_multiplier, "color": terrain_color}

			var idx = z * padded_width + x
			padded_heights[idx] = height_data.height
			padded_colors[idx] = height_data.color
			
	return {
		"heights": padded_heights,
		"colors": padded_colors,
		"width": padded_width
	}
	
# --- NUEVA FUNCIÓN ---
# Calcula la normal del vértice usando los datos 'padded'
# Nota: 'x' y 'z' son los índices en el array 'padded' (ej. 1 a verts_per_side)
func _calculate_normal_at(padded_heights: PackedFloat32Array, x: int, z: int, width: int) -> Vector3:
	# Obtenemos alturas de vecinos (¡sin 'max' o 'min'!)
	var y_L = padded_heights[z * width + (x - 1)]
	var y_R = padded_heights[z * width + (x + 1)]
	var y_D = padded_heights[(z - 1) * width + x]
	var y_U = padded_heights[(z + 1) * width + x]
	
	# Calcula la normal
	var normal = Vector3(y_L - y_R, 2.0 * chunk_scale, y_D - y_U).normalized()
	return normal
