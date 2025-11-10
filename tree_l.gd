extends Node3D

# ============================================================
# 🌳 GENERADOR DE ÁRBOLES PROCEDURALES MEJORADO
# ============================================================
# Versión optimizada para videojuegos con ramificación natural,
# tropismo, hojas realistas y mejor geometría
# ============================================================

# -----------------------------
# 🌳 Estructura Principal
# -----------------------------
@export_group("Estructura del Árbol")
@export var trunk_height: float = 4.0
@export var trunk_base_radius: float = 0.25
@export_range(3, 16) var trunk_radial_segments: int = 8
@export_range(2, 8) var branch_levels: int = 4
@export_range(2, 8) var branches_per_level: int = 4

# -----------------------------
# 🌿 Ramificación
# -----------------------------
@export_group("Ramificación")
@export_range(0.3, 0.8) var branch_length_ratio: float = 0.7
@export_range(0.5, 0.9) var branch_radius_ratio: float = 0.65
@export_range(15, 60) var branch_angle_min: float = 25.0
@export_range(30, 80) var branch_angle_max: float = 45.0
@export_range(0, 45) var branch_curve: float = 15.0

# -----------------------------
# 🎯 Tropismo (Gravedad/Luz)
# -----------------------------
@export_group("Tropismo")
@export var enable_phototropism: bool = true
@export_range(0, 1) var phototropism_strength: float = 0.3
@export var enable_gravitropism: bool = true
@export_range(0, 0.5) var gravitropism_strength: float = 0.15

# -----------------------------
# 🍃 Follaje
# -----------------------------
@export_group("Follaje")
@export var enable_leaves: bool = true
@export_enum("Quads", "Billboards", "Clusters") var leaf_type: int = 0
@export_range(50, 500) var leaves_per_branch: int = 150
@export_range(0.1, 0.5) var leaf_size: float = 0.25
@export var leaf_clumping: float = 0.6

# -----------------------------
# 🎨 Materiales
# -----------------------------
@export_group("Materiales")
@export var bark_color: Color = Color(0.35, 0.25, 0.18)
@export var bark_roughness: float = 0.95
@export var leaf_color_base: Color = Color(0.2, 0.6, 0.25)
@export var leaf_color_tip: Color = Color(0.4, 0.75, 0.35)
@export var leaf_subsurface: float = 0.4

# -----------------------------
# ⚡ Optimización
# -----------------------------
@export_group("Optimización")
@export var merge_geometry: bool = true
@export var generate_lod: bool = false
@export_range(3, 12) var lod_radial_segments: int = 4

# -----------------------------
# 🎲 Variación
# -----------------------------
@export_group("Variación")
@export var random_seed: int = -1
@export_range(0, 1) var branch_randomness: float = 0.3
@export_range(0, 1) var twist_amount: float = 0.2

# ============================================================
# Variables Internas
# ============================================================
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()

class Branch:
	var start_pos: Vector3
	var end_pos: Vector3
	var start_radius: float
	var end_radius: float
	var direction: Vector3
	var level: int
	var parent_branch: Branch
	
	func _init(s: Vector3, e: Vector3, sr: float, er: float, d: Vector3, l: int, p: Branch = null):
		start_pos = s
		end_pos = e
		start_radius = sr
		end_radius = er
		direction = d
		level = l
		parent_branch = p

var all_branches: Array[Branch] = []
var leaf_data: Array = []

# ============================================================
# 🚀 Inicialización
# ============================================================
func _ready():
	if random_seed >= 0:
		rng.seed = random_seed
	else:
		rng.randomize()
	
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.2
	
	generate_tree()

# ============================================================
# 🌳 Generación Principal
# ============================================================
func generate_tree():
	clear_tree()
	all_branches.clear()
	leaf_data.clear()
	
	print("🌱 Generando árbol...")
	
	# Generar estructura de ramas
	generate_branch_structure()
	
	# Crear geometría
	create_merged_trunk_mesh()
	
	# Crear follaje
	if enable_leaves and all_branches.size() > 0:
		create_foliage_system()
	
	print("✅ Árbol generado: ", all_branches.size(), " ramas, ", leaf_data.size(), " hojas")

# ============================================================
# 🌿 Generar Estructura de Ramas
# ============================================================
func generate_branch_structure():
	# Crear tronco principal
	var trunk_dir = Vector3.UP
	var trunk_end = Vector3.UP * trunk_height
	
	var trunk = Branch.new(
		Vector3.ZERO,
		trunk_end,
		trunk_base_radius,
		trunk_base_radius * branch_radius_ratio,
		trunk_dir,
		0
	)
	all_branches.append(trunk)
	
	# Generar niveles de ramas recursivamente
	generate_branches_recursive(trunk, 1)

