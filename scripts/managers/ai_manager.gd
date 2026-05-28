# ai_manager.gd
extends Node

## AI 功能总开关
@export var ai_enabled: bool = true
@export var base_url: String = "https://api.moonshot.cn/v1"
@export var model: String = "kimi-k2.6"
@export var request_timeout: float = 30.0
@export var env_file_path: String = "res://.env"

var _http_request: HTTPRequest = null
var _is_requesting: bool = false
var _env_values: Dictionary = {}
var _pending_choice_id: int = -1
var _pending_choice_text: String = ""
var _waiting_for_choice_continuation: bool = false

const _FALLBACK_TEXT := "AI 暂时不可用，请稍后再试。"
const _FALLBACK_ENV_FILE_PATH := "res://env"
const MEMORY_FILE := "res://config/ai_rules.json"

# ---------- 主线章节定义 ----------
const MAIN_STORY_LINE: Dictionary = {
	"prologue": {
		"title": "序章·初遇",
		"goal": "让玩家与角色初次相遇，建立基本关系。",
		"key_events": [
			"在校园场景中初次见面",
			"简单的自我介绍和闲聊",
            "触发好感度轻微上升"
		],
		"next_chapter": "chapter1"
	},
	"chapter1": {
		"title": "第一章·走近",
		"goal": "通过日常互动加深了解，好感度达到 30 以上时触发转折事件。",
		"key_events": [
			"一起上课、吃饭或散步",
			"分享各自的小秘密",
            "好感度接近 30 时，出现首次小矛盾或选择"
		],
		"next_chapter": "chapter2"
	},
	"chapter2": {
		"title": "第二章·波澜",
		"goal": "关系出现考验，通过关键选择决定剧情走向。",
		"key_events": [
			"出现误会或第三方介入",
			"角色情绪波动，需要玩家做出关键选择",
            "根据好感度和选择分支，导向不同发展方向"
		],
		"next_chapter": "chapter3"
	},
	"chapter3": {
		"title": "第三章·心意",
		"goal": "关系明朗化，走向结局。",
		"key_events": [
			"浪漫的约会或独处场景",
			"表达心意的关键对话",
            "解锁 CG 或特殊回忆"
		],
		"next_chapter": "ending"
	},
	"ending": {
		"title": "结局",
		"goal": "根据好感度和关键选择呈现不同结局。",
		"key_events": [
			"根据之前的选择和好感度值，走向好结局或普通结局",
            "播放最终 CG 和音乐"
		]
	}
}

# ---------- 初始化 ----------
func _ready() -> void:
	_load_env_file()

	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)

	call_deferred("_wire_runtime_signals")


func _wire_runtime_signals() -> void:
	if has_node("/root/DialogueManager"):
		DialogueManager.ai_adapter = self
		if not DialogueManager.is_connected("choice_made", _on_choice_made):
			DialogueManager.connect("choice_made", _on_choice_made)

	if has_node("/root/ScriptEngine"):
		if not ScriptEngine.is_connected("execution_finished", _on_script_execution_finished):
			ScriptEngine.connect("execution_finished", _on_script_execution_finished)


# ---------- AI 发送入口 ----------
func send_message(input_str: String, _callback: Callable = Callable()) -> void:
	if not ai_enabled:
		_recover_with_dialogue("[AIManager] AI 功能未启用。")
		_finish_requesting()
		return

	if _is_requesting:
		push_warning("[AIManager] 已有 AI 请求进行中，本次请求已忽略。")
		_recover_with_dialogue("[AIManager] AI 请求仍在进行中。")
		_finish_requesting()
		return

	var api_key := _get_env_value("MOONSHOT_API_KEY")
	if api_key == "":
		push_warning("[AIManager] 未设置 MOONSHOT_API_KEY，无法请求 Kimi。")
		_recover_with_dialogue("[AIManager] 缺少 MOONSHOT_API_KEY。")
		_finish_requesting()
		return

	_is_requesting = true
	var endpoint := _get_base_url().rstrip("/") + "/chat/completions"
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	var payload := {
		"model": _get_model(),
		"messages": [
			{"role": "system", "content": _build_system_prompt()},
			{"role": "user", "content": _build_user_prompt(input_str)}
		],
		"temperature": 0.8,
		"max_tokens": 800,
		"response_format": {"type": "json_object"}
	}

	var error := _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		push_error("[AIManager] 请求 Kimi 失败，错误码: %d" % error)
		_is_requesting = false
		_recover_with_dialogue("[AIManager] 无法发起 Kimi 请求。")
		_finish_requesting()


