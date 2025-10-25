extends Node3D
# Sistema de transición profesional entre cámaras FPS y RTS
# Sin modificar los addons originales

# Referencias a las cámaras de los addons
@export var fps_character: Node3D  # Arrastra aquí tu nodo FPS Character
@export var rts_camera_node: Camera3D  # Arrastra aquí tu cámara RTS
@export var transition_duration: float = 0.8
@export var enable_fade_effect: bool = true

# Cámara de transición (crear como hijo de este nodo)
@onready var transition_camera: Camera3D = $TransitionCamera3D
@onready var fade_overlay: ColorRect

# Variables de control
var current_mode: String = "FPS"
var is_transitioning: bool = false
var transition_progress: float = 0.0

# Datos de transición
var from_transform: Transform3D
var to_transform: Transform3D
var from_fov: float
var to_fov: float
var target_mode: String

# Referencias a cámaras de los addons
var fps_camera: Camera3D
var rts_camera: Camera3D

func _ready():
	# Inicializar el overlay de fade
	if fade_overlay == null:
		create_fade_overlay()
	
	# Asegurar que el overlay esté invisible al inicio
	if fade_overlay:
		fade_overlay.modulate.a = 0.0
		fade_overlay.visible = true
	
	# Buscar las cámaras dentro de los addons
	find_cameras()
	
	# Configurar cámara de transición
	if transition_camera == null:
		create_transition_camera()
	
	# Comenzar en modo FPS
	set_initial_mode("FPS")

func _input(event):
	# Alternar con Tab (configura esto en Project Settings > Input Map)
	if event.is_action_pressed("toggle_camera_mode") and not is_transitioning:
		toggle_mode()

func _process(delta):
	if is_transitioning:
		animate_transition(delta)

# ============= FUNCIONES PRINCIPALES =============

func toggle_mode():
	"""Alterna entre modo FPS y RTS"""
	if current_mode == "FPS":
		start_transition("RTS")
	else:
		start_transition("FPS")

func start_transition(to_mode: String):
	"""Inicia la transición a un modo específico"""
	if is_transitioning:
		return
	
	target_mode = to_mode
	is_transitioning = true
	transition_progress = 0.0
	
	# Desactivar controles de ambos addons
	disable_all_controls()
	
	# Activar la cámara de transición
	transition_camera.make_current()
	
	# Guardar estado inicial
	from_transform = transition_camera.global_transform
	from_fov = transition_camera.fov
	
	# Obtener estado final
	if to_mode == "RTS":
		to_transform = rts_camera.global_transform
		to_fov = rts_camera.fov if rts_camera.fov else 70.0
	else:  # FPS
		to_transform = fps_camera.global_transform
		to_fov = fps_camera.fov if fps_camera.fov else 75.0
	
	# Efecto de fade (opcional)
	if enable_fade_effect:
		fade_out()

func animate_transition(delta: float):
	"""Anima la transición entre cámaras"""
	transition_progress += delta / transition_duration
	
	if transition_progress >= 1.0:
		finish_transition()
		return
	
	# Aplicar easing suave (cubic in-out)
	var t = ease_in_out_cubic(transition_progress)
	
	# Interpolar transformación
	transition_camera.global_transform = from_transform.interpolate_with(to_transform, t)
	
	# Interpolar FOV
	transition_camera.fov = lerp(from_fov, to_fov, t)

func finish_transition():
	"""Completa la transición y activa el modo destino"""
	is_transitioning = false
	current_mode = target_mode
	
	# Asegurar posición final exacta
	transition_camera.global_transform = to_transform
	transition_camera.fov = to_fov
	
	# Activar el addon correspondiente
	if current_mode == "FPS":
		activate_fps_mode()
	else:
		activate_rts_mode()
	
	# Fade in (opcional)
	if enable_fade_effect:
		fade_in()

# ============= CONTROL DE ADDONS =============

