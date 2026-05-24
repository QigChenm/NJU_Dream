# settings_ui.gd
extends CanvasLayer

# ================= 节点引用 =================
@onready var text_speed_slider: HSlider = $Panel/VBoxContainer/TextSpeedContainer/TextSpeed
@onready var auto_speed_slider: HSlider = $Panel/VBoxContainer/AutoSpeedContainer/AutoSpeed
@onready var bgm_volume_slider: HSlider = $Panel/VBoxContainer/BGMVolumeContainer/BGMVolume
@onready var sfx_volume_slider: HSlider = $Panel/VBoxContainer/SFXVolumeContainer/SFXVolume
@onready var voice_volume_slider: HSlider = $Panel/VBoxContainer/VoiceVolumeContainer/VoiceVolume
@onready var fullscreen_check: CheckButton = $Panel/VBoxContainer/FullscreenContainer/Fullscreen


# ================= 初始化 =================
func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_load_settings()
	_connect_signals()


func _connect_signals() -> void:
	text_speed_slider.value_changed.connect(_on_text_speed_changed)
	auto_speed_slider.value_changed.connect(_on_auto_speed_changed)
	bgm_volume_slider.value_changed.connect(_on_bgm_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	voice_volume_slider.value_changed.connect(_on_voice_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	var clear_save_btn = $Panel/VBoxContainer/ClearSaveContainer/ClearSave
	if clear_save_btn:
		clear_save_btn.pressed.connect(_on_reset_unlocks)


# ================= 设置读写 =================
func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		text_speed_slider.value = config.get_value("dialogue", "text_speed", 0.05)
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
	config.set_value("dialogue", "text_speed", text_speed_slider.value)
	config.set_value("dialogue", "auto_speed", auto_speed_slider.value)
	config.set_value("audio", "bgm_volume", bgm_volume_slider.value)
	config.set_value("audio", "sfx_volume", sfx_volume_slider.value)
	config.set_value("audio", "voice_volume", voice_volume_slider.value)
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	config.save("user://settings.cfg")


# ================= 信号回调 =================
func _on_text_speed_changed(value: float) -> void:
	if GameManager:
		GameManager.text_speed = value
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
