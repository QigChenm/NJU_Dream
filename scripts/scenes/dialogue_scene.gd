# dialogue_scene.gd
extends Control

# ================= 信号 =================
signal continue_pressed
signal choice_selected(choice_id: int)

# ================= 属性 =================
@export var custom_font: Font

# ---------- UI 节点引用 ----------
@onready var background: TextureRect = $Background
@onready var char_left: CharacterDisplay = $SpriteLeft
@onready var char_right: CharacterDisplay = $SpriteRight
@onready var dialogue_box: Panel = $DialogueBox
@onready var portrait: TextureRect = $CharacterNameRect/Portrait
@onready var character_name_rect: TextureRect = $CharacterNameRect
@onready var name_label: Label = $CharacterNameRect/CharacterName
@onready var text_label: RichTextLabel = $DialogueBox/DialogueText
@onready var click_indicator: Label = $DialogueBox/ClickIndicator
@onready var choice_panel: VBoxContainer = $ChoicePanel
@onready var choice_buttons: Array[Button] = [
	$ChoicePanel/Choice1, $ChoicePanel/Choice2, $ChoicePanel/Choice3
]
@onready var background_node: TextureRect = $Background
@onready var weather_layer: Control = $WeatherLayer
@onready var cg_display: TextureRect = $CGLayer/CGDisplay
@onready var save_hint_label: Label = $CGLayer/SaveHint

# ---------- 状态变量 ----------
var is_waiting_for_input: bool = false
var current_choices: Array = []

# 打字机效果
var typewriter_tween: Tween = null
var is_typewriter_playing: bool = false
var _full_text: String = ""
var _typing_speed: float = 0.05

# HUD 与面板实例
var hud_instance: CanvasLayer = null
var save_load_ui_instance: CanvasLayer = null
var save_hint_tween: Tween = null

# 自动模式
var auto_advance_timer: Timer = null
var auto_mode_paused_by_choice: bool = false
var _current_line_recorded: bool = false


# ================= 初始化 =================
func _ready() -> void:
	_init_ui_basics()
	_register_systems()
	_instantiate_hud()
	_instantiate_panels()
	_connect_uimanager_signals()
	_start_game_flow()
	_enable_input()


# ================= 基础 UI 设置 =================
func _init_ui_basics() -> void:
	choice_panel.hide()
	for i in range(choice_buttons.size()):
		choice_buttons[i].pressed.connect(_on_choice_pressed.bind(i + 1))


# ================= 系统注册（舞台、背景、天气、CG、UI元素） =================
func _register_systems() -> void:
	if char_left is CharacterDisplay:
		CharacterManager.register_sprite("left", char_left)
	else:
		print("[DialogueScene] 错误：SpriteLeft 类型不正确！")
	if char_right is CharacterDisplay:
		CharacterManager.register_sprite("right", char_right)
	else:
		print("[DialogueScene] 错误：SpriteRight 类型不正确！")

	if background_node:
		BackgroundManager.register_background(background_node)
		print("[DialogueScene] 背景节点已注册。")
	else:
		print("[DialogueScene] 错误：未找到背景节点！")

	if weather_layer:
		ParticleManager.register_weather_layer(weather_layer)
		print("[DialogueScene] 天气层已注册。")
	else:
		print("[DialogueScene] 错误：未找到 WeatherLayer 节点！")

	if cg_display:
		CGManager.register_cg_display(cg_display)
		print("[DialogueScene] CG显示层已注册。")
	else:
		print("[DialogueScene] 错误：未找到 CG 层节点！")

	UIManager.register_ui_element("CharacterNameRect", character_name_rect)
	UIManager.register_ui_element("DialogueBox", dialogue_box)
	print("[DialogueScene] 核心UI元素已注册。")