func activate_fps_mode():
	"""Activa el controlador FPS y desactiva RTS"""
	# Hacer que la cámara FPS sea la activa
	fps_camera.make_current()
	
	# Activar procesamiento del addon FPS (más específico)
	fps_character.set_process_input(true)
	fps_character.set_physics_process(true)
	fps_character.set_process(true)
	
	# Activar también los hijos del FPS character
	for child in fps_character.get_children():
		if child.has_method("set_process_input"):
			child.set_process_input(true)
		if child.has_method("set_process"):
			child.set_process(true)
	
	# Desactivar RTS
	rts_camera_node.set_process_input(false)
	rts_camera_node.set_process(false)
	
	# Capturar el mouse para FPS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func activate_rts_mode():
	"""Activa la cámara RTS y desactiva FPS"""
	# Hacer que la cámara RTS sea la activa
	rts_camera.make_current()
	
	# Activar procesamiento del addon RTS
	if rts_camera_node.has_method("set_process_input"):
		rts_camera_node.set_process_input(true)
	if rts_camera_node.has_method("set_process"):
		rts_camera_node.set_process(true)
	
	# Desactivar FPS
	if fps_character.has_method("set_process_input"):
		fps_character.set_process_input(false)
	if fps_character.has_method("set_physics_process"):
		fps_character.set_physics_process(false)
	if fps_character.has_method("set_process"):
		fps_character.set_process(false)
	
	# Liberar el mouse para RTS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func disable_all_controls():
	"""Desactiva todos los controles durante la transición"""
	# Desactivar FPS y sus hijos
	fps_character.set_process_input(false)
	fps_character.set_physics_process(false)
	
	for child in fps_character.get_children():
		if child.has_method("set_process_input"):
			child.set_process_input(false)
		if child.has_method("set_process"):
			child.set_process(false)
	
	# Desactivar RTS
	rts_camera_node.set_process_input(false)
	rts_camera_node.set_process(false)

func set_initial_mode(mode: String):
	"""Configura el modo inicial sin transición"""
	current_mode = mode
	
	# Asegurar que la transition_camera copie el transform inicial
	if mode == "FPS" and fps_camera:
		transition_camera.global_transform = fps_camera.global_transform
		transition_camera.fov = fps_camera.fov if fps_camera.fov else 75.0
	elif mode == "RTS" and rts_camera:
		transition_camera.global_transform = rts_camera.global_transform
		transition_camera.fov = rts_camera.fov if rts_camera.fov else 70.0
	
	# Activar el modo correspondiente
	if mode == "FPS":
		activate_fps_mode()
	else:
		activate_rts_mode()

# ============= BÚSQUEDA DE CÁMARAS =============

func find_cameras():
	"""Encuentra las cámaras dentro de los addons automáticamente"""
	# Buscar cámara FPS
	if fps_character:
		fps_camera = find_camera_in_node(fps_character)
		if fps_camera == null:
			push_error("No se encontró cámara en el addon FPS")
	
	# La cámara RTS es directamente el nodo
	if rts_camera_node and rts_camera_node is Camera3D:
		rts_camera = rts_camera_node
	else:
		push_error("El nodo RTS no es una Camera3D")

func find_camera_in_node(node: Node) -> Camera3D:
	"""Busca recursivamente una Camera3D en un nodo"""
	if node is Camera3D:
		return node
	
	for child in node.get_children():
		if child is Camera3D:
			return child
		var found = find_camera_in_node(child)
		if found:
			return found
	
	return null

# ============= EFECTOS VISUALES =============

func create_fade_overlay():
	"""Crea el overlay de fade si no existe"""
	var canvas = CanvasLayer.new()
	canvas.name = "CanvasLayer"
	canvas.layer = 100
	add_child(canvas)
	
	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = Color.BLACK
	fade_overlay.modulate.a = 0.0
	
	# Configurar anclajes para cubrir toda la pantalla
	fade_overlay.anchor_left = 0.0
	fade_overlay.anchor_top = 0.0
	fade_overlay.anchor_right = 1.0
	fade_overlay.anchor_bottom = 1.0
	
	# Resetear offsets
	fade_overlay.offset_left = 0.0
	fade_overlay.offset_top = 0.0
	fade_overlay.offset_right = 0.0
	fade_overlay.offset_bottom = 0.0
	
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(fade_overlay)

func fade_out():
	"""Fade a negro"""
	if fade_overlay:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(fade_overlay, "modulate:a", 0.3, transition_duration * 0.4)

func fade_in():
	"""Fade desde negro"""
	if fade_overlay:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(fade_overlay, "modulate:a", 0.0, transition_duration * 0.6)

func create_transition_camera():
	"""Crea la cámara de transición si no existe"""
	transition_camera = Camera3D.new()
	transition_camera.name = "TransitionCamera3D"
	add_child(transition_camera)

# ============= FUNCIONES DE EASING =============

func ease_in_out_cubic(t: float) -> float:
	"""Easing cubic suave para transiciones profesionales"""
	if t < 0.5:
		return 4.0 * t * t * t
	else:
		var f = (2.0 * t) - 2.0
		return 0.5 * f * f * f + 1.0

# ============= API PÚBLICA =============

func set_mode(mode: String):
	"""API pública para cambiar de modo programáticamente"""
	if mode != current_mode and not is_transitioning:
		start_transition(mode)

func get_current_mode() -> String:
	"""Obtiene el modo actual"""
	return current_mode

func is_in_transition() -> bool:
	"""Verifica si hay una transición en curso"""
	return is_transitioning
