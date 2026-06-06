# save_manager.gd
extends Node

# ================= 常量 =================
const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 20
const SCREENSHOT_SCALE := 0.25

# ================= 信号 =================
signal save_completed(slot: int)
signal load_completed()
signal save_deleted(slot: int)

# ================= 属性 =================
var latest_slot: int = -1
var continue_mode: bool = false


# ================= 初始化 =================
func _ready() -> void:
	_ensure_save_dir()


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		var err = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			push_error("[SaveManager] 无法创建存档目录：%s (错误码: %d)" % [SAVE_DIR, err])
		else:
			print("[SaveManager] 存档目录已创建：%s" % SAVE_DIR)
	else:
		print("[SaveManager] 存档目录已存在：%s" % SAVE_DIR)


# ================= 路径工具 =================
func _get_save_path(slot: int) -> String:
	return SAVE_DIR + "save_%03d.json" % slot


func _get_thumbnail_path(slot: int) -> String:
	return SAVE_DIR + "thumb_%03d.png" % slot


# ================= 保存 =================
func save_game(slot: int) -> void:
	print("[SaveManager] 开始保存到槽位 %d..." % slot)

	var data := SaveGameData.new()
	var dt = Time.get_datetime_dict_from_system()
	data.save_date = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
	data.save_time = "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]

	# 场景与背景
	data.current_scene = GameManager.current_scene if GameManager else ""
	data.current_background_id = BackgroundManager.current_background_id if BackgroundManager else ""
	data.current_bgm_id = AudioManager.get_current_bgm_id() if AudioManager else ""

	# 变量
	data.variables = GameManager.variables.duplicate(true) if GameManager else {}

	# 对话历史（移除最后一句，除非是玩家的选择）
	if GameManager.dialogue_history.size() > 0:
		data.dialogue_history = GameManager.dialogue_history.duplicate(true)
		var last_entry = data.dialogue_history[data.dialogue_history.size() - 1]
		if last_entry.get("character", "") != "玩家":
			data.dialogue_history.remove_at(data.dialogue_history.size() - 1)
	else:
		data.dialogue_history = []

	# 对话 UI 状态
	var scene_root = get_tree().current_scene
	if scene_root and scene_root.has_method("get_dialogue_state"):
		var ui_state = scene_root.get_dialogue_state()
		data.dialogue_text = ui_state.get("text", "")
		data.character_name = ui_state.get("character", "")
		data.choice_options = ui_state.get("choices", [])
	else:
		data.dialogue_text = ""
		data.character_name = ""
		data.choice_options = []

	# 角色状态
	data.active_characters = []
	data.character_expressions = {}
	data.character_positions = {}
	if CharacterManager:
		var roles_data = CharacterManager.get_active_roles_data()
		for pos in ["left", "right"]:
			var info = roles_data.get(pos)
			if info != null and info is Dictionary:
				var char_id = info.get("id", "")
				if char_id != "":
					data.active_characters.append(char_id)
					data.character_positions[char_id] = pos
					data.character_expressions[char_id] = info.get("expression", "default")

	# 粒子效果
	data.active_particle_effects = []
	if has_node("/root/ParticleManager"):
		var pm = get_node("/root/ParticleManager")
		if pm.has_method("get_active_effects"):
			data.active_particle_effects = pm.get_active_effects()

	# 剧本执行状态
	data.pending_commands = []
	if has_node("/root/ScriptEngine"):
		data.pending_commands = get_node("/root/ScriptEngine").get_pending_commands()
	if has_node("/root/AIManager") and get_node("/root/AIManager").has_method("get_prediction_state_for_save"):
		data.ai_prediction_state = get_node("/root/AIManager").get_prediction_state_for_save()

	# 序列化并写入
	var json_str := JSON.stringify(data.to_dict(), "\t")
	if json_str == "" or json_str == "null":
		push_error("[SaveManager] JSON 序列化失败")
		return

	var file := FileAccess.open(_get_save_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] 无法打开文件：%s" % _get_save_path(slot))
		return

	file.store_string(json_str)
	file.close()
	print("[SaveManager] 存档文件写入成功：%s (%d 字节)" % [_get_save_path(slot), json_str.length()])

	save_completed.emit(slot)
	print("[SaveManager] 存档完成：槽位 %d" % slot)


