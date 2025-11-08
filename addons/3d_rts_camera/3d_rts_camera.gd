extends Node3D

# --- Configuración de Chunks ---
@export_group("Chunk Settings")
@export var chunk_size: int = 32  # Tamaño de cada chunk (vértices)
@export var render_distance: int = 4  # Cuántos chunks cargar alrededor del jugador
@export var chunk_scale: float = 2.0  # Separación entre vértices

@export_group("Terrain Settings")
@export var height_multiplier: float = 15.0
@export var noise_frequency: float = 0.05

@export_group("Player Reference")
@export var player: Node3D  # Arrastra aquí tu jugador o cámara

@export_group("Performance")
@export var use_threading: bool = true  # Generación asíncrona
@export var use_cache: bool = true  # Guardar chunks en disco
@export var max_threads: int = 4  # Número máximo de threads simultáneos
@export var chunks_per_frame: int = 2  # Chunks a procesar por frame

# Almacenamiento de chunks
var loaded_chunks: Dictionary = {}  # {Vector2i: MeshInstance3D}
var cached_chunk_data: Dictionary = {}  # {Vector2i: ChunkData} en memoria
var noise: FastNoiseLite = FastNoiseLite.new()

# Sistema de threads
var generation_threads: Array[Thread] = []
var thread_semaphore: Semaphore = Semaphore.new()
var active_threads: int = 0
var thread_mutex: Mutex = Mutex.new()

# Colas de trabajo
var chunk_queue: Array[Vector2i] = []
var chunks_to_unload: Array[Vector2i] = []
var generated_chunks_queue: Array = []  # [{pos: Vector2i, data: ChunkData}]

# Caché en disco
var cache_dir: String = "user://terrain_cache/"
var cache_enabled: bool = false

# Clase para almacenar datos del chunk
class ChunkData:
	var vertices: PackedVector3Array
	var uvs: PackedVector2Array
	var indices: PackedInt32Array
	var chunk_pos: Vector2i

func _ready():
	setup_noise()
	setup_cache_directory()
	
	if player == null:
		player = self
	
	# Generar chunks iniciales alrededor del origen
	generate_initial_chunks()
	
	# Esperar un frame para que se apliquen las colisiones
	await get_tree().process_frame
	
	# Actualizar chunks
	update_chunks()

func generate_initial_chunks():
	# Generar un área de chunks alrededor del spawn del jugador
	var player_chunk = world_to_chunk(player.global_position)
	
	for x in range(-2, 3):  # 5x5 chunks iniciales
		for z in range(-2, 3):
			var chunk_pos = player_chunk + Vector2i(x, z)
			if use_threading:
				# Generar síncronamente los chunks iniciales para evitar caída
				var chunk_data = generate_chunk_data(chunk_pos)
				apply_chunk_mesh(chunk_pos, chunk_data)
				if use_cache:
					save_chunk_to_cache(chunk_pos, chunk_data)
			else:
				var chunk_data = generate_chunk_data(chunk_pos)
				apply_chunk_mesh(chunk_pos, chunk_data)

func _process(_delta):
	if player:
		update_chunks()
	
	# Procesar chunks generados en threads
	process_generated_chunks()

func _exit_tree():
	# Limpiar threads al salir
	cleanup_threads()

func setup_noise():
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = randi()
	noise.frequency = noise_frequency
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5

func setup_cache_directory():
	if not use_cache:
		return
	
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("terrain_cache"):
			dir.make_dir("terrain_cache")
		cache_enabled = true
		print("Cache de terreno habilitado en: ", cache_dir)

func update_chunks():
	if player == null:
		return
	
	var player_chunk = world_to_chunk(player.global_position)
	
	# Limpiar listas
	chunk_queue.clear()
	chunks_to_unload.clear()
	
	# Determinar qué chunks deben estar cargados
	var chunks_needed: Dictionary = {}
	
	# Ordenar chunks por distancia al jugador (más cerca = mayor prioridad)
	var chunk_distances: Array = []
	
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var chunk_pos = player_chunk + Vector2i(x, z)
			chunks_needed[chunk_pos] = true
			
			if not loaded_chunks.has(chunk_pos):
				var distance = Vector2(x, z).length()
				chunk_distances.append({"pos": chunk_pos, "dist": distance})
	
	# Ordenar por distancia (más cerca primero)
	chunk_distances.sort_custom(func(a, b): return a.dist < b.dist)
	
	# Agregar a la cola
	for item in chunk_distances:
		chunk_queue.append(item.pos)
	
	# Determinar qué chunks descargar
	for chunk_pos in loaded_chunks.keys():
		if not chunks_needed.has(chunk_pos):
			chunks_to_unload.append(chunk_pos)
	
	# Descargar chunks lejanos
	for chunk_pos in chunks_to_unload:
		unload_chunk(chunk_pos)
	
	# Generar nuevos chunks
	for i in range(min(chunks_per_frame, chunk_queue.size())):
		request_chunk_generation(chunk_queue[i])

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	var chunk_world_size = chunk_size * chunk_scale
	return Vector2i(
		int(floor(world_pos.x / chunk_world_size)),
		int(floor(world_pos.z / chunk_world_size))
	)

