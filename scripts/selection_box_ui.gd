extends Control
class_name SelectionBoxUI

var is_selecting: bool = false
var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO

@export var fill_color: Color = Color(0, 1, 0, 0.2)
@export var border_color: Color = Color(0, 1, 0, 0.8)
@export var border_width: float = 2.0

func _ready():
	# Asegurar que el control cubra toda la pantalla
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func start_selection(pos: Vector2):
	"""Inicia la selección en una posición"""
	is_selecting = true
	start_pos = pos
	end_pos = pos
	queue_redraw()

func update_selection(pos: Vector2):
	"""Actualiza la posición final de la selección"""
	if is_selecting:
		end_pos = pos
		queue_redraw()

func end_selection() -> Rect2:
	"""Finaliza la selección y retorna el rectángulo"""
	is_selecting = false
	var rect = get_selection_rect()
	queue_redraw()
	return rect

func get_selection_rect() -> Rect2:
	"""Obtiene el rectángulo de selección"""
	var min_x = min(start_pos.x, end_pos.x)
	var min_y = min(start_pos.y, end_pos.y)
	var width = abs(end_pos.x - start_pos.x)
	var height = abs(end_pos.y - start_pos.y)
	
	return Rect2(min_x, min_y, width, height)

func _draw():
	"""Dibuja el rectángulo de selección"""
	if is_selecting:
		var rect = get_selection_rect()
		
		# Dibujar relleno
		draw_rect(rect, fill_color, true)
		
		# Dibujar borde
		draw_rect(rect, border_color, false, border_width)