# ---------- 响应处理 ----------
func process_ai_response(response: Dictionary) -> void:
	if not response.has("commands"):
		_recover_with_dialogue("[AIManager] 响应缺少 commands。")
		return
	var commands = response["commands"]
	if not commands is Array:
		push_warning("[AIManager] 响应中的 'commands' 不是数组，已忽略。")
		_recover_with_dialogue("[AIManager] commands 不是数组。")
		return
	if commands.is_empty():
		push_warning("[AIManager] 响应中的 'commands' 为空，已忽略。")
		_recover_with_dialogue("[AIManager] commands 为空。")
		return
	if not has_node("/root/ScriptEngine"):
		push_error("[AIManager] ScriptEngine 未找到，无法执行命令。")
		return
	ScriptEngine.execute_commands(commands)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting = false
	_finish_requesting()

	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[AIManager] Kimi 请求未成功完成，结果码: %d" % result)
		_recover_with_dialogue("[AIManager] Kimi 请求未成功完成。")
		return
	if response_code < 200 or response_code >= 300:
		push_error("[AIManager] Kimi 返回 HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		_recover_with_dialogue("[AIManager] Kimi HTTP 响应异常。")
		return

	var raw_response = JSON.parse_string(body.get_string_from_utf8())
	if not raw_response is Dictionary:
		push_error("[AIManager] Kimi 响应不是 JSON 对象。")
		_recover_with_dialogue("[AIManager] Kimi 响应不是 JSON 对象。")
		return

	var choices: Array = raw_response.get("choices", [])
	if choices.is_empty():
		push_error("[AIManager] Kimi 响应缺少 choices。")
		_recover_with_dialogue("[AIManager] Kimi 响应缺少 choices。")
		return
	if not choices[0] is Dictionary:
		push_error("[AIManager] Kimi choices[0] 不是对象。")
		_recover_with_dialogue("[AIManager] Kimi choices 格式异常。")
		return

	var first_choice: Dictionary = choices[0]
	var message = first_choice.get("message", {})
	if not message is Dictionary:
		push_error("[AIManager] Kimi message 不是对象。")
		_recover_with_dialogue("[AIManager] Kimi message 格式异常。")
		return

	var message_dict: Dictionary = message
	var content: String = message_dict.get("content", "")
	var ai_response = JSON.parse_string(_normalize_json_content(content))
	if not ai_response is Dictionary:
		push_error("[AIManager] Kimi 返回内容不是有效 JSON。")
		_recover_with_dialogue("[AIManager] Kimi 返回内容不是有效 JSON。")
		return

	process_ai_response(ai_response)


# ---------- 选项续写 ----------
func _on_choice_made(choice_id: int) -> void:
	_pending_choice_id = choice_id
	_pending_choice_text = _resolve_choice_text(choice_id)
	_waiting_for_choice_continuation = true
	print("[AIManager] 已记录玩家选择: %d %s" % [choice_id, _pending_choice_text])


func _on_script_execution_finished() -> void:
	if not _waiting_for_choice_continuation:
		return
	if _is_requesting:
		return

	var choice_event := _build_choice_event()
	_pending_choice_id = -1
	_pending_choice_text = ""
	_waiting_for_choice_continuation = false
	call_deferred("send_message", choice_event)


# ---------- 提示词构建 ----------
func _build_system_prompt() -> String:
	var lines := PackedStringArray()
	
	lines.append("# 长期记忆（用户纠正的规则，必须严格遵守）")
	var rules := _load_rules()
	if rules.is_empty():
		lines.append("（暂无用户自定义规则）")
	else:
		for item in rules:
			lines.append("- " + item.get("rule", ""))
	lines.append("")
	
	lines.append_array(_get_core_rules())
	lines.append_array(_get_character_skills())
	lines.append_array(_get_scene_templates())
	lines.append_array(_get_emotion_rules())
	lines.append_array(_get_story_guidance())
	lines.append_array(_get_command_spec())
	lines.append_array(_get_dialogue_examples())
	return "\n".join(lines)


# -- 核心规则 --
func _get_core_rules() -> PackedStringArray:
	var rules := PackedStringArray()
	rules.append("# 角色与目标")
	rules.append("你是视觉小说《梧桐语小栈》的 AI 编剧引擎。你必须且只能返回 JSON 对象：{\"commands\": [...]}")
	rules.append("绝对不要输出 Markdown 代码块、解释文字或其他任何内容。")
	rules.append("")
	rules.append("# 核心规则")
	rules.append("1. 每次必须生成 2-4 条指令，形成一小段完整的剧情推进。绝不能只生成一条 show_dialogue 就结束。")
	rules.append("2. 第一条指令通常是 show_dialogue，后续可搭配 set_expression、character_action、change_background 等。")
	rules.append("3. 只有在剧情自然结束（如章节末尾、离别场景）时才使用 end_scene。一般对话中绝对不要使用 end_scene。")
	rules.append("4. 当剧情出现需要玩家决策的时刻（例如角色提问、征求意见、面临选择时），必须使用 show_choices 指令，提供 2-3 个选项。")
	rules.append("5. show_choices 必须是本轮 commands 的最后一条指令。玩家选择后，系统会自动将选择结果发送给你。")
	rules.append("6. 【强制规则】在收到 __start__ 或新章节开场的请求时，你必须在 commands 中包含一条 play_audio 指令，为场景配上合适的背景音乐。")
	rules.append("7. 当你收到玩家的选择事件后，你的第一个指令应展示角色对该选择的即时反应（如惊讶、高兴、犹豫等），然后继续后续剧情。")
	rules.append("8. 【严格禁止】不要在 show_dialogue 的 text 字段中直接使用 BBCode 标签来模拟角色动作（如 [bounce]、[shake]）。如需角色做出动作，你必须独立输出一条 character_action 指令。")
	rules.append("9. 只使用下方列出的资源 ID，严禁编造。")
	rules.append("")
	return rules


# -- 角色 Skill --
func _get_character_skills() -> PackedStringArray:
	var skills := PackedStringArray()
	skills.append("# 角色 Skill")
	skills.append("")
	skills.append("## sister（妹妹）")
	skills.append("- 性格：活泼可爱，有点粘人，偶尔任性。")
	skills.append("- 说话风格：喜欢用“哥哥”开头，语气轻快，多用“～”和感叹号。")
	skills.append("- 情感表达：")
	skills.append("  - 开心 → happy，非常开心 → very_happy")
	skills.append("  - 难过/委屈 → sad，哭 → cry")
	skills.append("  - 生气/不满 → angry")
	skills.append("- 行为习惯：")
	skills.append("  - 高兴时 → bounce（跳）")
	skills.append("  - 被吓到/感动 → shake（发抖）")
	skills.append("  - 同意 → nod（点头）")
	skills.append("  - 害羞/想后退 → step_back")
	skills.append("- 关系：你是她的“哥哥”，她依赖你，有时会撒娇。")
	skills.append("")
	return skills


# -- 场景模板 --
func _get_scene_templates() -> PackedStringArray:
	var scenes := PackedStringArray()
	scenes.append("# 场景模板")
	scenes.append("- gulou_spring (鼓楼·春)：春天的校园，阳光明媚，樱花飘落。适合轻松愉快的日常互动。")
	scenes.append("- gulou_winter (鼓楼·冬)：冬天的校园，雪花纷飞，气氛清冷。适合深情对话或稍微沉重的剧情。")
	scenes.append("")
	return scenes


# -- 情绪反应库 --
func _get_emotion_rules() -> PackedStringArray:
	var emotions := PackedStringArray()
	emotions.append("# 情绪反应规则（基于好感度）")
	emotions.append("- 好感度 0-15：角色保持礼貌但略疏离，表情多为 default，偶尔 happy。")
	emotions.append("- 好感度 15-30：角色开始亲近，表情 happy 增多，偶尔 sad 表示委屈。")
	emotions.append("- 好感度 30-50：角色明显依赖，经常使用 very_happy，情绪波动更大。")
	emotions.append("- 好感度 50+：角色非常亲密，偶尔撒娇，可能会出现特殊事件（解锁 CG）。")
	emotions.append("")
	return emotions


# -- 剧情指导 --
func _get_story_guidance() -> PackedStringArray:
	var guide := PackedStringArray()
	guide.append("# 剧情阶段指导")
	guide.append("当前章节和进度会由系统在用户消息中提供，请严格据此推进剧情。")
	guide.append("- 序章：着重初遇和自我介绍，建立基础关系。")
	guide.append("- 第一章：通过日常互动加深了解，好感度达到 30 左右时引入小矛盾或选择。")
	guide.append("- 第二章：出现考验或误会，通过关键选择影响走向。")
	guide.append("- 第三章：关系明朗化，准备结局。")
	guide.append("- 结局：根据整体好感度给出相应结局。")
	guide.append("")
	return guide


# -- 指令参考 --
func _get_command_spec() -> PackedStringArray:
	var spec := PackedStringArray()
	spec.append("# 可用指令速查")
	spec.append("show_dialogue: {\"type\":\"show_dialogue\",\"character\":\"sister\",\"text\":\"对话内容\"}")
	spec.append("show_choices: {\"type\":\"show_choices\",\"choices\":[{\"id\":1,\"text\":\"选项1\"}]}")
	spec.append("change_background: {\"type\":\"change_background\",\"background\":\"gulou_spring\"}")
	spec.append("set_characters: {\"type\":\"set_characters\",\"left\":{\"id\":\"sister\",\"expression\":\"happy\"}}")
	spec.append("set_expression: {\"type\":\"set_expression\",\"character\":\"sister\",\"expression\":\"angry\"}")
	spec.append("character_action: {\"type\":\"character_action\",\"character\":\"sister\",\"action\":\"shake\"}")
	spec.append("play_audio: {\"type\":\"play_audio\",\"audio_id\":\"spring_forest\"}")
	spec.append("stop_audio: {\"type\":\"stop_audio\",\"audio_id\":\"spring_forest\"}")
	spec.append("particle_play/stop: {\"type\":\"particle_play\",\"effect_id\":\"petal\"}")
	spec.append("unlock_cg/bgm: {\"type\":\"unlock_cg\",\"cg_id\":\"heroine_smile\"}")
	spec.append("add_affection: {\"type\":\"add_affection\",\"character\":\"sister\",\"delta\":10}")
	spec.append("long_dialogue: {\"type\":\"long_dialogue\",\"text\":\"全屏叙述文本\"}")
	spec.append("end_scene: {\"type\":\"end_scene\"} (最后一条指令)")
	spec.append("")
	return spec


# -- 对话范例 --
func _get_dialogue_examples() -> PackedStringArray:
	var examples := PackedStringArray()
	examples.append("# 对话范例（请严格模仿）")
	examples.append("")
	examples.append("## 普通对话")
	examples.append("{")
	examples.append("  \"commands\": [")
	examples.append("    {\"type\": \"change_background\", \"background\": \"gulou_spring\"},")
	examples.append("    {\"type\": \"set_characters\", \"left\": {\"id\": \"sister\", \"expression\": \"happy\"}},")
	examples.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"哥哥！今天天气真好呀～ [color=#FFB6C1]一起去散步吗？[/color]\"},")
	examples.append("    {\"type\": \"set_expression\", \"character\": \"sister\", \"expression\": \"very_happy\"},")
	examples.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"好久没和你一起走了呢。[shake rate=15 level=3]好开心！[/shake]\"}")
	examples.append("  ]")
	examples.append("}")
	examples.append("")
	examples.append("## 出现选项时")
	examples.append("当妹妹问你想去哪里，你应该生成如下指令：")
	examples.append("{")
	examples.append("  \"commands\": [")
	examples.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"哥哥，你想去哪里呢？\"},")
	examples.append("    {\"type\": \"show_choices\", \"choices\": [{\"id\":1,\"text\":\"去公园\"}, {\"id\":2,\"text\":\"去图书馆\"}]}")
	examples.append("  ]")
	examples.append("}")
	examples.append("")
	examples.append("## 收到玩家选择后的反应（注意：动作指令独立）")
	examples.append("当玩家选择了“去公园”，你应该生成：")
	examples.append("")
	examples.append("{")
	examples.append("  \"commands\": [")
	examples.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"好呀！公园的花开了，一定很美～\"},")
	examples.append("    {\"type\": \"character_action\", \"character\": \"sister\", \"action\": \"bounce\"},")
	examples.append("    {\"type\": \"set_expression\", \"character\": \"sister\", \"expression\": \"very_happy\"},")
	examples.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"哥哥陪我多逛一会儿好不好？\"}")
	examples.append("  ]")
	examples.append("}")
	examples.append("")
	examples.append("## 选项分支的完整示例（关键！）")
	examples.append("假设剧情到达一个需要玩家选择的时刻：")
	examples.append("{")
	examples.append("  \"commands\": [")
	examples.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"哥哥，你觉得我该怎么办？\"},")
	examples.append("    {\"type\": \"show_choices\", \"choices\": [{\"id\":1,\"text\":\"鼓励她\"}, {\"id\":2,\"text\":\"劝她放弃\"}]}")
	examples.append("  ]")
	examples.append("}")
	examples.append("当玩家选择后，你收到的事件为“玩家选择了选项 ID: 1，选项文本: 鼓励她”，此时你应该立即输出角色对这个选择的即时反应：")
	examples.append("{")
	examples.append("  \"commands\": [")
	examples.append("    {\"type\": \"show_dialogue\", \"character\": \"sister\", \"text\": \"真的吗？哥哥你觉得我可以做到吗？[shake rate=10 level=3]我好感动...\"},")
	examples.append("    {\"type\": \"set_expression\", \"character\": \"sister\", \"expression\": \"happy\"}")
	examples.append("  ]")
	examples.append("}")
	return examples


