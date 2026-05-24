# background_manager.gd
extends Node

# ================= 信号 =================
signal background_changed(new_bg_id: String)
signal fade_out_finished
signal fade_in_finished
signal transition_finished

# ================= 常量 =================
const LOCATION_BAR_HEIGHT: float = 100.0
const LOCATION_BAR_TOP_MARGIN: float = 540.0
const LOCATION_FONT_SIZE: int = 40
const LOCATION_BAR_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)

# ================= 属性 =================
var background_database: Dictionary = {}
var current_background_id: String = ""
var _background_layer: TextureRect = null
var _transition_canvas: CanvasLayer = null
var transition_overlay: ColorRect = null
var tween: Tween

# ================= 初始化 =================
func _ready() -> void:
	_load_background_database()
	_create_transition_canvas()


func _create_transition_canvas() -> void:
	_transition_canvas = CanvasLayer.new()
	_transition_canvas.name = "TransitionCanvas"
	_transition_canvas.layer = 100
	call_deferred("_add_canvas_to_scene")


func _add_canvas_to_scene() -> void:
	var root = get_tree().root
	if root:
		root.add_child(_transition_canvas)
		_create_transition_overlay()
	else:
		await get_tree().process_frame
		_add_canvas_to_scene()


func _create_transition_overlay() -> void:
	if transition_overlay and is_instance_valid(transition_overlay):
		return
	if not _transition_canvas or not is_instance_valid(_transition_canvas):
		_create_transition_canvas()
		return

	var overlay_scene = load("res://scenes/transition_overlay.tscn")
	if overlay_scene:
		transition_overlay = overlay_scene.instantiate()
	else:
		transition_overlay = ColorRect.new()
		transition_overlay.color = Color.BLACK
		transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_transition_canvas.add_child(transition_overlay)
	transition_overlay.modulate.a = 0.0
	transition_overlay.hide()


# ================= 背景数据库加载 =================
func _load_background_database() -> void:
	var dir = DirAccess.open("res://assets/backgrounds/tres")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with("_data.tres"):
				var resource = load("res://assets/backgrounds/tres/" + file_name)
				if resource is BackgroundData and resource.background_id != "":
					background_database[resource.background_id] = resource
			file_name = dir.get_next()
		dir.list_dir_end()
		print("[BackgroundManager] 背景数据库加载完成。")


func register_background(node: TextureRect) -> void:
	_background_layer = node
	print("[BackgroundManager] 背景层已注册。")


# ================= 背景切换（含转场动画） =================
func change_background(bg_id: String, transition_type: String = "fade", duration: float = 0.5) -> void:
	if not background_database.has(bg_id):
		transition_finished.emit.call_deferred()
		return
	if not _background_layer:
		transition_finished.emit.call_deferred()
		return
	if current_background_id == bg_id:
		transition_finished.emit.call_deferred()
		return

	var bg_data: BackgroundData = background_database[bg_id]
	_play_transition_out(transition_type, duration, bg_data)


func _play_transition_out(type: String, duration: float, bg_data: BackgroundData) -> void:
	if not transition_overlay or not is_instance_valid(transition_overlay):
		_create_transition_overlay()
		if not transition_overlay:
			_background_layer.texture = bg_data.texture
			current_background_id = bg_data.background_id
			transition_finished.emit.call_deferred()
			return

	if tween:
		tween.kill()
	tween = create_tween()

	transition_overlay.modulate.a = 0.0
	transition_overlay.show()
	tween.tween_property(transition_overlay, "modulate:a", 1.0, duration)
	tween.tween_callback(_on_fadeout_complete.bind(type, duration, bg_data))


func _on_fadeout_complete(type: String, duration: float, bg_data: BackgroundData) -> void:
	if _background_layer:
		_background_layer.texture = bg_data.texture
	current_background_id = bg_data.background_id
	_play_transition_in(type, duration)


func _play_transition_in(_type: String, duration: float) -> void:
	if not transition_overlay or not is_instance_valid(transition_overlay):
		transition_finished.emit.call_deferred()
		return

	if tween:
		tween.kill()
	tween = create_tween()

	transition_overlay.modulate.a = 1.0
	tween.tween_property(transition_overlay, "modulate:a", 0.0, duration)
	tween.tween_callback(_on_fadein_complete)


