# character_display.gd
class_name CharacterDisplay
extends TextureRect

# ================= 信号 =================
signal action_finished()
signal entrance_finished
signal exit_finished

# ================= 常量 =================
const CODE_ACTIONS = {
	"breathe": {"type": "loop", "duration": 1.8, "scale_min": 0.99, "scale_max": 1.01},
	"shake":   {"type": "once",  "duration": 0.4, "amplitude": 10},
	"bounce":  {"type": "once",  "duration": 0.5, "jump_height": -20},
	"nod":     {"type": "once",  "duration": 0.6, "move_y": -10},
	"step_back":{"type": "once",  "duration": 0.5, "move_x": 15},
	"shrug":   {"type": "once",  "duration": 0.6, "move_y": -8, "amplitude": 4},
}

# ================= 属性 =================
var character_data: CharacterData = null
var current_position: String = "left"
var current_expression: String = ""

# ---------- 动画相关 ----------
var tween: Tween = null
var action_tween: Tween = null
var breathe_tween: Tween = null
var blink_tween: Tween = null
var _entrance_tween: Tween = null
var _exit_tween: Tween = null

# ---------- 动图系统 ----------
var animated_sprite: AnimatedSprite2D = null
var anim_frames: SpriteFrames = null

# ---------- 状态 ----------
var current_action: String = ""
var is_idle_active: bool = false
var blink_timer: Timer = null


# ================= 初始化 =================
func initialize(data: CharacterData, pos: String = "left", initial_expression: String = "default") -> void:
	character_data = data
	current_position = pos
	kill_all_animations()

	var expr_id = initial_expression if data.expressions.has(initial_expression) else "default"
	if data.expressions.has(expr_id):
		texture = data.expressions[expr_id]
		current_expression = expr_id
		modulate.a = 1.0
	else:
		texture = null
	show()
	_setup_animated_sprite()
	start_idle()


func _setup_animated_sprite() -> void:
	if not character_data or not character_data.action_animations:
		if animated_sprite:
			animated_sprite.visible = false
		visible = true
		return

	if not animated_sprite:
		animated_sprite = AnimatedSprite2D.new()
		animated_sprite.name = "AnimSprite"
		add_child(animated_sprite)
		visible = false

	if character_data.action_animations.is_empty():
		return
	var first_key = character_data.action_animations.keys()[0]
	anim_frames = character_data.action_animations[first_key]
	if anim_frames:
		animated_sprite.sprite_frames = anim_frames


# ================= 表情切换 =================
func set_expression(expression_id: String) -> void:
	if not character_data:
		return

	# 容错：表情不存在时回退到 default
	if not character_data.expressions.has(expression_id):
		if not character_data.expressions.has("default"):
			return
		expression_id = "default"

	if current_expression == expression_id:
		return

	if tween and tween.is_running():
		tween.kill()
		tween = null

	var tex = character_data.expressions[expression_id]
	if not tex:
		return

	tween = create_tween()
	tween.set_parallel(false)
	tween.tween_method(Callable(self, "_set_alpha"), 1.0, 0.0, 0.15)
	tween.tween_callback(Callable(self, "_swap_texture").bind(tex, expression_id))
	tween.tween_method(Callable(self, "_set_alpha"), 0.0, 1.0, 0.15)
	tween.tween_callback(func():
		modulate.a = 1.0
		if animated_sprite:
			animated_sprite.modulate.a = 1.0
		tween = null
	)


func _set_alpha(value: float) -> void:
	modulate.a = value
	if animated_sprite:
		animated_sprite.modulate.a = value


func _swap_texture(new_texture: Texture2D, expression_id: String) -> void:
	texture = new_texture
	current_expression = expression_id


# ================= 动作播放 =================
func play_action(action_name: String) -> void:
	if not character_data:
		return
	if action_name == "breathe":
		start_idle()
		action_finished.emit()
		return

	if anim_frames and anim_frames.has_animation(action_name):
		_play_anim_action(action_name)
	else:
		_play_code_action(action_name)


func _play_anim_action(action_name: String) -> void:
	if not animated_sprite:
		return
	animated_sprite.stop()
	stop_idle()
	animated_sprite.play(action_name)
	if not anim_frames.get_animation_loop_mode(action_name) == Animation.LOOP_LINEAR:
		await animated_sprite.animation_finished
		start_idle()


func _play_code_action(action_name: String) -> void:
	if not CODE_ACTIONS.has(action_name):
		action_finished.emit()
		return

	_stop_current_action()
	stop_idle()
	var config = CODE_ACTIONS[action_name]
	current_action = action_name
	action_tween = create_tween()
	match action_name:
		"shake":
			_start_shake(config)
		"bounce":
			_start_bounce(config)
		"nod":
			_start_nod(config)
		"step_back":
			_start_step_back(config)
		"shrug":
			_start_shrug(config)


func _on_action_finished() -> void:
	current_action = ""
	start_idle()
	action_finished.emit()


func _stop_current_action() -> void:
	if action_tween and action_tween.is_running():
		action_tween.kill()
	current_action = ""


# ================= 常态循环 =================
func start_idle() -> void:
	if is_idle_active:
		return
	is_idle_active = true
	if anim_frames and anim_frames.has_animation("breathe"):
		animated_sprite.play("breathe")
	else:
		_play_code_breathe()


func _play_code_breathe() -> void:
	breathe_tween = create_tween()
	breathe_tween.set_loops()
	var original_scale = scale
	var original_pos = position
	breathe_tween.tween_property(self, "position:y", original_pos.y - 1, 1.6)
	breathe_tween.parallel().tween_property(self, "scale", Vector2(1.021, 1.01), 1.6)
	breathe_tween.tween_property(self, "position:y", original_pos.y + 1, 1.6)
	breathe_tween.parallel().tween_property(self, "scale", Vector2(0.99, 0.99), 1.6)