# ---------- 用户提示构建 ----------
func _build_user_prompt(input_str: String) -> String:
	var chapter := _determine_current_chapter()
	var chapter_info = MAIN_STORY_LINE.get(chapter, {})

	var history_block := _get_recent_dialogue_history(50)
	var state_block := _get_current_game_state()
	var flags_block := _get_flags_state()

	var event_desc := ""
	if input_str == "__start__":
		event_desc = "新游戏开始，请生成开场剧情。"
	elif input_str == "__continue__":
		event_desc = "玩家点击继续，请推进剧情。"
	elif input_str.begins_with("__choice__:"):
		event_desc = "玩家做出了选择：%s，请根据这个选择继续剧情。" % input_str.trim_prefix("__choice__:")
	else:
		event_desc = "未知事件。"

	var prompt := """
当前章节: %s (阶段: %s)
章节目标: %s
建议关键事件: %s

%s

%s

%s

事件: %s
请生成下一段剧情指令（2-4 条），确保朝着章节目标推进，避免重复之前的对话。
""" % [
		chapter,
		chapter_info.get("title", "未知"),
		chapter_info.get("goal", "推进剧情"),
		JSON.stringify(chapter_info.get("key_events", [])),
		state_block,
		flags_block,
		history_block,
		event_desc
	]
	return prompt