func auto_save_to_latest_slot() -> void:
	var slot := -1
	for i in range(MAX_SLOTS):
		if not has_save(i):
			slot = i
			break
	if slot == -1:
		slot = 0
	print("[SaveManager] 自动保存到槽位 %d" % slot)

	var scene := get_tree().current_scene
	if scene and scene.has_method("hide_all_ui_for_screenshot"):
		scene.hide_all_ui_for_screenshot()
		await get_tree().process_frame
		await get_tree().process_frame

	var viewport := get_viewport()
	var img := viewport.get_texture().get_image()
	if not img.is_empty():
		var new_width := int(img.get_width() * 0.25)
		var new_height := int(img.get_height() * 0.25)
		if new_width > 0 and new_height > 0:
			img.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)
		img.save_png(_get_thumbnail_path(slot))

	if scene and scene.has_method("show_all_ui"):
		scene.show_all_ui()

	save_game(slot)


# 【已废弃】截图方法，现在截图由 save_load_ui 负责
func _capture_screenshot(slot: int) -> void:
	await get_tree().process_frame
	var viewport := get_viewport()
	if not viewport:
		return
	var img := viewport.get_texture().get_image()
	if img.is_empty():
		return
	var new_width := int(img.get_width() * SCREENSHOT_SCALE)
	var new_height := int(img.get_height() * SCREENSHOT_SCALE)
	if new_width > 0 and new_height > 0:
		img.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)
	img.save_png(_get_thumbnail_path(slot))


# ================= 读取 =================
func load_game(slot: int) -> bool:
	var path := _get_save_path(slot)
	if not FileAccess.file_exists(path):
		push_error("[SaveManager] 存档文件不存在：%s" % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] 无法读取存档文件：%s" % path)
		return false

	var json_str := file.get_as_text()
	file.close()

	if json_str.is_empty():
		push_error("[SaveManager] 存档文件为空：%s" % path)
		return false

	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		push_error("[SaveManager] JSON 解析失败：%s (行 %d)" % [json.get_error_message(), json.get_error_line()])
		return false

	var dict: Dictionary = json.data
	if dict.is_empty():
		push_error("[SaveManager] 存档数据为空")
		return false

	_apply_save_data(dict)
	load_completed.emit()
	print("[SaveManager] 存档加载成功：槽位 %d" % slot)
	return true


func load_latest_game() -> bool:
	var latest_time := 0.0
	var found := false
	for i in range(MAX_SLOTS):
		if has_save(i):
			var path = _get_save_path(i)
			var mod_time := FileAccess.get_modified_time(path)
			if mod_time > latest_time:
				latest_time = mod_time
				latest_slot = i
				found = true
	if found:
		print("[SaveManager] 最新存档槽位：%d" % latest_slot)
		return true
	push_error("[SaveManager] 没有找到任何存档。")
	return false


