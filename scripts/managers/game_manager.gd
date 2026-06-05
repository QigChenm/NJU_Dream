# game_manager.gd
extends Node

# ================= 信号 =================
signal variable_changed(variable: String, new_value)
signal cg_unlocked(cg_id: String)
signal bgm_unlocked(bgm_id: String)
signal auto_mode_changed(enabled: bool)
signal skip_mode_changed(enabled: bool)

# ================= 常量 =================
const UNLOCK_FILE := "user://unlocks.cfg"
const AI_PROVIDERS_FILE := "res://config/ai_providers.json"

# ================= 属性 =================
var variables: Dictionary = {}
var ai_settings: Dictionary = {}
var ai_provider_registry: Dictionary = {}
var flags: Dictionary = {}
var dialogue_history: Array = []
var pending_choices: Array = []
var current_scene: String = ""
var ai_enabled: bool = true
var open_settings_on_load: bool = false
var open_gallery_on_load: bool = false
var open_about_on_load: bool = false
var text_speed: float = 0.05
var auto_speed: float = 2.0
var is_auto_mode: bool = false
var is_skip_mode: bool = false
var character_database: Dictionary = {}
var affection_ui_instance: CanvasLayer = null
var is_settings_from_main_menu: bool = false

# 解锁数据
var unlocked_cgs: Array[String] = []
var unlocked_bgms: Array[String] = []


# ================= 初始化 =================
func _ready() -> void:
	set_process_input(true)
	print("[GameManager] 游戏管理器初始化...")
	_load_ai_enabled_setting()
	_load_character_database()
	_load_unlocks()
	_load_config()
	_load_all_resources_from_index()
	_create_affection_ui()
	_load_ai_provider_registry()
	_load_ai_settings()

func check_ollama_status() -> bool:
	var http = HTTPRequest.new()
	add_child(http)
	http.request("http://localhost:11434/api/tags", [], HTTPClient.METHOD_GET)
	var result = await http.request_completed
	if result[0] == HTTPRequest.RESULT_SUCCESS:
		print("[GameManager] Ollama 服务正常运行")
		return true
	else:
		print("[GameManager] 未检测到 Ollama 服务")
		return false


func _create_affection_ui() -> void:
	var ui_scene = load("res://scenes/affection_ui.tscn")
	if ui_scene:
		affection_ui_instance = ui_scene.instantiate()
		add_child(affection_ui_instance)
		affection_ui_instance.visible = false


func _add_ui_to_scene() -> void:
	if get_tree().current_scene and affection_ui_instance:
		get_tree().current_scene.add_child(affection_ui_instance)
		print("[GameManager] 好感度UI已添加到场景")
	else:
		print("[GameManager] 未能添加好感度UI：场景或实例无效")


func start_new_game() -> void:
	variables.clear()
	dialogue_history.clear()
	current_scene = "prologue"