func _determine_current_chapter() -> String:
	var current_scene := ""
	if GameManager:
		current_scene = GameManager.current_scene

	var affection_sister := 0
	if GameManager:
		affection_sister = GameManager.get_affection("sister")

	if affection_sister >= 80 or current_scene == "ending":
		return "ending"
	elif affection_sister >= 50 or current_scene == "chapter3":
		return "chapter3"
	elif affection_sister >= 30 or current_scene == "chapter2":
		return "chapter2"
	elif affection_sister >= 20 or current_scene == "chapter1":
		return "chapter1"
	else:
		return "prologue"


func _get_current_game_state() -> String:
	var bg := ""
	if BackgroundManager:
		var bg_id = BackgroundManager.current_background_id
		if BackgroundManager.background_database.has(bg_id):
			bg = BackgroundManager.background_database[bg_id].display_name

	var characters := ""
	if CharacterManager:
		characters = JSON.stringify(CharacterManager.get_active_roles_data())

	var affections := ""
	if GameManager:
		affections = JSON.stringify(GameManager.variables)

	return "当前场景: %s\n舞台上角色: %s\n变量: %s" % [bg, characters, affections]


func _get_flags_state() -> String:
	if GameManager and "flags" in GameManager:
		return "剧情标记: " + JSON.stringify(GameManager.flags)
	return "剧情标记: 无"