func generate_branches_recursive(parent: Branch, current_level: int):
	if current_level > branch_levels:
		return
	
	var branch_length = parent.start_pos.distance_to(parent.end_pos) * branch_length_ratio
	var num_branches = branches_per_level
	
	# Distribuir ramas a lo largo del padre
	for i in range(num_branches):
		var t = (i + 1.0) / (num_branches + 1.0)
		t = pow(t, 0.7) # Bias hacia la punta
		
		var branch_start = parent.start_pos.lerp(parent.end_pos, t)
		var parent_radius = lerp(parent.start_radius, parent.end_radius, t)
		
		# Calcular ángulo de ramificación
		var angle = deg_to_rad(rng.randf_range(branch_angle_min, branch_angle_max))
		angle += rng.randf_range(-branch_randomness, branch_randomness) * PI * 0.25
		
		# Rotación azimutal (alrededor del tronco)
		var azimuth = (i / float(num_branches)) * TAU + rng.randf_range(-twist_amount, twist_amount) * PI
		
		# Calcular dirección de rama
		var up_bias = Vector3.UP * 0.3
		var radial = Vector3(cos(azimuth), 0, sin(azimuth))
		var initial_dir = (parent.direction + up_bias + radial).normalized()
		
		# Aplicar ángulo de ramificación
		var rotation_axis = parent.direction.cross(radial).normalized()
		if rotation_axis.length() < 0.01:
			rotation_axis = Vector3.RIGHT
		var branch_dir = initial_dir.rotated(rotation_axis, angle)
		
		# Aplicar tropismo
		branch_dir = apply_tropism(branch_dir, current_level)
		
		# Aplicar curvatura
		var curve_noise = noise.get_noise_3d(branch_start.x * 2, branch_start.y * 2, branch_start.z * 2)
		var curve_angle = deg_to_rad(branch_curve * curve_noise)
		branch_dir = branch_dir.rotated(rotation_axis, curve_angle)
		
		var branch_end = branch_start + branch_dir.normalized() * branch_length
		
		# Crear rama
		var new_branch = Branch.new(
			branch_start,
			branch_end,
			parent_radius * branch_radius_ratio,
			parent_radius * branch_radius_ratio * branch_radius_ratio,
			branch_dir.normalized(),
			current_level,
			parent
		)
		all_branches.append(new_branch)
		
		# Generar sub-ramas
		if current_level < branch_levels:
			generate_branches_recursive(new_branch, current_level + 1)

# ============================================================
# 🎯 Aplicar Tropismo (Gravedad y Luz)
# ============================================================
func apply_tropism(direction: Vector3, level: int) -> Vector3:
	var result = direction
	var level_factor = 1.0 - (level / float(branch_levels))
	
	# Fototropismo (hacia arriba/luz)
	if enable_phototropism:
		var up_influence = Vector3.UP * phototropism_strength * level_factor
		result = (result + up_influence).normalized()
	
	# Gravitropismo (caída por peso)
	if enable_gravitropism and level > 1:
		var down_influence = Vector3.DOWN * gravitropism_strength * (1.0 - level_factor)
		result = (result + down_influence).normalized()
	
	return result

# ============================================================
# 🪵 Crear Geometría Unificada (Optimizado)
# ============================================================
func create_merged_trunk_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var segments = trunk_radial_segments if not generate_lod else lod_radial_segments
	
	for branch in all_branches:
		add_branch_to_surface(st, branch, segments)
	
	st.generate_normals()
	st.generate_tangents()
	
	var mesh = st.commit()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.name = "TreeTrunk"
	
	# Material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = bark_color
	mat.roughness = bark_roughness
	mat.metallic = 0.0
	mat.normal_enabled = true
	mat.ao_enabled = true
	mat.ao_light_affect = 0.5
	mesh_instance.material_override = mat
	
	add_child(mesh_instance)