# ================= HUD 实例化与按钮绑定 =================
func _instantiate_hud() -> void:
	var hud_scene = load("res://scenes/hud.tscn")
	if not hud_scene:
		return
	hud_instance = hud_scene.instantiate()
	add_child(hud_instance)

	# 获取所有按钮引用
	var settings_btn = hud_instance.get_node_or_null("TopBar/SettingsButton")
	var affection_btn = hud_instance.get_node_or_null("TopBar/AffectionButton")
	var save_btn = hud_instance.get_node_or_null("TopBar/SaveButton")
	var load_btn = hud_instance.get_node_or_null("TopBar/LoadButton")
	var return_btn = hud_instance.get_node_or_null("TopBar/ReturnButton")
	var return_to_menu_btn = hud_instance.get_node_or_null("TopBar/ReturnToMenuButton")
	var home_btn = hud_instance.get_node_or_null("HomeButton")
	var backlog_btn = hud_instance.get_node_or_null("BacklogButton")
	var quick_save_btn = hud_instance.get_node_or_null("QuickSaveButton")
	var gallery_btn = hud_instance.get_node_or_null("GalleryButton")
	var auto_btn = hud_instance.get_node_or_null("AutoButton")

	# 连接信号
	if settings_btn:
		settings_btn.pressed.connect(func(): UIManager.open_panel("SettingsUI"))
	if affection_btn:
		affection_btn.pressed.connect(_on_affection_button_pressed)
	if save_btn:
		save_btn.pressed.connect(_on_save_button_pressed)
	if load_btn:
		load_btn.pressed.connect(_on_load_button_pressed)
	if home_btn:
		home_btn.pressed.connect(_on_home_button_pressed)
	if backlog_btn:
		backlog_btn.pressed.connect(_on_backlog_button_pressed)
	if quick_save_btn:
		quick_save_btn.pressed.connect(_on_quick_save_pressed)
	if auto_btn:
		auto_btn.pressed.connect(_on_auto_button_pressed)
	if gallery_btn:
		gallery_btn.pressed.connect(func(): UIManager.open_panel("GalleryUI"))

	if return_btn:
		UIManager.set_return_button(return_btn)
		return_btn.pressed.connect(UIManager.close_current_panel)
	if return_to_menu_btn:
		UIManager.set_return_to_menu_button(return_to_menu_btn)
		return_to_menu_btn.pressed.connect(_on_return_to_menu_pressed)

	# 将所有功能按钮注册到 UIManager（以便统一显隐管理）
	var all_buttons: Array[Button] = []
	for btn in [settings_btn, auto_btn, gallery_btn, quick_save_btn, backlog_btn, home_btn, affection_btn, save_btn, load_btn]:
		if btn:
			all_buttons.append(btn)
	UIManager.register_hud_action_buttons(all_buttons)


# ================= 面板实例化与注册 =================
func _instantiate_panels() -> void:
	_load_and_register("AffectionUI", "res://scenes/affection_ui.tscn")
	_load_and_register("SaveLoadUI", "res://scenes/save_load_ui.tscn", func(panel): save_load_ui_instance = panel)
	_load_and_register("SettingsUI", "res://scenes/settings_ui.tscn")
	_load_and_register("BacklogUI", "res://scenes/backlog_ui.tscn")
	_load_and_register("GalleryUI", "res://scenes/gallery_ui.tscn", func(panel): panel.custom_font = custom_font)


func _load_and_register(panel_name: String, scene_path: String, callback: Callable = Callable()) -> void:
	var scene = load(scene_path)
	if not scene:
		return
	var instance = scene.instantiate()
	add_child(instance)
	UIManager.register_panel(panel_name, instance)
	if callback.is_valid():
		callback.call(instance)


# ================= UIManager 信号连接 =================
func _connect_uimanager_signals() -> void:
	if not UIManager.has_signal("panel_opened"):
		return
	UIManager.panel_opened.connect(_on_panel_opened)
	UIManager.panel_closed.connect(_on_panel_closed)


# ================= 启动游戏流程 =================
func _start_game_flow() -> void:
	if GameManager.open_settings_on_load:
		GameManager.open_settings_on_load = false
		call_deferred("_open_settings_from_menu")
	elif SaveManager.continue_mode:
		SaveManager.continue_mode = false
		call_deferred("_open_load_panel_on_continue")
	else:
		if GameManager.current_scene == "":
			GameManager.start_new_game()
		DialogueManager.start_dialogue()


# ================= 启用输入 =================
func _enable_input() -> void:
	set_process_input(true)