# ================= 角色数据库加载 =================
func _load_character_database() -> void:
	character_database.clear()
	var dir = DirAccess.open("res://assets/characters")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and not file_name.begins_with("."):
				_scan_directory_for_resources("res://assets/characters/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		print("[GameManager] 角色数据库加载完成，共找到 %d 个角色。" % character_database.size())
	else:
		print("[GameManager] 错误：无法打开 assets/characters 目录。")


func _scan_directory_for_resources(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with("_data.tres"):
				var resource_path = dir_path + "/" + file_name
				var char_data = load(resource_path) as CharacterData
				if char_data and char_data.character_id != "":
					character_database[char_data.character_id] = char_data
					print("[GameManager] 加载角色数据: '%s' (ID: %s)" % [char_data.display_name, char_data.character_id])
			file_name = dir.get_next()
		dir.list_dir_end()


# ================= 通用变量读写 =================
func set_variable(variable: String, value) -> void:
	variables[variable] = value
	variable_changed.emit(variable, value)
	print("[GameManager] 变量 '%s' = %s" % [variable, str(value)])


func get_variable(variable: String):
	return variables.get(variable, null)


# ================= 好感度便捷方法 =================
func set_affection(character: String, value: int) -> void:
	var key = "affection_" + character
	set_variable(key, value)


func get_affection(character: String) -> int:
	var key = "affection_" + character
	return variables.get(key, 0)


func add_affection(character: String, delta: int) -> void:
	var current = get_affection(character)
	set_affection(character, current + delta)


# ================= 事件标记便捷方法 =================
func set_flag(flag_name: String, value = true) -> void:
	var key = "flag_" + flag_name
	set_variable(key, value)


func get_flag(flag_name: String) -> bool:
	var key = "flag_" + flag_name
	return variables.get(key, false)


# ================= 永久解锁管理 =================
func unlock_cg(cg_id: String) -> void:
	if cg_id not in unlocked_cgs:
		unlocked_cgs.append(cg_id)
		_save_unlocks()
		cg_unlocked.emit(cg_id)
		print("[GameManager] CG 已永久解锁：%s" % cg_id)


func unlock_bgm(bgm_id: String) -> void:
	if bgm_id not in unlocked_bgms:
		unlocked_bgms.append(bgm_id)
		_save_unlocks()
		bgm_unlocked.emit(bgm_id)
		print("[GameManager] BGM 已永久解锁：%s" % bgm_id)


func is_cg_unlocked(cg_id: String) -> bool:
	return cg_id in unlocked_cgs


func is_bgm_unlocked(bgm_id: String) -> bool:
	return bgm_id in unlocked_bgms


func reset_all_unlocks() -> void:
	unlocked_cgs.clear()
	unlocked_bgms.clear()
	var config = ConfigFile.new()
	config.save(UNLOCK_FILE)
	print("[GameManager] 所有解锁已清空。")
	var gallery_panel = UIManager._panels.get("GalleryUI")
	if gallery_panel and gallery_panel.has_method("_refresh_cg_page"):
		gallery_panel._refresh_cg_page()
		gallery_panel._refresh_music_page()


func _load_unlocks() -> void:
	var config = ConfigFile.new()
	if config.load(UNLOCK_FILE) == OK:
		var cgs: Array = config.get_value("unlocks", "cgs", [])
		var bgms: Array = config.get_value("unlocks", "bgms", [])
		for cg in cgs:
			if cg is String and cg not in unlocked_cgs:
				unlocked_cgs.append(cg)
		for bgm in bgms:
			if bgm is String and bgm not in unlocked_bgms:
				unlocked_bgms.append(bgm)
		print("[GameManager] 永久解锁加载：CG %d 个，BGM %d 个" % [unlocked_cgs.size(), unlocked_bgms.size()])
	else:
		unlocked_cgs.clear()
		unlocked_bgms.clear()


func _save_unlocks() -> void:
	var config = ConfigFile.new()
	config.set_value("unlocks", "cgs", unlocked_cgs)
	config.set_value("unlocks", "bgms", unlocked_bgms)
	config.save(UNLOCK_FILE)


# ================= 全局配置加载 =================
func _load_config() -> void:
	var file = FileAccess.open("res://config/game_settings.json", FileAccess.READ)
	if file == null:
		push_warning("[GameManager] 无法打开 game_settings.json，使用默认设置。")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_warning("[GameManager] JSON 解析错误：" + json.get_error_message())
		return

	var settings = json.data

	# 对话速度
	if settings.has("dialogue"):
		var d = settings["dialogue"]
		if d.has("default_text_speed"):
			text_speed = d["default_text_speed"]
		if d.has("auto_advance_delay"):
			auto_speed = d["auto_advance_delay"]

	# 音频默认音量（由 SettingsUI 进一步覆盖，这里只设初始值）
	if settings.has("audio"):
		var a = settings["audio"]
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BGM"), a.get("bgm_default_volume_db", 0.0))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), a.get("sfx_default_volume_db", 0.0))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), a.get("voice_default_volume_db", 0.0))

	print("[GameManager] 全局配置已从 game_settings.json 加载。")

func _load_ai_settings() -> void:
	var config = ConfigFile.new()
	var default_provider := _get_default_ai_provider()
	var default_provider_id: String = default_provider.get("id", "ollama")
	var default_model: String = default_provider.get("default_model", "qwen2.5:7b-instruct")
	var default_base_url: String = default_provider.get("base_url", "http://localhost:11434/v1")
	if config.load("user://ai_settings.cfg") == OK:
		ai_settings["provider"] = config.get_value("ai", "provider", default_provider_id)
		ai_settings["model"] = config.get_value("ai", "model", default_model)
		ai_settings["api_key"] = config.get_value("ai", "api_key", "")
		ai_settings["base_url"] = config.get_value("ai", "base_url", _get_provider_base_url(ai_settings["provider"], default_base_url))
		ai_settings["ollama_model"] = config.get_value("ai", "ollama_model", "qwen2.5:7b-instruct")
		_load_provider_api_keys(config)
	else:
		# 默认值
		ai_settings["provider"] = default_provider_id
		ai_settings["base_url"] = default_base_url
		ai_settings["model"] = default_model
		ai_settings["api_key"] = ""
		ai_settings["ollama_model"] = "qwen2.5:7b-instruct"
		ai_settings["api_keys"] = {}
		_save_ai_settings()

func _save_ai_settings() -> void:
	var config = ConfigFile.new()
	var provider_id: String = ai_settings.get("provider", "ollama")
	config.set_value("ai", "provider", provider_id)
	config.set_value("ai", "base_url", get_current_ai_provider().get("base_url", ai_settings.get("base_url", "")))
	config.set_value("ai", "model", ai_settings.get("model", ""))
	config.set_value("ai", "api_key", ai_settings.get("api_key", ""))
	config.set_value("ai", "ollama_model", ai_settings.get("ollama_model", ""))
	var api_keys: Dictionary = ai_settings.get("api_keys", {})
	for key_provider in api_keys:
		config.set_value("api_keys", str(key_provider), api_keys[key_provider])
	config.save("user://ai_settings.cfg")

func get_ai_setting(key: String) -> String:
	return ai_settings.get(key, "")

func set_ai_setting(key: String, value: String) -> void:
	ai_settings[key] = value
	if key == "provider":
		var provider := get_ai_provider(value)
		ai_settings["base_url"] = provider.get("base_url", "")
		var provider_model = provider.get("default_model", "")
		if provider_model != "":
			ai_settings["model"] = provider_model
		var api_keys: Dictionary = ai_settings.get("api_keys", {})
		ai_settings["api_key"] = api_keys.get(value, "")
	elif key == "api_key":
		var provider_id: String = ai_settings.get("provider", "ollama")
		var api_keys: Dictionary = ai_settings.get("api_keys", {})
		api_keys[provider_id] = value
		ai_settings["api_keys"] = api_keys
	elif key == "ollama_model":
		ai_settings["model"] = value
	_save_ai_settings()

func _load_ai_provider_registry() -> void:
	ai_provider_registry.clear()
	var file = FileAccess.open(AI_PROVIDERS_FILE, FileAccess.READ)
	if file == null:
		push_warning("[GameManager] 无法打开 ai_providers.json，使用 Ollama 默认配置。")
		ai_provider_registry = {"providers": [_fallback_ollama_provider()]}
		return
	var json_string = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_string) != OK:
		push_warning("[GameManager] ai_providers.json 解析失败，使用 Ollama 默认配置。")
		ai_provider_registry = {"providers": [_fallback_ollama_provider()]}
		return
	var data = json.data
	if data is Dictionary and data.has("providers") and data["providers"] is Array:
		ai_provider_registry = data
	else:
		ai_provider_registry = {"providers": [_fallback_ollama_provider()]}

func get_ai_providers() -> Array:
	return ai_provider_registry.get("providers", [])

func get_ai_provider(provider_id: String) -> Dictionary:
	for provider in get_ai_providers():
		if provider is Dictionary and provider.get("id", "") == provider_id:
			return provider
	return _get_default_ai_provider()

func get_current_ai_provider() -> Dictionary:
	return get_ai_provider(ai_settings.get("provider", "ollama"))

func get_provider_models(provider_id: String) -> Array:
	var provider := get_ai_provider(provider_id)
	return provider.get("models", [])

func _get_default_ai_provider() -> Dictionary:
	var providers := get_ai_providers()
	for provider in providers:
		if provider is Dictionary and provider.get("id", "") == "ollama":
			return provider
	if not providers.is_empty() and providers[0] is Dictionary:
		return providers[0]
	return _fallback_ollama_provider()

func _get_provider_base_url(provider_id: String, fallback: String = "") -> String:
	var provider := get_ai_provider(provider_id)
	return provider.get("base_url", fallback)

func _load_provider_api_keys(config: ConfigFile) -> void:
	var api_keys := {}
	for provider in get_ai_providers():
		if not provider is Dictionary:
			continue
		var provider_id: String = provider.get("id", "")
		if provider_id == "":
			continue
		api_keys[provider_id] = config.get_value("api_keys", provider_id, "")
	if api_keys.is_empty():
		api_keys[ai_settings.get("provider", "ollama")] = ai_settings.get("api_key", "")
	ai_settings["api_keys"] = api_keys
	var current_provider: String = ai_settings.get("provider", "ollama")
	if ai_settings.get("api_key", "") == "":
		ai_settings["api_key"] = api_keys.get(current_provider, "")

func _fallback_ollama_provider() -> Dictionary:
	return {
		"id": "ollama",
		"name": "Ollama 本地",
		"region": "本地",
		"base_url": "http://localhost:11434/v1",
		"api_format": "openai_chat",
		"auth_type": "none",
		"supports_model_refresh": true,
		"default_model": "qwen2.5:7b-instruct",
		"models": ["qwen2.5:7b-instruct"]
	}

func _load_all_resources_from_index() -> void:
	var file = FileAccess.open("res://config/resource_index.json", FileAccess.READ)
	if file == null:
		push_error("[GameManager] 无法打开 resource_index.json，请确保文件存在。")
		return
	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("[GameManager] resource_index.json 解析失败。")
		return

	var data = json.data
	if not data is Dictionary:
		return

	# 加载角色
	if data.has("characters"):
		for path in data["characters"]:
			var res = load(path)
			if res is CharacterData and res.character_id != "":
				character_database[res.character_id] = res
	print("[GameManager] 角色数据库加载完成，共 %d 个角色。" % character_database.size())

	# 加载背景
	if data.has("backgrounds"):
		for path in data["backgrounds"]:
			var res = load(path)
			if res is BackgroundData and res.background_id != "":
				BackgroundManager.background_database[res.background_id] = res
	print("[GameManager] 背景数据库加载完成，共 %d 个背景。" % BackgroundManager.background_database.size())

	# 加载音频（BGM）
	if data.has("audio_bgm"):
		for path in data["audio_bgm"]:
			var res = load(path)
			if res is AudioData and res.audio_id != "":
				AudioManager.audio_database[res.audio_id] = res
	print("[GameManager] 音频数据库加载完成，共 %d 个音频。" % AudioManager.audio_database.size())

	# 加载粒子
	if data.has("particles"):
		for path in data["particles"]:
			var res = load(path)
			if res is ParticleEffectData and res.effect_id != "":
				ParticleManager.particle_database[res.effect_id] = res
	print("[GameManager] 粒子数据库加载完成，共 %d 个效果。" % ParticleManager.particle_database.size())

	# 加载 CG
	if data.has("cg"):
		for path in data["cg"]:
			var res = load(path)
			if res is CGData and res.cg_id != "":
				CGManager.cg_database[res.cg_id] = res
	print("[GameManager] CG数据库加载完成，共 %d 个CG。" % CGManager.cg_database.size())

# ================= AI 模式 =================
func _load_ai_enabled_setting() -> void:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		ai_enabled = config.get_value("ai", "enabled", true)
	else:
		ai_enabled = true

func set_ai_enabled_direct(enabled: bool) -> void:
	ai_enabled = enabled
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("ai", "enabled", enabled)
	config.save("user://settings.cfg")
	if has_node("/root/AIManager"):
		get_node("/root/AIManager").ai_enabled = enabled