func add_branch_to_surface(st: SurfaceTool, branch: Branch, segments: int):
	var length = branch.start_pos.distance_to(branch.end_pos)
	var direction = (branch.end_pos - branch.start_pos).normalized()
	
	# Calcular ejes perpendiculares
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.9:
		up = Vector3.FORWARD
	var right = direction.cross(up).normalized()
	var forward = right.cross(direction).normalized()
	
	# Subdivisiones a lo largo de la rama para curvatura
	var length_segments = max(2, int(length / 0.3))
	
	for seg in range(length_segments):
		var t0 = seg / float(length_segments)
		var t1 = (seg + 1) / float(length_segments)
		
		var pos0 = branch.start_pos.lerp(branch.end_pos, t0)
		var pos1 = branch.start_pos.lerp(branch.end_pos, t1)
		var r0 = lerp(branch.start_radius, branch.end_radius, t0)
		var r1 = lerp(branch.start_radius, branch.end_radius, t1)
		
		# Añadir deformación por ruido
		var noise_val0 = noise.get_noise_3d(pos0.x * 3, pos0.y * 3, pos0.z * 3) * 0.08
		var noise_val1 = noise.get_noise_3d(pos1.x * 3, pos1.y * 3, pos1.z * 3) * 0.08
		
		for i in range(segments):
			var angle0 = (i / float(segments)) * TAU
			var angle1 = ((i + 1) / float(segments)) * TAU
			
			# Calcular vértices del cilindro
			var v0 = pos0 + (right * cos(angle0) + forward * sin(angle0)) * (r0 + noise_val0)
			var v1 = pos1 + (right * cos(angle0) + forward * sin(angle0)) * (r1 + noise_val1)
			var v2 = pos1 + (right * cos(angle1) + forward * sin(angle1)) * (r1 + noise_val1)
			var v3 = pos0 + (right * cos(angle1) + forward * sin(angle1)) * (r0 + noise_val0)
			
			# Normales
			var n0 = (right * cos(angle0) + forward * sin(angle0)).normalized()
			var n1 = (right * cos(angle1) + forward * sin(angle1)).normalized()
			
			# UVs
			var uv_x0 = i / float(segments)
			var uv_x1 = (i + 1) / float(segments)
			var uv_y0 = (seg + t0) / float(length_segments)
			var uv_y1 = (seg + t1) / float(length_segments)
			
			# Primer triángulo
			st.set_normal(n0)
			st.set_uv(Vector2(uv_x0, uv_y0))
			st.add_vertex(v0)
			
			st.set_normal(n0)
			st.set_uv(Vector2(uv_x0, uv_y1))
			st.add_vertex(v1)
			
			st.set_normal(n1)
			st.set_uv(Vector2(uv_x1, uv_y1))
			st.add_vertex(v2)
			
			# Segundo triángulo
			st.set_normal(n0)
			st.set_uv(Vector2(uv_x0, uv_y0))
			st.add_vertex(v0)
			
			st.set_normal(n1)
			st.set_uv(Vector2(uv_x1, uv_y1))
			st.add_vertex(v2)
			
			st.set_normal(n1)
			st.set_uv(Vector2(uv_x1, uv_y0))
			st.add_vertex(v3)

# ============================================================
# 🍃 Sistema de Follaje Mejorado
# ============================================================
func create_foliage_system():
	match leaf_type:
		0: create_quad_leaves()
		1: create_billboard_leaves()
		2: create_cluster_leaves()

func create_quad_leaves():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var leaf_count = 0
	
	# Solo en ramas superiores
	for branch in all_branches:
		if branch.level < 2:
			continue
		
		var leaves_on_branch = int(leaves_per_branch / float(branch.level))
		
		for i in range(leaves_on_branch):
			var t = rng.randf()
			# Agrupar hojas hacia la punta
			t = pow(t, 1.0 / (1.0 + leaf_clumping))
			
			var pos = branch.start_pos.lerp(branch.end_pos, t)
			
			# Offset aleatorio
			var offset = Vector3(
				rng.randf_range(-0.15, 0.15),
				rng.randf_range(-0.1, 0.1),
				rng.randf_range(-0.15, 0.15)
			)
			pos += offset
			
			# Orientación aleatoria
			var angle = rng.randf() * TAU
			var tilt = rng.randf_range(-0.3, 0.3)
			
			add_leaf_quad(st, pos, angle, tilt, leaf_size)
			leaf_count += 1
	
	if leaf_count == 0:
		return
	
	st.generate_normals()
	var mesh = st.commit()
	
	var leaves = MeshInstance3D.new()
	leaves.mesh = mesh
	leaves.name = "Leaves"
	
	# Material de hojas
	var mat = StandardMaterial3D.new()
	mat.albedo_color = leaf_color_base
	mat.roughness = 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.subsurface_scattering_enabled = true
	mat.subsurface_scattering_strength = leaf_subsurface
	mat.subsurface_scattering_skin_mode = true
	leaves.material_override = mat
	
	add_child(leaves)