# ================= 对话显示 =================
func display_dialogue(data: Dictionary) -> void:
	_current_line_recorded = false
	choice_panel.hide()
	_kill_typewriter()

	# 更新角色名与头像
	var character = data.get("character", "")
	var display_name = _resolve_character_name(character)
	name_label.text = display_name
	if character == "":
		character_name_rect.hide()
		portrait.hide()
	else:
		character_name_rect.show()
		if GameManager.character_database.has(character):
			portrait.texture = GameManager.character_database[character].portrait
			portrait.show()

	# 启动打字机动画
	_full_text = data.get("text", "")
	text_label.text = _full_text
	text_label.visible_characters = 0

	var speed = data.get("speed", GameManager.text_speed)
	var total_chars = _full_text.length()
	var duration = total_chars * speed
	is_typewriter_playing = true

	typewriter_tween = create_tween()
	typewriter_tween.tween_property(text_label, "visible_characters", total_chars, duration)
	typewriter_tween.tween_callback(func():
		is_typewriter_playing = false
		if GameManager.is_auto_mode:
			_start_auto_timer()
			click_indicator.hide()
		else:
			_stop_auto_timer()
			is_waiting_for_input = true
			click_indicator.show()
		_record_dialogue_history(display_name)
	)

	dialogue_box.show()
	text_label.show()


func _resolve_character_name(character: String) -> String:
	if character != "" and GameManager.character_database.has(character):
		return GameManager.character_database[character].display_name
	return character


func _kill_typewriter() -> void:
	if typewriter_tween and typewriter_tween.is_running():
		typewriter_tween.kill()
	is_typewriter_playing = false
	if auto_advance_timer:
		auto_advance_timer.stop()
		auto_advance_timer.queue_free()
		auto_advance_timer = null


func _record_dialogue_history(display_name: String) -> void:
	if _current_line_recorded or not GameManager:
		return
	_current_line_recorded = true
	GameManager.dialogue_history.append({
		"character": display_name,
		"text": _full_text
	})


# ================= 选项显示 =================
func display_choices(choices: Array) -> void:
	_pause_auto_for_choices()
	is_waiting_for_input = false
	click_indicator.hide()
	current_choices = choices

	for i in range(choice_buttons.size()):
		if i < choices.size():
			choice_buttons[i].text = choices[i].get("text", "")
			choice_buttons[i].disabled = false
			choice_buttons[i].mouse_filter = Control.MOUSE_FILTER_STOP
			choice_buttons[i].visible = true
			choice_buttons[i].modulate.a = 1.0
			choice_buttons[i].scale = Vector2.ONE
		else:
			choice_buttons[i].visible = false

	choice_panel.show()
	choice_panel.z_index = 10
	choice_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# 轻微弹入动画
	for i in range(min(choices.size(), choice_buttons.size())):
		var btn = choice_buttons[i]
		var t = create_tween()
		t.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.1)
		t.tween_property(btn, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT)


func _pause_auto_for_choices() -> void:
	if not GameManager.is_auto_mode:
		return
	auto_mode_paused_by_choice = true
	GameManager.is_auto_mode = false
	GameManager.auto_mode_changed.emit(false)
	_stop_auto_timer()
	if hud_instance:
		var btn = hud_instance.get_node_or_null("AutoButton")
		if btn:
			btn.text = "自动: OFF"
			btn.modulate = Color.WHITE


# ================= 选项点击 =================
func _on_choice_pressed(choice_id: int) -> void:
	_record_choice(choice_id)
	choice_panel.hide()
	choice_selected.emit(choice_id)
	_restore_auto_after_choice()


func _record_choice(choice_id: int) -> void:
	var choice_text = ""
	for c in current_choices:
		if str(c.get("id", "")) == str(choice_id):
			choice_text = c.get("text", "")
			break
	if choice_text != "":
		GameManager.dialogue_history.append({
			"character": "玩家",
			"text": choice_text
		})


func _restore_auto_after_choice() -> void:
	if not auto_mode_paused_by_choice:
		return
	auto_mode_paused_by_choice = false
	GameManager.is_auto_mode = true
	GameManager.auto_mode_changed.emit(true)
	if hud_instance:
		var btn = hud_instance.get_node_or_null("AutoButton")
		if btn:
			btn.text = "自动: ON"
			btn.modulate = Color.GREEN


