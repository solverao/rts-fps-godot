# ocean.gd
extends MeshInstance3D
class_name Ocean

# Función para obtener la altura del océano en una posición específica
func get_wave_height(world_position: Vector3) -> float:
	var material = self.material_override as ShaderMaterial
	if not material:
		return 0.0
	
	var amplitude = material.get_shader_parameter("amplitude")
	var frequency = material.get_shader_parameter("frequency")
	var speed = material.get_shader_parameter("speed")
	var time = Time.get_ticks_msec() / 1000.0
	
	# Replica la misma fórmula del shader
	var uv = Vector2(world_position.x, world_position.z) * frequency
	var wave = sin(uv.x + time * speed) * cos(uv.y + time * speed * 0.5)
	
	return wave * amplitude

# Función para obtener la normal (para inclinación del barco)
func get_wave_normal(world_position: Vector3) -> Vector3:
	var epsilon = 0.1
	var height_center = get_wave_height(world_position)
	var height_right = get_wave_height(world_position + Vector3.RIGHT * epsilon)
	var height_forward = get_wave_height(world_position + Vector3.FORWARD * epsilon)
	
	var tangent_x = Vector3(epsilon, height_right - height_center, 0)
	var tangent_z = Vector3(0, height_forward - height_center, epsilon)
	
	return tangent_x.cross(tangent_z).normalized()

func _process(delta):
	var material = self.material_override as ShaderMaterial
	if material:
		material.set_shader_parameter("amplitude", OceanManager.amplitude)
		material.set_shader_parameter("frequency", OceanManager.frequency)
		material.set_shader_parameter("speed", OceanManager.speed)
