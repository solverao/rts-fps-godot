# Archivo: res://managers/OceanManager.gd
# ¡Añádelo como Autoloader llamado "OceanManager"!
extends Node

# Parámetros de la ola (puedes ajustarlos)
var amplitude: float = 0.3
var frequency: float = 2.0
var speed: float = 1.0

# Esta es la función clave que usará nuestro barco
# Devuelve la altura Y de la ola en una posición X, Z global
func get_wave_height_at(position: Vector3) -> float:
	# Obtenemos el tiempo global (independiente de la pausa)
	var time = Time.get_ticks_msec() / 1000.0 * speed

	# ESTA ES LA MISMA LÓGICA QUE USAREMOS EN EL SHADER
	var wave_1 = sin(position.x * frequency + time)
	var wave_2 = sin(position.z * (frequency * 1.5) + time * 0.5) * 0.5

	var height = (wave_1 + wave_2) * amplitude
	return height