# ================= 自动模式核心 =================
func _on_auto_button_pressed() -> void:
	GameManager.is_auto_mode = !GameManager.is_auto_mode
	GameManager.auto_mode_changed.emit(GameManager.is_auto_mode)
	auto_mode_paused_by_choice = false
	_stop_auto_timer()

	if hud_instance:
		var btn = hud_instance.get_node_or_null("AutoButton")
		if btn:
			if GameManager.is_auto_mode:
				btn.text = "自动: ON"
				btn.modulate = Color.GREEN
				if is_waiting_for_input:
					_start_auto_timer()
			else:
				btn.text = "自动: OFF"
				btn.modulate = Color.WHITE
				if not is_typewriter_playing and not is_waiting_for_input:
					is_waiting_for_input = true
					click_indicator.show()


func _start_auto_timer() -> void:
	_stop_auto_timer()
	if not GameManager.is_auto_mode:
		return
	auto_advance_timer = Timer.new()
	add_child(auto_advance_timer)
	auto_advance_timer.one_shot = true
	var auto_delay = GameManager.get_variable("auto_speed")
	if auto_delay == null:
		auto_delay = 2.0 / GameManager.auto_speed if GameManager.auto_speed > 0 else 2.0
	auto_advance_timer.wait_time = auto_delay
	auto_advance_timer.timeout.connect(_on_auto_advance_timeout)
	auto_advance_timer.start()
	click_indicator.hide()


func _stop_auto_timer() -> void:
	if auto_advance_timer:
		auto_advance_timer.stop()
		auto_advance_timer.queue_free()
		auto_advance_timer = null


func _on_auto_advance_timeout() -> void:
	if not GameManager.is_auto_mode:
		return
	continue_pressed.emit()


# ================= 继续与输入处理 =================
func _gui_input(event: InputEvent) -> void:
	if get_tree().paused or not is_waiting_for_input:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_continue_clicked()
		return
	if event.is_action_pressed("ui_accept"):
		accept_event()
		_on_continue_clicked()
		return


func _on_continue_clicked() -> void:
	is_waiting_for_input = false
	click_indicator.hide()
	_stop_auto_timer()
	continue_pressed.emit()


# ================= HUD 按钮回调 =================
func _on_affection_button_pressed() -> void: UIManager.open_panel("AffectionUI")
func _on_save_button_pressed() -> void: _open_save_load("save")
func _on_load_button_pressed() -> void: _open_save_load("load")
func _on_backlog_button_pressed() -> void:
	var panel = UIManager._panels.get("BacklogUI")
	if panel and panel.has_method("refresh_history"):
		panel.refresh_history()
	UIManager.open_panel("BacklogUI")

func _on_quick_save_pressed() -> void:
	SaveManager.auto_save_to_latest_slot()
	show_save_hint()

func _open_save_load(mode: String) -> void:
	if save_load_ui_instance and save_load_ui_instance.has_method("set_mode"):
		save_load_ui_instance.set_mode(mode)
	UIManager.open_panel("SaveLoadUI")


# ================= 返回主界面流程 =================
func _on_home_button_pressed() -> void:
	if has_node("HomeConfirmDialog"):
		get_node("HomeConfirmDialog").popup_centered()
		return
	_create_home_confirm_dialog()
	get_node("HomeConfirmDialog").popup_centered()


func _create_home_confirm_dialog() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.name = "HomeConfirmDialog"
	dialog.title = "提示"
	dialog.dialog_text = "是否保存当前游戏进度？"
	dialog.ok_button_text = "是（保存）"
	dialog.cancel_button_text = "否（不保存）"
	dialog.process_mode = PROCESS_MODE_ALWAYS
	dialog.min_size = Vector2(450, 200)

	if custom_font:
		dialog.add_theme_font_override("title_font", custom_font)
	dialog.add_theme_font_size_override("title_font_size", 30)
	dialog.add_theme_constant_override("title_margin_top", 15)

	var content_label = dialog.get_label()
	if content_label:
		if custom_font:
			content_label.add_theme_font_override("font", custom_font)
		content_label.add_theme_font_size_override("font_size", 30)

	var ok_btn = dialog.get_ok_button()
	var cancel_btn = dialog.get_cancel_button()
	if custom_font:
		ok_btn.add_theme_font_override("font", custom_font)
		cancel_btn.add_theme_font_override("font", custom_font)
	ok_btn.add_theme_font_size_override("font_size", 30)
	cancel_btn.add_theme_font_size_override("font_size", 30)

	var button_container = ok_btn.get_parent()
	if button_container is Container:
		button_container.add_theme_constant_override("separation", 10)

	for btn in [ok_btn, cancel_btn]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

	dialog.confirmed.connect(_on_home_save_confirmed)
	dialog.canceled.connect(_on_home_cancel_confirmed)
	add_child(dialog)


