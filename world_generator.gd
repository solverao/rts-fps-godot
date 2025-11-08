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

# Almacenamiento de chunks
var loaded_chunks: Dictionary = {}  # {Vector2i: MeshInstance3D}
var noise: FastNoiseLite = FastNoiseLite.new()

# Para generación asíncrona
var chunk_queue: Array[Vector2i] = []
var chunks_to_unload: Array[Vector2i] = []
var is_generating: bool = false

func _ready():
	setup_noise()
	
	# Si no hay jugador asignado, usar la posición actual
	if player == null:
		player = self
	
	# Generar chunks iniciales
	update_chunks()

func _process(_delta):
	# Actualizar chunks cada frame
	if player:
		update_chunks()

func setup_noise():
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = randi()
	noise.frequency = noise_frequency
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5

func update_chunks():
	if player == null:
		return
	
	# Obtener la posición del chunk donde está el jugador
	var player_chunk = world_to_chunk(player.global_position)
	
	# Limpiar listas
	chunk_queue.clear()
	chunks_to_unload.clear()
	
	# Determinar qué chunks deben estar cargados
	var chunks_needed: Dictionary = {}
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var chunk_pos = player_chunk + Vector2i(x, z)
			chunks_needed[chunk_pos] = true
			
			# Si el chunk no existe, agregarlo a la cola de generación
			if not loaded_chunks.has(chunk_pos):
				chunk_queue.append(chunk_pos)
	
	# Determinar qué chunks descargar (están muy lejos)
	for chunk_pos in loaded_chunks.keys():
		if not chunks_needed.has(chunk_pos):
			chunks_to_unload.append(chunk_pos)
	
	# Descargar chunks lejanos
	for chunk_pos in chunks_to_unload:
		unload_chunk(chunk_pos)
	
	# Generar nuevos chunks (limitar a unos pocos por frame)
	var chunks_per_frame = 2
	for i in range(min(chunks_per_frame, chunk_queue.size())):
		generate_chunk(chunk_queue[i])

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	var chunk_world_size = chunk_size * chunk_scale
	return Vector2i(
		int(floor(world_pos.x / chunk_world_size)),
		int(floor(world_pos.z / chunk_world_size))
	)

func generate_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return
	
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	# Posicionar el chunk en el mundo
	var chunk_world_size = chunk_size * chunk_scale
	mesh_instance.position = Vector3(
		chunk_pos.x * chunk_world_size,
		0,
		chunk_pos.y * chunk_world_size
	)
	
	# Generar la geometría del chunk
	var mesh = create_chunk_mesh(chunk_pos)
	mesh_instance.mesh = mesh
	
	# Aplicar material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.38, 0.28)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.95
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_instance.set_surface_override_material(0, material)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# Guardar el chunk
	loaded_chunks[chunk_pos] = mesh_instance

func create_chunk_mesh(chunk_pos: Vector2i) -> ArrayMesh:
	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	
	# Offset global del chunk para el ruido
	var chunk_world_size = chunk_size * chunk_scale
	var offset_x = chunk_pos.x * chunk_size
	var offset_z = chunk_pos.y * chunk_size
	
	# Generar vértices (con 1 vértice extra para conectar con chunks vecinos)
	for x in range(chunk_size + 1):
		for z in range(chunk_size + 1):
			# Posición global para el ruido
			var world_x = offset_x + x
			var world_z = offset_z + z
			
			# Obtener altura del ruido
			var noise_value = noise.get_noise_2d(float(world_x), float(world_z))
			var y = noise_value * height_multiplier
			
			# Posición local del vértice dentro del chunk
			var position = Vector3(float(x) * chunk_scale, y, float(z) * chunk_scale)
			vertices.append(position)
			
			# UVs
			uvs.append(Vector2(float(x) / float(chunk_size), float(z) / float(chunk_size)))
	
	# Generar índices
	for x in range(chunk_size):
		for z in range(chunk_size):
			var v0 = x * (chunk_size + 1) + z
			var v1 = (x + 1) * (chunk_size + 1) + z
			var v2 = x * (chunk_size + 1) + (z + 1)
			var v3 = (x + 1) * (chunk_size + 1) + (z + 1)
			
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
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Generar normales
	var st = SurfaceTool.new()
	st.create_from(array_mesh, 0)
	st.generate_normals()
	st.generate_tangents()
	
	return st.commit()

func unload_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		var mesh_instance = loaded_chunks[chunk_pos]
		mesh_instance.queue_free()
		loaded_chunks.erase(chunk_pos)

# Función útil para depuración
func get_chunk_count() -> int:
	return loaded_chunks.size()

# Función para forzar regeneración (útil si cambias parámetros)
func regenerate_all_chunks():
	for chunk_pos in loaded_chunks.keys():
		unload_chunk(chunk_pos)
	update_chunks()