func _apply_save_data(dict: Dictionary) -> void:
	print("[SaveManager] 正在恢复游戏状态...")

	# 恢复变量（先清旧好感，再设置）
	var new_vars: Dictionary = dict.get("variables", {})
	if GameManager:
		for key in GameManager.variables.keys():
			if key.begins_with("affection_") and not new_vars.has(key):
				GameManager.set_variable(key, 0)
		for key in new_vars:
			GameManager.set_variable(key, new_vars[key])

	# 恢复背景
	var bg_id: String = dict.get("current_background_id", "")
	if bg_id != "":
		BackgroundManager.set_background(bg_id)

	# 恢复 BGM
	var bgm_id: String = dict.get("current_bgm_id", "")
	if bgm_id != "" and AudioManager:
		AudioManager.play_audio(bgm_id, 0.0)

	# 恢复粒子
	if has_node("/root/ParticleManager"):
		var pm = get_node("/root/ParticleManager")
		for active_id in pm.get_active_effects():
			pm.stop_effect(active_id)
		var effects: Array = dict.get("active_particle_effects", [])
		for effect_id in effects:
			pm.play_effect(effect_id)

	# 恢复角色
	var characters: Array = dict.get("active_characters", [])
	var expressions: Dictionary = dict.get("character_expressions", {})
	var positions: Dictionary = dict.get("character_positions", {})
	var roles_data: Dictionary = {"left": null, "right": null}
	for char_id in characters:
		var expr = expressions.get(char_id, "default")
		var pos = positions.get(char_id, "left")
		roles_data[pos] = {"id": char_id, "expression": expr}
	CharacterManager.restore_characters(roles_data)
	await get_tree().process_frame

	# 恢复对话 UI
	var scene_root = get_tree().current_scene
	if scene_root and scene_root.has_method("restore_dialogue_state"):
		scene_root.restore_dialogue_state({
			"character": dict.get("character_name", ""),
			"text": dict.get("dialogue_text", ""),
			"choices": dict.get("choice_options", [])
		})

	# 恢复对话历史
	var history: Array = dict.get("dialogue_history", [])
	if GameManager:
		GameManager.dialogue_history.clear()
		for entry in history:
			GameManager.dialogue_history.append(entry)

	# 恢复剧本指令
	if has_node("/root/ScriptEngine"):
		var se = get_node("/root/ScriptEngine")
		var pending_commands: Array = dict.get("pending_commands", [])
		se.silently_set_commands(pending_commands)
		if not pending_commands.is_empty():
			if has_node("/root/AIManager") and get_node("/root/AIManager").has_method("suppress_next_auto_continue"):
				get_node("/root/AIManager").suppress_next_auto_continue()
			se.execute_commands(pending_commands)
			print("[SaveManager] 剧情进程已从存档点恢复，共 %d 条新指令。" % pending_commands.size())
		else:
			print("[SaveManager] 存档后没有新的剧情指令，场景已恢复为静态。")
	else:
		push_error("[SaveManager] ScriptEngine 未找到，无法恢复剧情。")

	if has_node("/root/AIManager") and get_node("/root/AIManager").has_method("restore_prediction_state_from_save"):
		get_node("/root/AIManager").restore_prediction_state_from_save(dict.get("ai_prediction_state", {}))
	if has_node("/root/AIManager") and get_node("/root/AIManager").has_method("rebuild_predictions_for_current_state"):
		get_node("/root/AIManager").call_deferred("rebuild_predictions_for_current_state", true)

	# 重置 CG 状态
	if has_node("/root/CGManager"):
		get_node("/root/CGManager").reset_state()

	print("[SaveManager] 游戏状态全面恢复完成！")


# 【已废弃】旧版恢复脚本方法，目前流程已不调用
func _resume_script(commands: Array) -> void:
	if has_node("/root/ScriptEngine"):
		var se = get_node("/root/ScriptEngine")
		if se.has_method("set_commands"):
			se.set_commands(commands)
			se.execute_commands(commands)


# ================= 删除与状态查询 =================
func delete_save(slot: int) -> void:
	var path := _get_save_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var thumb_path := _get_thumbnail_path(slot)
	if FileAccess.file_exists(thumb_path):
		DirAccess.remove_absolute(thumb_path)
	save_deleted.emit(slot)
	print("[SaveManager] 存档槽位 %d 已删除" % slot)


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_get_save_path(slot))


func has_any_save() -> bool:
	for i in range(MAX_SLOTS):
		if has_save(i):
			return true
	return false


func get_save_info(slot: int) -> Dictionary:
	var path := _get_save_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": false}

	var json_str := file.get_as_text()
	file.close()
	if json_str.is_empty():
		return {"exists": false}

	var json := JSON.new()
	if json.parse(json_str) != OK:
		return {"exists": false}

	var dict: Dictionary = json.data
	return {
		"exists": true,
		"date": dict.get("save_date", ""),
		"time": dict.get("save_time", ""),
		"description": dict.get("save_description", ""),
		"thumbnail": _get_thumbnail_path(slot),
		"play_time": dict.get("play_time", 0.0)
	}


func get_latest_slot() -> int:
	var latest_slot_found := 0
	var latest_time := 0.0
	for i in range(MAX_SLOTS):
		if has_save(i):
			var path = _get_save_path(i)
			var mod_time := FileAccess.get_modified_time(path)
			if mod_time > latest_time:
				latest_time = mod_time
				latest_slot_found = i
	return latest_slot_found


# 【已废弃】画廊解锁刷新方法，永久解锁制度已不再需要
func _notify_gallery_refresh() -> void:
	if GameManager:
		for cg in GameManager.unlocked_cgs:
			GameManager.cg_unlocked.emit(cg)
		for bgm in GameManager.unlocked_bgms:
			GameManager.bgm_unlocked.emit(bgm)
