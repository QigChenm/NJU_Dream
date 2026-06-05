# settings_ui.gd
extends CanvasLayer

# ================= 节点引用 =================
@onready var text_speed_slider: HSlider = $VBoxContainerL/SpeedContainer/TextSpeedContainer/TextSpeed
@onready var auto_speed_slider: HSlider = $VBoxContainerL/SpeedContainer/AutoSpeedContainer/AutoSpeed
@onready var bgm_volume_slider: HSlider = $VBoxContainerL/VolumeContainer/BGMVolumeContainer/BGMVolume
@onready var sfx_volume_slider: HSlider = $VBoxContainerL/VolumeContainer/SFXVolumeContainer/SFXVolume
@onready var voice_volume_slider: HSlider = $VBoxContainerL/VolumeContainer/VoiceVolumeContainer/VoiceVolume
@onready var fullscreen_check: CheckButton = $VBoxContainerL/FullscreenContainer/Fullscreen
@onready var ui_sound_toggle: CheckButton = $VBoxContainerL/VolumeContainer/SFXContainer/SFXToggle
@onready var clear_save_btn = $VBoxContainerL/LockContainer/ClearSaveContainer/ClearSave
@onready var ai_url_edit = $VBoxContainerR/AIURLContainer/AIBaseURL/LineEdit
@onready var ai_model_edit = $VBoxContainerR/AIURLContainer/AIModel/LineEdit
@onready var ai_key_edit = $VBoxContainerR/AIURLContainer/APIKey/LineEdit
@onready var ai_provider_option: OptionButton = $VBoxContainerR/AIURLContainer/AIBaseURL/ProviderOption
@onready var ai_model_option: OptionButton = $VBoxContainerR/AIURLContainer/AIModel/ModelOption
@onready var ai_refresh_btn: BaseButton = $VBoxContainerR/AIURLContainer/AIModel/RefreshModels
@onready var ollama_model_container: HBoxContainer = $VBoxContainerR/AIURLContainer/OllamaModel
@onready var ollama_model_edit: LineEdit = $VBoxContainerR/AIURLContainer/OllamaModel/LineEdit
@onready var deploy_btn = $VBoxContainerR/AIURLContainer/DeployAI/DeployAIBtn
@onready var ai_enabled_toggle = $VBoxContainerR/AIURLContainer/AIControl/AIEnabledToggle

var _provider_items: Array[String] = []
var _model_items: Array[String] = []
var _is_loading_ai_controls := false
var _model_refresh_request: HTTPRequest = null
var _can_toggle_ai: bool = false

const AI_FIELD_COLOR := Color(0.36078432, 0.75686276, 0.8980392, 1)
const AI_POPUP_BG_COLOR := Color(0.82, 0.96, 0.99, 0.98)
const AI_POPUP_HOVER_COLOR := Color(0.36, 0.76, 0.90, 1.0)

# ================= 初始化 =================
func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_load_settings()
	_connect_signals()

	UIManager.panel_opened.connect(_on_panel_opened)


func _connect_signals() -> void:
	text_speed_slider.value_changed.connect(_on_text_speed_changed)
	auto_speed_slider.value_changed.connect(_on_auto_speed_changed)
	bgm_volume_slider.value_changed.connect(_on_bgm_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	voice_volume_slider.value_changed.connect(_on_voice_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	
	_setup_ai_controls()
	_style_ai_dropdown(ai_provider_option)
	_style_ai_dropdown(ai_model_option)
	ai_key_edit.text_changed.connect(_on_ai_key_changed)
	ollama_model_edit.text_changed.connect(_on_ollama_model_changed)
	ai_provider_option.item_selected.connect(_on_ai_provider_selected)
	ai_model_option.item_selected.connect(_on_ai_model_selected)
	ai_refresh_btn.pressed.connect(_on_refresh_models_pressed)

	if clear_save_btn:
		clear_save_btn.pressed.connect(_on_reset_unlocks)
	if ui_sound_toggle:
		ui_sound_toggle.toggled.connect(_on_ui_sound_toggled)
	if deploy_btn:
		deploy_btn.pressed.connect(_on_deploy_ai_pressed)
	if ai_enabled_toggle:
		ai_enabled_toggle.toggled.connect(_on_ai_enabled_toggled)
	visibility_changed.connect(_on_visibility_changed)


# ================= 设置读写 =================
func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		var saved_speed = config.get_value("dialogue", "text_speed", 0.05)
		var slider_value = text_speed_slider.max_value + text_speed_slider.min_value - saved_speed
		text_speed_slider.value = clamp(slider_value, text_speed_slider.min_value, text_speed_slider.max_value)
		auto_speed_slider.value = config.get_value("dialogue", "auto_speed", 2.0)
		bgm_volume_slider.value = config.get_value("audio", "bgm_volume", 0.0)
		sfx_volume_slider.value = config.get_value("audio", "sfx_volume", 0.0)
		voice_volume_slider.value = config.get_value("audio", "voice_volume", 0.0)
		fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)
	else:
		text_speed_slider.value = 0.05
		auto_speed_slider.value = 2.0
		bgm_volume_slider.value = 0.0
		sfx_volume_slider.value = 0.0
		voice_volume_slider.value = 0.0
		fullscreen_check.button_pressed = false


func _save_settings() -> void:
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("dialogue", "text_speed", GameManager.text_speed)
	config.set_value("dialogue", "auto_speed", auto_speed_slider.value)
	config.set_value("audio", "bgm_volume", bgm_volume_slider.value)
	config.set_value("audio", "sfx_volume", sfx_volume_slider.value)
	config.set_value("audio", "voice_volume", voice_volume_slider.value)
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	config.save("user://settings.cfg")


# ================= 信号回调 =================
func _on_text_speed_changed(value: float) -> void:
	var actual_speed = text_speed_slider.max_value + text_speed_slider.min_value - value
	if GameManager:
		GameManager.text_speed = actual_speed
	var scene = get_tree().current_scene
	if scene and scene.has_method("update_text_speed"):
		scene.update_text_speed(actual_speed)
	_save_settings()
	

func _on_auto_speed_changed(value: float) -> void:
	GameManager.set_variable("auto_speed", value)
	_save_settings()


func _on_bgm_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BGM"), value)
	_save_settings()


func _on_sfx_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), value)
	_save_settings()