func _get_recent_dialogue_history(count: int = 10) -> String:
	if not GameManager or GameManager.dialogue_history.is_empty():
		return "暂无对话历史"

	var start_index: int = max(0, GameManager.dialogue_history.size() - count)
	var recent := GameManager.dialogue_history.slice(start_index)
	var lines: Array[String] = []
	lines.append("最近对话记录（共 %d 条）：" % recent.size())

	for entry in recent:
		var char_name: String = entry.get("character", "")
		var text: String = entry.get("text", "")
		var entry_type: String = entry.get("type", "dialogue")

		if entry_type == "choice":
			lines.append("- 玩家选择了：%s" % text)
		elif entry_type == "long_dialogue":
			lines.append("- 旁白（长对话）：%s" % text)
		elif char_name == "":
			lines.append("- 旁白：%s" % text)
		else:
			lines.append("- %s: %s" % [char_name, text])

	return "\n".join(lines)


# ---------- 工具函数 ----------
func _get_base_url() -> String:
	var env_base_url := _get_env_value("MOONSHOT_BASE_URL")
	return env_base_url if env_base_url != "" else base_url


func _get_model() -> String:
	var env_model := _get_env_value("MOONSHOT_MODEL")
	return env_model if env_model != "" else model


func _get_env_value(key: String) -> String:
	var system_value := OS.get_environment(key)
	if system_value != "":
		return system_value
	return str(_env_values.get(key, ""))