func add_leaf_quad(st: SurfaceTool, pos: Vector3, rotation: float, tilt: float, size: float):
	var half_size = size * 0.5
	var size_var = rng.randf_range(0.8, 1.2)
	half_size *= size_var
	
	# Color variado
	var color_mix = rng.randf()
	var leaf_color = leaf_color_base.lerp(leaf_color_tip, color_mix)
	
	# Vértices del quad (orientado)
	var right = Vector3.RIGHT.rotated(Vector3.UP, rotation)
	var up = Vector3.UP.rotated(right, tilt)
	
	var v0 = pos + (-right - up) * half_size
	var v1 = pos + (right - up) * half_size
	var v2 = pos + (right + up) * half_size
	var v3 = pos + (-right + up) * half_size
	
	var normal = right.cross(up).normalized()
	
	# Primer triángulo
	st.set_color(leaf_color)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(v0)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(v1)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(v2)
	
	# Segundo triángulo
	st.set_uv(Vector2(0, 0))
	st.add_vertex(v0)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(v2)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(v3)

func create_billboard_leaves():
	# Usar MultiMesh para hojas tipo billboard (más eficiente)
	var mm = MultiMesh.new()
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(leaf_size, leaf_size)
	mm.mesh = quad_mesh
	
	var leaf_count = 0
	for branch in all_branches:
		if branch.level >= 2:
			leaf_count += int(leaves_per_branch / float(branch.level))
	
	mm.instance_count = leaf_count
	mm.transform_format = MultiMesh.TRANSFORM_3D
	
	var idx = 0
	for branch in all_branches:
		if branch.level < 2:
			continue
		
		var leaves_on_branch = int(leaves_per_branch / float(branch.level))
		for i in range(leaves_on_branch):
			if idx >= leaf_count:
				break
			
			var t = pow(rng.randf(), 1.0 / (1.0 + leaf_clumping))
			var pos = branch.start_pos.lerp(branch.end_pos, t)
			pos += Vector3(
				rng.randf_range(-0.15, 0.15),
				rng.randf_range(-0.1, 0.1),
				rng.randf_range(-0.15, 0.15)
			)
			
			var transform = Transform3D().rotated(Vector3.UP, rng.randf() * TAU)
			transform = transform.scaled(Vector3.ONE * rng.randf_range(0.8, 1.3))
			transform.origin = pos
			mm.set_instance_transform(idx, transform)
			idx += 1
	
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "LeavesBillboard"
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = leaf_color_base
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = mat
	
	add_child(mmi)

func create_cluster_leaves():
	# Crear grupos/clusters de hojas (más denso)
	create_quad_leaves() # Reutiliza la lógica pero con más densidad

# ============================================================
# 🧹 Limpiar Árbol
# ============================================================
func clear_tree():
	for child in get_children():
		child.queue_free()

# ============================================================
# 🔄 Regenerar
# ============================================================
func regenerate():
	generate_tree()

# ============================================================
# 📦 Presets de Árboles
# ============================================================
func preset_oak():
	branch_levels = 4
	branches_per_level = 4
	branch_angle_min = 30
	branch_angle_max = 50
	branch_curve = 20
	trunk_height = 4.5
	phototropism_strength = 0.2
	leaf_type = 0
	regenerate()

func preset_pine():
	branch_levels = 6
	branches_per_level = 6
	branch_angle_min = 15
	branch_angle_max = 30
	branch_curve = 5
	trunk_height = 6.0
	phototropism_strength = 0.1
	gravitropism_strength = 0.05
	leaf_type = 2
	leaf_size = 0.15
	regenerate()

func preset_willow():
	branch_levels = 4
	branches_per_level = 5
	branch_angle_min = 20
	branch_angle_max = 40
	branch_curve = 35
	trunk_height = 3.5
	phototropism_strength = 0.1
	gravitropism_strength = 0.35
	leaf_type = 0
	regenerate()

func preset_birch():
	branch_levels = 3
	branches_per_level = 3
	branch_angle_min = 25
	branch_angle_max = 45
	branch_curve = 10
	trunk_height = 5.0
	trunk_base_radius = 0.15
	bark_color = Color(0.9, 0.88, 0.85)
	leaf_color_base = Color(0.3, 0.7, 0.3)
	regenerate()