func _on_voice_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), value)
	_save_settings()


func _on_fullscreen_toggled(button_pressed: bool) -> void:
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()


func _on_reset_unlocks() -> void:
	if GameManager:
		GameManager.reset_all_unlocks()
		
		
func _on_ui_sound_toggled(button_pressed: bool) -> void:
	if SFXManager:
		SFXManager.set_enabled(button_pressed)
		
		
func _on_panel_opened(panel_name: String) -> void:
	if panel_name == "SettingsUI":
		if ui_sound_toggle and SFXManager:
			ui_sound_toggle.button_pressed = SFXManager.enabled
		_setup_ai_controls()

func _on_ai_key_changed(new_text: String):
	if _is_loading_ai_controls:
		return
	GameManager.set_ai_setting("api_key", new_text)

func _on_deploy_ai_pressed() -> void:
	var exe_dir = OS.get_executable_path().get_base_dir()
	var script_path = exe_dir + "/deploy_ollama.bat"
	if not FileAccess.file_exists(script_path):
		OS.alert("未找到部署脚本 deploy_ollama.bat，请确保脚本与游戏在同一目录。", "部署失败")
		return
	OS.shell_open(script_path)
	OS.alert("部署脚本已启动，请在弹出的命令行窗口中查看进度。完成后重启游戏。", "提示")

func _on_visibility_changed() -> void:
	if not visible:
		return
	_can_toggle_ai = GameManager.is_settings_from_main_menu
	if ai_enabled_toggle:
		ai_enabled_toggle.disabled = not _can_toggle_ai
		ai_enabled_toggle.button_pressed = GameManager.ai_enabled
	GameManager.is_settings_from_main_menu = false

func _on_ai_enabled_toggled(button_pressed: bool) -> void:
	if not _can_toggle_ai:
		ai_enabled_toggle.set_pressed_no_signal(!button_pressed)
		return
	GameManager.set_ai_enabled_direct(button_pressed)
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("ai", "enabled", button_pressed)
	config.save("user://settings.cfg")

func _on_ollama_model_changed(new_text: String) -> void:
	if _is_loading_ai_controls:
		return
	GameManager.set_ai_setting("ollama_model", new_text)

func _on_ai_provider_selected(index: int) -> void:
	if _is_loading_ai_controls or index < 0 or index >= _provider_items.size():
		return
	var provider_id := _provider_items[index]
	GameManager.set_ai_setting("provider", provider_id)
	_setup_ai_controls()

func _on_ai_model_selected(index: int) -> void:
	if _is_loading_ai_controls or index < 0 or index >= _model_items.size():
		return
	var model_id := _model_items[index]
	GameManager.set_ai_setting("model", model_id)
	if GameManager.get_ai_setting("provider") == "ollama":
		GameManager.set_ai_setting("ollama_model", model_id)

func _setup_ai_controls() -> void:
	if not ai_provider_option or not ai_model_option:
		return
	_is_loading_ai_controls = true
	_populate_provider_options()
	_populate_model_options(GameManager.get_ai_setting("provider"))
	var provider_id := GameManager.get_ai_setting("provider")
	var provider := GameManager.get_current_ai_provider()
	ai_url_edit.text = provider.get("base_url", "")
	ai_model_edit.text = GameManager.get_ai_setting("model")
	ai_key_edit.text = GameManager.get_ai_setting("api_key")
	ollama_model_edit.text = GameManager.get_ai_setting("ollama_model")
	ollama_model_container.visible = provider_id == "ollama"
	ai_key_edit.secret = provider.get("auth_type", "bearer") != "none"
	ai_key_edit.editable = provider.get("auth_type", "bearer") != "none"
	ai_refresh_btn.disabled = not provider.get("supports_model_refresh", false)
	_is_loading_ai_controls = false