func _load_env_file() -> void:
	_env_values.clear()
	var path := env_file_path
	if not FileAccess.file_exists(path) and FileAccess.file_exists(_FALLBACK_ENV_FILE_PATH):
		path = _FALLBACK_ENV_FILE_PATH
	if not FileAccess.file_exists(path):
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[AIManager] 无法读取 env 文件: %s" % path)
		return

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("export "):
			line = line.trim_prefix("export ").strip_edges()

		var separator_index := line.find("=")
		if separator_index <= 0:
			continue

		var key := line.substr(0, separator_index).strip_edges()
		var value := line.substr(separator_index + 1).strip_edges()
		value = _strip_env_quotes(value)
		if key != "":
			_env_values[key] = value


func _strip_env_quotes(value: String) -> String:
	if value.length() < 2:
		return value
	var starts_with_single_quote := value.begins_with("'") and value.ends_with("'")
	var starts_with_double_quote := value.begins_with("\"") and value.ends_with("\"")
	if starts_with_single_quote or starts_with_double_quote:
		return value.substr(1, value.length() - 2)
	return value


func _finish_requesting() -> void:
	if has_node("/root/DialogueManager"):
		DialogueManager.is_requesting = false


func _resolve_choice_text(choice_id: int) -> String:
	if not has_node("/root/DialogueManager"):
		return ""

	var scene = DialogueManager.get_dialogue_scene()
	if scene == null:
		return ""

	var choices = scene.get("current_choices")
	if not choices is Array:
		return ""

	for choice in choices:
		if choice is Dictionary and str(choice.get("id", "")) == str(choice_id):
			return str(choice.get("text", ""))

	var index := choice_id - 1
	if index >= 0 and index < choices.size() and choices[index] is Dictionary:
		return str(choices[index].get("text", ""))

	return ""


func _build_choice_event() -> String:
	if _pending_choice_text == "":
		return "__choice__:%d" % _pending_choice_id
	return "__choice__:%d:%s" % [_pending_choice_id, _pending_choice_text]


func _normalize_json_content(content: String) -> String:
	var result := content.strip_edges()
	if result.begins_with("```json"):
		result = result.trim_prefix("```json").strip_edges()
	elif result.begins_with("```"):
		result = result.trim_prefix("```").strip_edges()
	if result.ends_with("```"):
		result = result.trim_suffix("```").strip_edges()
	return result


func _recover_with_dialogue(reason: String) -> void:
	push_warning(reason)
	if not has_node("/root/ScriptEngine"):
		return
	ScriptEngine.execute_commands([
		{
			"type": "show_dialogue",
			"character": "",
			"text": _FALLBACK_TEXT
		}
	])

# -----强化学习规则-----
func _load_rules() -> Array:
	if not FileAccess.file_exists(MEMORY_FILE):
		return []
	var file := FileAccess.open(MEMORY_FILE, FileAccess.READ)
	if file == null:
		return []
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) == OK:
		var data = json.data
		if data is Array:
			return data
	return []

func _save_rules(rules: Array) -> void:
	var json_string := JSON.stringify(rules, "\t")
	var file := FileAccess.open(MEMORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	else:
		push_error("[AIManager] 无法写入 ai_rules.json")

func add_user_rule(rule_text: String) -> void:
	var rules := _load_rules()
	var new_rule := {
		"rule": rule_text,
		"timestamp": Time.get_datetime_string_from_system()
	}
	rules.append(new_rule)
	_save_rules(rules)
	print("[AIManager] 已添加新规则：", rule_text)