func request_chunk_generation(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return
	
	# Primero intentar cargar desde caché
	if use_cache and try_load_from_cache(chunk_pos):
		return
	
	# Si no está en caché, generar
	if use_threading:
		start_chunk_generation_thread(chunk_pos)
	else:
		# Generación síncrona (sin threads)
		var chunk_data = generate_chunk_data(chunk_pos)
		apply_chunk_mesh(chunk_pos, chunk_data)

func start_chunk_generation_thread(chunk_pos: Vector2i):
	# Limitar número de threads activos
	thread_mutex.lock()
	if active_threads >= max_threads:
		thread_mutex.unlock()
		return
	active_threads += 1
	thread_mutex.unlock()
	
	# Crear y lanzar thread
	var thread = Thread.new()
	generation_threads.append(thread)
	thread.start(_thread_generate_chunk.bind(chunk_pos, thread))

func _thread_generate_chunk(chunk_pos: Vector2i, thread: Thread):
	# Esta función se ejecuta en un thread separado
	var chunk_data = generate_chunk_data(chunk_pos)
	
	# Agregar resultado a la cola thread-safe
	thread_mutex.lock()
	generated_chunks_queue.append({"pos": chunk_pos, "data": chunk_data, "thread": thread})
	thread_mutex.unlock()

func process_generated_chunks():
	if generated_chunks_queue.is_empty():
		return
	
	thread_mutex.lock()
	var chunks_to_process = generated_chunks_queue.duplicate()
	generated_chunks_queue.clear()
	thread_mutex.unlock()
	
	# Aplicar chunks generados (esto debe hacerse en el main thread)
	for item in chunks_to_process:
		apply_chunk_mesh(item.pos, item.data)
		
		# Limpiar thread
		if item.thread.is_alive():
			item.thread.wait_to_finish()
		
		thread_mutex.lock()
		active_threads -= 1
		generation_threads.erase(item.thread)
		thread_mutex.unlock()
		
		# Guardar en caché si está habilitado
		if use_cache:
			save_chunk_to_cache(item.pos, item.data)

func generate_chunk_data(chunk_pos: Vector2i) -> ChunkData:
	var chunk_data = ChunkData.new()
	chunk_data.chunk_pos = chunk_pos
	
	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	
	var chunk_world_size = chunk_size * chunk_scale
	var offset_x = chunk_pos.x * chunk_size
	var offset_z = chunk_pos.y * chunk_size
	
	# Generar vértices
	for x in range(chunk_size + 1):
		for z in range(chunk_size + 1):
			var world_x = offset_x + x
			var world_z = offset_z + z
			
			var noise_value = noise.get_noise_2d(float(world_x), float(world_z))
			var y = noise_value * height_multiplier
			
			var position = Vector3(float(x) * chunk_scale, y, float(z) * chunk_scale)
			vertices.append(position)
			uvs.append(Vector2(float(x) / float(chunk_size), float(z) / float(chunk_size)))
	
	# Generar índices
	for x in range(chunk_size):
		for z in range(chunk_size):
			var v0 = x * (chunk_size + 1) + z
			var v1 = (x + 1) * (chunk_size + 1) + z
			var v2 = x * (chunk_size + 1) + (z + 1)
			var v3 = (x + 1) * (chunk_size + 1) + (z + 1)
			
			indices.append(v0)
			indices.append(v1)
			indices.append(v2)
			
			indices.append(v1)
			indices.append(v3)
			indices.append(v2)
	
	chunk_data.vertices = vertices
	chunk_data.uvs = uvs
	chunk_data.indices = indices
	
	return chunk_data

func apply_chunk_mesh(chunk_pos: Vector2i, chunk_data: ChunkData):
	if loaded_chunks.has(chunk_pos):
		return
	
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	var chunk_world_size = chunk_size * chunk_scale
	mesh_instance.position = Vector3(
		chunk_pos.x * chunk_world_size,
		0,
		chunk_pos.y * chunk_world_size
	)
	
	# Crear mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = chunk_data.vertices
	arrays[Mesh.ARRAY_TEX_UV] = chunk_data.uvs
	arrays[Mesh.ARRAY_INDEX] = chunk_data.indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	var st = SurfaceTool.new()
	st.create_from(array_mesh, 0)
	st.generate_normals()
	st.generate_tangents()
	
	mesh_instance.mesh = st.commit()
	
	# Aplicar material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.38, 0.28)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.95
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_instance.set_surface_override_material(0, material)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# ===== AGREGAR COLISIÓN =====
	# Crear StaticBody3D para la física
	var static_body = StaticBody3D.new()
	mesh_instance.add_child(static_body)
	
	# Crear CollisionShape3D
	var collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)
	
	# Crear la forma de colisión desde el mesh
	var shape = mesh_instance.mesh.create_trimesh_shape()
	collision_shape.shape = shape
	
	loaded_chunks[chunk_pos] = mesh_instance
	cached_chunk_data[chunk_pos] = chunk_data