func stop_idle() -> void:
	is_idle_active = false
	if animated_sprite and anim_frames:
		animated_sprite.stop()
	if breathe_tween and breathe_tween.is_running():
		breathe_tween.kill()
	breathe_tween = null
	if blink_timer:
		blink_timer.stop()
		blink_timer.queue_free()
		blink_timer = null
	if blink_tween and blink_tween.is_running():
		blink_tween.kill()
	blink_tween = null


# ================= 辅助 =================
func hide_character() -> void:
	kill_all_animations()
	hide()


func kill_all_animations() -> void:
	if tween and tween.is_running():
		tween.kill()
	if action_tween and action_tween.is_running():
		action_tween.kill()
	if breathe_tween and breathe_tween.is_running():
		breathe_tween.kill()
	if blink_tween and blink_tween.is_running():
		blink_tween.kill()
	if blink_timer:
		blink_timer.stop()
		blink_timer.queue_free()
		blink_timer = null
	if animated_sprite:
		animated_sprite.stop()


# ---------- 具体动作实现 ----------
func _start_shake(config: Dictionary) -> void:
	var original_pos = position
	var shake_count = 4
	for i in range(shake_count):
		var dir = 1 if i % 2 == 0 else -1
		action_tween.tween_property(self, "position:x", original_pos.x + config.amplitude * dir, config.duration / shake_count)
	action_tween.tween_property(self, "position:x", original_pos.x, 0.01)
	action_tween.tween_callback(Callable(self, "_on_action_finished"))


func _start_bounce(config: Dictionary) -> void:
	var original_pos = position
	action_tween.tween_property(self, "position:y", original_pos.y + config.jump_height, 0.2).set_ease(Tween.EASE_OUT)
	action_tween.tween_property(self, "position:y", original_pos.y, 0.3).set_ease(Tween.EASE_IN)
	action_tween.tween_callback(Callable(self, "_on_action_finished"))


func _start_nod(config: Dictionary) -> void:
	var original_pos = position
	action_tween.tween_property(self, "position:y", original_pos.y + config.move_y, 0.2)
	action_tween.tween_property(self, "position:y", original_pos.y, 0.3)
	action_tween.tween_callback(Callable(self, "_on_action_finished"))


func _start_step_back(config: Dictionary) -> void:
	var original_pos = position
	var dir = -1 if current_position == "left" else 1
	action_tween.tween_property(self, "position:x", original_pos.x + config.move_x * dir, 0.25)
	action_tween.tween_property(self, "position:x", original_pos.x, 0.25)
	action_tween.tween_callback(Callable(self, "_on_action_finished"))


func _start_shrug(config: Dictionary) -> void:
	var original_pos = position
	action_tween.tween_property(self, "position:y", original_pos.y + config.move_y, 0.2)
	for i in range(2):
		var dir = 1 if i % 2 == 0 else -1
		action_tween.tween_property(self, "position:x", original_pos.x + config.amplitude * dir, 0.1)
	action_tween.tween_property(self, "position:x", original_pos.x, 0.1)
	action_tween.tween_property(self, "position:y", original_pos.y, 0.2)
	action_tween.tween_callback(Callable(self, "_on_action_finished"))


# ================= 出入场动画 =================
func play_entrance_animation(animation_type: String = "fade", duration: float = 0.6) -> void:
	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = create_tween()
	visible = true
	modulate.a = 0.0

	match animation_type:
		"none":
			visible = true
			modulate.a = 1.0
			if animated_sprite:
				animated_sprite.visible = false
			entrance_finished.emit()

		"slide_left":
			var target_pos = position
			position.x = -size.x
			_entrance_tween.set_parallel(true)
			_entrance_tween.tween_property(self, "position:x", target_pos.x, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
			_entrance_tween.tween_property(self, "modulate:a", 1.0, duration * 0.8)
			_entrance_tween.set_parallel(false)
			_entrance_tween.tween_callback(func(): entrance_finished.emit())

		"slide_right":
			var target_pos = position
			position.x = get_viewport_rect().size.x
			_entrance_tween.set_parallel(true)
			_entrance_tween.tween_property(self, "position:x", target_pos.x, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
			_entrance_tween.tween_property(self, "modulate:a", 1.0, duration * 0.8)
			_entrance_tween.set_parallel(false)
			_entrance_tween.tween_callback(func(): entrance_finished.emit())

		_:
			_entrance_tween.tween_property(self, "modulate:a", 1.0, duration)
			_entrance_tween.tween_callback(func(): entrance_finished.emit())


func play_exit_animation(animation_type: String = "fade", duration: float = 0.4) -> void:
	if _exit_tween and _exit_tween.is_valid():
		_exit_tween.kill()
	_exit_tween = create_tween()

	match animation_type:
		"slide_left":
			var target_x = -size.x
			_exit_tween.set_parallel(true)
			_exit_tween.tween_property(self, "position:x", target_x, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
			_exit_tween.tween_property(self, "modulate:a", 0.0, duration * 0.8)
			_exit_tween.set_parallel(false)
			_exit_tween.tween_callback(func():
				hide()
				exit_finished.emit()
			)

		"slide_right":
			var target_x = get_viewport_rect().size.x
			_exit_tween.set_parallel(true)
			_exit_tween.tween_property(self, "position:x", target_x, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
			_exit_tween.tween_property(self, "modulate:a", 0.0, duration * 0.8)
			_exit_tween.set_parallel(false)
			_exit_tween.tween_callback(func():
				hide()
				exit_finished.emit()
			)

		_:
			_exit_tween.tween_property(self, "modulate:a", 0.0, duration)
			_exit_tween.tween_callback(func():
				hide()
				exit_finished.emit()
			)