func _populate_provider_options() -> void:
	_provider_items.clear()
	ai_provider_option.clear()
	var current_provider := GameManager.get_ai_setting("provider")
	var selected_index := 0
	for provider in GameManager.get_ai_providers():
		if not provider is Dictionary:
			continue
		var provider_id: String = provider.get("id", "")
		if provider_id == "":
			continue
		var label := "[%s] %s" % [provider.get("region", "未知"), provider.get("name", provider_id)]
		_provider_items.append(provider_id)
		ai_provider_option.add_item(label)
		if provider_id == current_provider:
			selected_index = _provider_items.size() - 1
	if not _provider_items.is_empty():
		ai_provider_option.select(selected_index)
	_style_ai_dropdown(ai_provider_option)

func _populate_model_options(provider_id: String) -> void:
	_model_items.clear()
	ai_model_option.clear()
	var current_model := GameManager.get_ai_setting("model")
	if provider_id == "ollama" and GameManager.get_ai_setting("ollama_model") != "":
		current_model = GameManager.get_ai_setting("ollama_model")
	var selected_index := 0
	for model_id in GameManager.get_provider_models(provider_id):
		var text := str(model_id)
		if text == "":
			continue
		_model_items.append(text)
		ai_model_option.add_item(text)
		if text == current_model:
			selected_index = _model_items.size() - 1
	if _model_items.is_empty() and current_model != "":
		_model_items.append(current_model)
		ai_model_option.add_item(current_model)
	if not _model_items.is_empty():
		ai_model_option.select(selected_index)
	_style_ai_dropdown(ai_model_option)

func _style_ai_dropdown(option: OptionButton) -> void:
	if not option:
		return
	option.add_theme_color_override("font_color", Color.WHITE)
	option.add_theme_color_override("font_hover_color", Color.WHITE)
	option.add_theme_color_override("font_focus_color", Color.WHITE)
	option.add_theme_color_override("font_pressed_color", Color.WHITE)
	var popup := option.get_popup()
	if not popup:
		return
	var font = option.get_theme_font("font")
	if font:
		popup.add_theme_font_override("font", font)
	popup.add_theme_font_size_override("font_size", 28)
	popup.add_theme_color_override("font_color", AI_FIELD_COLOR)
	popup.add_theme_color_override("font_hover_color", Color.WHITE)
	popup.add_theme_color_override("font_focus_color", Color.WHITE)
	popup.add_theme_color_override("font_pressed_color", Color.WHITE)
	popup.add_theme_constant_override("v_separation", 8)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = AI_POPUP_BG_COLOR
	normal_style.border_color = AI_FIELD_COLOR
	normal_style.border_width_left = 3
	normal_style.border_width_top = 3
	normal_style.border_width_right = 3
	normal_style.border_width_bottom = 3
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	normal_style.content_margin_left = 12
	normal_style.content_margin_right = 12
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = AI_POPUP_HOVER_COLOR
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4
	popup.add_theme_stylebox_override("panel", normal_style)
	popup.add_theme_stylebox_override("hover", hover_style)

func _on_refresh_models_pressed() -> void:
	var provider := GameManager.get_current_ai_provider()
	if not provider.get("supports_model_refresh", false):
		return
	if _model_refresh_request and is_instance_valid(_model_refresh_request):
		_model_refresh_request.queue_free()
	_model_refresh_request = HTTPRequest.new()
	add_child(_model_refresh_request)
	_model_refresh_request.request_completed.connect(_on_model_refresh_completed)

	var provider_id: String = provider.get("id", "")
	var endpoint := ""
	var headers := PackedStringArray()
	if provider_id == "ollama":
		endpoint = "http://localhost:11434/api/tags"
	else:
		endpoint = str(provider.get("base_url", "")).rstrip("/") + "/models"
		headers.append("Content-Type: application/json")
		var api_key := GameManager.get_ai_setting("api_key")
		if api_key != "" and provider.get("auth_type", "bearer") == "bearer":
			headers.append("Authorization: Bearer " + api_key)
	var error := _model_refresh_request.request(endpoint, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_warning("[SettingsUI] 模型列表刷新请求失败：%d" % error)

func _on_model_refresh_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("[SettingsUI] 模型列表刷新失败，继续使用内置列表。")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	var models := _parse_model_refresh_response(GameManager.get_ai_setting("provider"), data)
	if models.is_empty():
		return
	_model_items.clear()
	ai_model_option.clear()
	for model_id in models:
		_model_items.append(model_id)
		ai_model_option.add_item(model_id)
	ai_model_option.select(0)
	GameManager.set_ai_setting("model", models[0])
	if GameManager.get_ai_setting("provider") == "ollama":
		GameManager.set_ai_setting("ollama_model", models[0])
		ollama_model_edit.text = models[0]

func _parse_model_refresh_response(provider_id: String, data: Dictionary) -> Array[String]:
	var models: Array[String] = []
	if provider_id == "ollama":
		for model in data.get("models", []):
			if model is Dictionary and str(model.get("name", "")) != "":
				models.append(str(model.get("name", "")))
	else:
		for model in data.get("data", []):
			if model is Dictionary and str(model.get("id", "")) != "":
				models.append(str(model.get("id", "")))
	return models