# === SISTEMA DE CACHÉ EN DISCO ===

func get_cache_path(chunk_pos: Vector2i) -> String:
	return cache_dir + "chunk_%d_%d.dat" % [chunk_pos.x, chunk_pos.y]

func save_chunk_to_cache(chunk_pos: Vector2i, chunk_data: ChunkData):
	if not cache_enabled:
		return
	
	var file = FileAccess.open(get_cache_path(chunk_pos), FileAccess.WRITE)
	if file:
		# Guardar metadata
		file.store_32(chunk_data.vertices.size())
		file.store_32(chunk_data.indices.size())
		
		# Guardar vértices
		for vertex in chunk_data.vertices:
			file.store_float(vertex.x)
			file.store_float(vertex.y)
			file.store_float(vertex.z)
		
		# Guardar UVs
		for uv in chunk_data.uvs:
			file.store_float(uv.x)
			file.store_float(uv.y)
		
		# Guardar índices
		for index in chunk_data.indices:
			file.store_32(index)
		
		file.close()

func try_load_from_cache(chunk_pos: Vector2i) -> bool:
	if not cache_enabled:
		return false
	
	var cache_path = get_cache_path(chunk_pos)
	if not FileAccess.file_exists(cache_path):
		return false
	
	var file = FileAccess.open(cache_path, FileAccess.READ)
	if not file:
		return false
	
	var chunk_data = ChunkData.new()
	chunk_data.chunk_pos = chunk_pos
	
	# Leer metadata
	var vertex_count = file.get_32()
	var index_count = file.get_32()
	
	# Leer vértices
	var vertices: PackedVector3Array = []
	for i in range(vertex_count):
		var x = file.get_float()
		var y = file.get_float()
		var z = file.get_float()
		vertices.append(Vector3(x, y, z))
	
	# Leer UVs
	var uvs: PackedVector2Array = []
	for i in range(vertex_count):
		var u = file.get_float()
		var v = file.get_float()
		uvs.append(Vector2(u, v))
	
	# Leer índices
	var indices: PackedInt32Array = []
	for i in range(index_count):
		indices.append(file.get_32())
	
	file.close()
	
	chunk_data.vertices = vertices
	chunk_data.uvs = uvs
	chunk_data.indices = indices
	
	# Aplicar el chunk cargado desde caché
	apply_chunk_mesh(chunk_pos, chunk_data)
	
	return true

func unload_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		var mesh_instance = loaded_chunks[chunk_pos]
		mesh_instance.queue_free()
		loaded_chunks.erase(chunk_pos)

func cleanup_threads():
	# Esperar a que todos los threads terminen
	for thread in generation_threads:
		if thread.is_alive():
			thread.wait_to_finish()
	generation_threads.clear()

# === FUNCIONES DE DEBUG Y UTILIDAD ===

func get_chunk_count() -> int:
	return loaded_chunks.size()

func get_cache_size() -> int:
	if not cache_enabled:
		return 0
	
	var dir = DirAccess.open(cache_dir)
	if not dir:
		return 0
	
	var count = 0
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".dat"):
			count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	
	return count

func clear_cache():
	if not cache_enabled:
		return
	
	var dir = DirAccess.open(cache_dir)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".dat"):
			dir.remove(cache_dir + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	print("Caché limpiado")

func regenerate_all_chunks():
	cleanup_threads()
	for chunk_pos in loaded_chunks.keys():
		unload_chunk(chunk_pos)
	cached_chunk_data.clear()
	clear_cache()
	update_chunks()