func _on_home_save_confirmed() -> void:
	SaveManager.auto_save_to_latest_slot()
	await get_tree().create_timer(0.5).timeout
	_return_to_main_menu()


func _on_home_cancel_confirmed() -> void:
	_return_to_main_menu()


func _on_return_to_menu_pressed() -> void:
	UIManager.close_current_panel()
	await get_tree().process_frame
	UIManager.hide_return_to_menu_button()
	SaveManager.continue_mode = false
	if get_tree().paused:
		get_tree().paused = false
	clean_up_all_ui()
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	if AudioManager:
		AudioManager.stop_all()
	if ScriptEngine:
		ScriptEngine.hard_reset()
	if has_node("/root/ScriptEngine"):
		get_node("/root/ScriptEngine").stop_execution()
		get_node("/root/ScriptEngine").hard_reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ================= 存档与读档 UI =================
func _open_load_panel_on_continue() -> void:
	if save_load_ui_instance and save_load_ui_instance.has_method("set_mode"):
		save_load_ui_instance.set_mode("load")
	UIManager.open_panel("SaveLoadUI")
	UIManager.show_return_to_menu_button()


func _open_settings_from_menu() -> void:
	UIManager.open_panel("SettingsUI")
	UIManager.show_return_to_menu_button()


# ================= 面板回调 =================
func _on_panel_opened(_panel_name: String) -> void: pass
func _on_panel_closed(_panel_name: String) -> void: pass


# ================= 对话状态存取（存档用） =================
func get_dialogue_state() -> Dictionary:
	return {
		"character": name_label.text,
		"text": _full_text if is_typewriter_playing else text_label.text,
		"choices": current_choices if choice_panel.visible else []
	}


func restore_dialogue_state(data: Dictionary) -> void:
	var character: String = data.get("character", "")
	var text: String = data.get("text", "")
	var choices: Array = data.get("choices", [])

	_full_text = text
	text_label.text = text
	text_label.visible_characters = text.length()
	name_label.text = character
	if character == "":
		character_name_rect.hide()
	else:
		character_name_rect.show()

	if choices.size() > 0:
		display_choices(choices)
	else:
		choice_panel.hide()
		is_waiting_for_input = true
		click_indicator.show()

	dialogue_box.visible = true
	text_label.visible = true
	dialogue_box.modulate.a = 1.0
	text_label.modulate.a = 1.0
	if character != "":
		character_name_rect.visible = true
		character_name_rect.modulate.a = 1.0
	click_indicator.visible = true


# ================= UI 截图与清理 =================
func hide_all_ui_for_screenshot() -> void:
	if hud_instance:
		hud_instance.visible = false


func show_all_ui() -> void:
	if hud_instance:
		hud_instance.visible = true


func clean_up_all_ui() -> void:
	print("[DialogueScene] 正在清理所有动态UI...")
	if hud_instance and is_instance_valid(hud_instance):
		hud_instance.queue_free()
		hud_instance = null
	if save_load_ui_instance and is_instance_valid(save_load_ui_instance):
		save_load_ui_instance.queue_free()
		save_load_ui_instance = null
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		if gm.affection_ui_instance and is_instance_valid(gm.affection_ui_instance):
			gm.affection_ui_instance.queue_free()
			gm.affection_ui_instance = null
	if has_node("HomeConfirmDialog"):
		var dialog = get_node("HomeConfirmDialog")
		if is_instance_valid(dialog):
			dialog.queue_free()
	print("[DialogueScene] 动态UI清理完成。")


func show_save_hint() -> void:
	if not save_hint_label:
		return
	if save_hint_tween and save_hint_tween.is_valid():
		save_hint_tween.kill()
	save_hint_label.text = "✅ 已保存"
	save_hint_label.modulate.a = 1.0
	save_hint_label.visible = true
	save_hint_tween = create_tween()
	save_hint_tween.tween_interval(1.5)
	save_hint_tween.tween_property(save_hint_label, "modulate:a", 0.0, 0.5)
	save_hint_tween.tween_callback(func(): save_hint_label.visible = false)