func _on_fadein_complete() -> void:
	if transition_overlay and is_instance_valid(transition_overlay):
		transition_overlay.hide()
	print("[BackgroundManager] 背景切换动画完成。")

	var bg_data = background_database.get(current_background_id)
	if bg_data and not bg_data.location_name.is_empty():
		_show_location_name(bg_data.location_name, func():
			transition_finished.emit.call_deferred()
			background_changed.emit.call_deferred(current_background_id)
		)
	else:
		transition_finished.emit.call_deferred()
		background_changed.emit.call_deferred(current_background_id)


# ================= 通用转场（供 CG 等系统调用） =================
func perform_fade_out(duration: float = 0.5) -> void:
	if not transition_overlay or not is_instance_valid(transition_overlay):
		_create_transition_overlay()
		if not transition_overlay:
			fade_out_finished.emit.call_deferred()
			return

	if tween:
		tween.kill()
	tween = create_tween()
	transition_overlay.modulate.a = 0.0
	transition_overlay.show()
	tween.tween_property(transition_overlay, "modulate:a", 1.0, duration)
	tween.tween_callback(_on_generic_fade_out_complete)


func _on_generic_fade_out_complete() -> void:
	fade_out_finished.emit.call_deferred()


func perform_fade_in(duration: float = 0.5) -> void:
	if not transition_overlay or not is_instance_valid(transition_overlay):
		_create_transition_overlay()
		if not transition_overlay:
			fade_in_finished.emit.call_deferred()
			return

	if tween:
		tween.kill()
	tween = create_tween()
	transition_overlay.modulate.a = 1.0
	transition_overlay.show()
	tween.tween_property(transition_overlay, "modulate:a", 0.0, duration)
	tween.tween_callback(_on_generic_fade_in_complete)


func _on_generic_fade_in_complete() -> void:
	if transition_overlay and is_instance_valid(transition_overlay):
		transition_overlay.hide()
	fade_in_finished.emit.call_deferred()


# ================= 场景名称提示条 =================
func _show_location_name(location_name: String, on_finished: Callable = Callable()) -> void:
	if location_name.is_empty():
		return

	var scene_root = get_tree().current_scene
	if not scene_root:
		return

	var canvas = CanvasLayer.new()
	canvas.name = "LocationBarCanvas"
	canvas.layer = 50
	scene_root.add_child(canvas)

	var container = Control.new()
	container.name = "LocationBarContainer"
	canvas.add_child(container)

	var viewport_size = get_viewport().size
	var bar_width = 1920
	var bar_height = LOCATION_BAR_HEIGHT
	container.position = Vector2(0, LOCATION_BAR_TOP_MARGIN)
	container.size = Vector2(bar_width, bar_height)

	var bg_bar = ColorRect.new()
	bg_bar.name = "BgBar"
	bg_bar.color = LOCATION_BAR_COLOR
	bg_bar.position = Vector2.ZERO
	bg_bar.size = Vector2(bar_width, bar_height)
	container.add_child(bg_bar)

	var label = Label.new()
	label.name = "LocationLabel"
	label.text = location_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", LOCATION_FONT_SIZE)

	var bg_data = background_database.get(current_background_id)
	if bg_data and bg_data.get("location_font"):  # 避免属性缺失报错
		label.add_theme_font_override("font", bg_data.location_font)

	label.add_theme_color_override("font_color", Color.WHITE)
	label.position = Vector2.ZERO
	label.size = Vector2(bar_width, bar_height)
	container.add_child(label)

	bg_bar.size.x = 0.0
	label.modulate.a = 0.0

	var tween = create_tween()
	tween.set_parallel(false)
	tween.tween_property(bg_bar, "size:x", bar_width, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.2)
	tween.tween_property(bg_bar, "size:x", 0.0, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.3)

	tween.tween_callback(func():
		if is_instance_valid(canvas):
			canvas.queue_free()
		if on_finished.is_valid():
			on_finished.call()
	)


# ================= 读档专用（无动画） =================
func set_background(bg_id: String) -> void:
	if not background_database.has(bg_id):
		print("[BackgroundManager] 错误：背景ID '%s' 不存在。" % bg_id)
		return
	if not _background_layer:
		print("[BackgroundManager] 错误：背景层未注册，无法设置背景。")
		return

	var bg_data: BackgroundData = background_database[bg_id]
	_background_layer.texture = bg_data.texture
	current_background_id = bg_id
	print("[BackgroundManager] 背景已直接设置为：%s" % bg_data.display_name)

# ================= 废弃函数区？ =================
func _retry_change_background(bg_id: String, transition_type: String, duration: float) -> void:
	change_background(bg_id, transition_type, duration)
