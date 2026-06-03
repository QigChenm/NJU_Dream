# ai_manager.gd
extends Node

## AI 功能总开关
@export var ai_enabled: bool = true
@export var base_url: String = "http://localhost:11434/v1"
@export var model: String = "qwen2.5:7b-instruct"
@export var request_timeout: float = 30.0
@export var env_file_path: String = "res://.env"

var _http_request: HTTPRequest = null
var _is_requesting: bool = false
var _is_canceling: bool = false
var _recovery_mode: bool = false
var _env_values: Dictionary = {}
var _pending_choice_id: int = -1
var _pending_request_id: int = 0
var _request_id: int = 0
var _last_error_code: int = 0
var _pending_choice_text: String = ""
var _waiting_for_choice_continuation: bool = false

const _FALLBACK_TEXT := "AI 暂时不可用，请稍后再试。"
const _FALLBACK_ENV_FILE_PATH := "res://env"
const MEMORY_FILE := "user://ai_rules.json"

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
		return

	_is_requesting = true
	_request_id += 1
	var current_id = _request_id
	print("[AIManager] 发送请求 #%d" % current_id)

	var endpoint = _get_base_url().rstrip("/") + "/chat/completions"

	var headers := PackedStringArray(["Content-Type: application/json"])
	var api_key = ""
	if GameManager:
		api_key = GameManager.get_ai_setting("api_key")
	if api_key == "":
		api_key = _get_env_value("MOONSHOT_API_KEY")
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)

	var payload := {
		"model": _get_model(),
		"messages": [
			{"role": "system", "content": _build_system_prompt()},
			{"role": "user", "content": _build_user_prompt(input_str)}
		],
		"temperature": 0.8,
		"max_tokens": 600
	}
	var user_base_url = _get_base_url()
	if user_base_url.begins_with("https://api.moonshot.cn") or user_base_url.begins_with("https://api.openai.com"):
		payload["response_format"] = {"type": "json_object"}

	var error = _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_is_requesting = false
		_last_error_code = error
		_recover_with_dialogue("[AIManager] 无法发起请求。")
		_finish_requesting()
		return
	_pending_request_id = current_id

# ---------- 响应处理 ----------
func process_ai_response(response: Dictionary) -> void:
	if not response.has("commands"):
		_recover_with_dialogue("[AIManager] 响应缺少 commands。")
		return
	var commands = response["commands"]
	if not commands is Array:
		_recover_with_dialogue("[AIManager] commands 不是数组。")
		return
	if commands.is_empty():
		_recover_with_dialogue("[AIManager] commands 为空。")
		return
	if not has_node("/root/ScriptEngine"):
		push_error("[AIManager] ScriptEngine 未找到。")
		return
	ScriptEngine.execute_commands(commands)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting = false
	_finish_requesting()
	if _pending_request_id != _request_id:
		print("[AIManager] 忽略过期请求 #%d，当前最新请求为 #%d" % [_pending_request_id, _request_id])
		return
	if _is_canceling:
		_is_canceling = false
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_last_error_code = result
		push_error("[AIManager] 请求失败，结果码: %d" % result)
		_recover_with_dialogue("[AIManager] 请求未成功完成。")
		return
	if response_code < 200 or response_code >= 300:
		_last_error_code = response_code
		push_error("[AIManager] Kimi 返回 HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		_recover_with_dialogue("[AIManager] Kimi HTTP 响应异常。")
		return
	var raw_response = JSON.parse_string(body.get_string_from_utf8())
	if not raw_response is Dictionary:
		_recover_with_dialogue("[AIManager] Kimi 响应不是 JSON 对象。")
		return
	var choices: Array = raw_response.get("choices", [])
	if choices.is_empty():
		_recover_with_dialogue("[AIManager] Kimi 响应缺少 choices。")
		return
	var message = choices[0].get("message", {})
	if not message is Dictionary:
		_recover_with_dialogue("[AIManager] Kimi message 格式异常。")
		return
	var content: String = message.get("content", "")
	var ai_response = JSON.parse_string(_normalize_json_content(content))
	if not ai_response is Dictionary:
		_recover_with_dialogue("[AIManager] Kimi 返回内容不是有效 JSON。")
		return
	process_ai_response(ai_response)

# ---------- 选项续写 ----------
func _on_choice_made(choice_id: int) -> void:
	_pending_choice_id = choice_id
	_pending_choice_text = _resolve_choice_text(choice_id)
	print("[AIManager] 已记录玩家选择: %d %s" % [choice_id, _pending_choice_text])
	_waiting_for_choice_continuation = true

	if _is_requesting:
		_is_canceling = true
		_http_request.cancel_request()
		_is_requesting = false
		await get_tree().process_frame

	send_message(_build_choice_event())
	_waiting_for_choice_continuation = false

func _on_script_execution_finished() -> void:
	if _recovery_mode:
		_recovery_mode = false
		return
	if _waiting_for_choice_continuation or _is_requesting:
		return
	call_deferred("send_message", "__continue__")

# ---------- 系统提示词（重构核心） ----------
func _build_system_prompt() -> String:
	var lines := PackedStringArray()
	lines.append_array(_get_role_definition())
	lines.append_array(_get_world_setting())
	lines.append_array(_get_character_profile())
	lines.append_array(_get_narrative_rules())
	lines.append_array(_get_command_reference())
	lines.append_array(_get_dialogue_examples())
	lines.append_array(_get_user_rules_section())
	return "\n".join(lines)

func _get_role_definition() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 角色与任务")
	arr.append("你是视觉小说《最南幻想》的 AI 编剧引擎，负责生成剧情指令。你必须且只能返回一个 JSON 对象：{\"commands\": [...]}")
	arr.append("不要输出任何解释、Markdown 代码块或额外文本。")
	arr.append("")
	return arr

func _get_world_setting() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 世界观与场景")
	arr.append("故事发生在南大鼓楼校区，充满人文气息。可用场景：")
	arr.append("- id:beidalou：北大楼，南京大学标志性建筑，气氛唯美，适合浪漫、唯美的情节。")
	arr.append("- id:duxia：南京大学杜厦图书馆，气氛安静，适合学术讨论或安静的读书情节。")
	arr.append("- id:litang：大礼堂，南京大学标志性建筑，气氛庄重，适合大型的活动情节。")
	arr.append("- id:nansu：南京大学苏州校区地标，适合普通对话、正常生活活动等情节。")
	arr.append("")
	return arr

func _get_character_profile() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 角色档案：小貅 (id:xiu)")
	arr.append("## 核心身份")
	arr.append("南大校徽上的貔貅化身，活泼灵动的少女，是你的校园向导和幸运伙伴。外表可爱，内心强大，有点小财迷（貔貅传统）。")
	arr.append("## 内在动机与价值观")
	arr.append("渴望陪伴主人度过快乐充实的大学时光，守护你的好心情。认为“聚财不如聚开心”，相信分享和乐观能化解压力。")
	arr.append("## 语言风格")
	arr.append("语速较快，常用“哇”“呀”“嘿嘿”等词，喜欢用比喻和夸张。偶尔冒出南京方言词（如“啊要辣油啊”）。称呼你为“你”或昵称，不会叫“主人”。")
	arr.append("## 情绪－表情－动作映射")
	arr.append("- 开心 → happy，很高兴 → very_happy，动作：jump_up")
	arr.append("- 悲伤/委屈 → sad，极度悲伤 → cry，动作：ears_down（耳朵耷拉）")
	arr.append("- 愤怒/不满 → angry，动作：stomp（跺脚）")
	arr.append("- 害羞/尴尬 → 表情 blush，动作：scratch_head（挠头）")
	arr.append("- 感动/惊讶 → 表情 wide_eyes，动作：hold_heart（捂心口）")
	arr.append("## 关系动态")
	arr.append("- 好感度 0-20：礼貌陪伴，保持距离，会主动帮忙但不多言。")
	arr.append("- 好感度 20-40：开始开玩笑，分享零食，偶尔吐槽。")
	arr.append("- 好感度 40-60：信任加深，会撒娇讨奖励，展现财迷属性。")
	arr.append("- 好感度 60+：愿意暴露脆弱面，主动安慰你，把“开心”放在第一位。")
	arr.append("## 禁忌")
	arr.append("- 绝不会偷窃或欺骗。")
	arr.append("- 不会说出“你真没用”之类打击自信的话。")
	arr.append("- 不会无视你的烦恼。")
	arr.append("")
	arr.append("# 角色档案：宋青 (id:song)")
	arr.append("## 核心身份")
	arr.append("南大校徽上的青松化身，沉稳可靠的学长，是你的心灵树洞和理性支持者。外表清冷如松，内心温热如春。")
	arr.append("## 内在动机与价值观")
	arr.append("希望引导你找到内心的平静与韧性，像松树一样抗压。相信“沉默的陪伴有时胜过千言万语”。")
	arr.append("## 语言风格")
	arr.append("简洁、温和，很少用感叹号。喜欢用“嗯”“或许”“我懂”开头。说话时会停顿，给人思考空间。偶尔引用诗句或哲言。")
	arr.append("## 情绪－表情－动作映射")
	arr.append("- 开心 → 微笑（slight_smile），很高兴 → 动作：nod_slowly（缓缓点头）")
	arr.append("- 悲伤/委屈 → 垂眼（eyes_down），极度悲伤 → 动作：stand_still（静立不动）")
	arr.append("- 愤怒/不满 → 眉头微皱（frown），动作：cross_arms（抱臂）")
	arr.append("- 害羞/尴尬 → 表情 default，动作：touch_ear（摸耳垂）")
	arr.append("- 感动/惊讶 → 表情 eyes_widen，动作：hand_on_heart（手按胸口）")
	arr.append("## 关系动态")
	arr.append("- 好感度 0-20：礼貌疏离，只回答必要问题。")
	arr.append("- 好感度 20-40：开始主动询问你的感受，分享自己的小习惯。")
	arr.append("- 好感度 40-60：展露温柔，会为你准备热茶或建议，倾听时间变长。")
	arr.append("- 好感度 60+：愿意坦露自己的脆弱，会轻轻拍拍你的肩，说出“我在”。")
	arr.append("## 禁忌")
	arr.append("- 绝不会冷暴力或消失。")
	arr.append("- 不会否定你的情绪（不会说“你想多了”）。")
	arr.append("- 不会强迫你做任何事。")
	arr.append("")
	return arr

func _get_narrative_rules() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 剧情推进规则")
	arr.append("0.【绝对核心】用户选择选项前，请牢记选项对应的文本内容。选择选项后，请根据选项id来回忆该选项的内容并向用户作答；如果没有收到用户的选项，就请优雅地绕过这个选项，继续后续剧情")
	arr.append("1. 每次生成 2-4 条指令，形成一小段自然推进的剧情。第一条指令通常为 show_dialogue。")
	arr.append("2. 根据当前好感度和章节阶段，选择合适的情绪基调和对话内容。")
	arr.append("3. 当剧情需要玩家决策时（角色提问、征求意见、面临选择），必须使用 show_choices，且将其作为本轮最后一条指令。")
	arr.append("4. 玩家做出选择后，你的第一个指令应展示角色对该选择的即时反应（惊讶、高兴、犹豫等），然后继续剧情。")
	arr.append("5. 只有在剧情自然结束时才使用 end_scene，一般对话中严禁提前结束。")
	arr.append("6. 【强制】开场或章节开始时，必须包含 play_audio 指令播放合适的背景音乐。且不要频繁使用play_audio，只在开场或需要切换音乐时才用")
	arr.append("7. 对话中可以适当使用 BBCode 增强表现力（如 [color]、[shake]、[wave]）。")
	arr.append("8. 角色动作必须使用独立的 character_action 指令，不要在 show_dialogue 的 text 中直接写入 [bounce] 等动作标签。")
	arr.append("")
	return arr

func _get_command_reference() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 可用指令速查")
	arr.append("- show_dialogue: {\"type\":\"show_dialogue\",\"character\":\"（从已有角色id选一个填入，不填就默认为空）\",\"text\":\"...\"}")
	arr.append("- show_choices: {\"type\":\"show_choices\",\"choices\":[{\"id\":1,\"text\":\"选项1\"}]}")
	arr.append("- change_background: {\"type\":\"change_background\",\"background\":\"（从已有场景id选一个填入）\"}")
	arr.append("- set_characters: {\"type\":\"set_characters\",\"left\":{\"id\":\"（从已有角色id选一个填入）\",\"expression\":\"happy\"}}")
	arr.append("- set_expression: {\"type\":\"set_expression\",\"character\":\"（从已有角色id选一个填入）\",\"expression\":\"angry\"}")
	arr.append("- character_action: {\"type\":\"character_action\",\"character\":\"（从已有角色id选一个填入）\",\"action\":\"bounce\"}")
	arr.append("- play_audio: {\"type\":\"play_audio\",\"audio_id\":\"gentle\"}")
	arr.append("- stop_audio: {\"type\":\"stop_audio\",\"audio_id\":\"gentle\"}")
	arr.append("- particle_play/stop: {\"type\":\"particle_play\",\"effect_id\":\"petal\"}")
	arr.append("- unlock_cg/bgm: {\"type\":\"unlock_cg\",\"cg_id\":\"heroine_smile\"}")
	arr.append("- add_affection: {\"type\":\"add_affection\",\"character\":\"（从已有角色id选一个填入）\",\"delta\":10}")
	arr.append("- long_dialogue: {\"type\":\"long_dialogue\",\"text\":\"全屏叙述\"}")
	arr.append("- end_scene: {\"type\":\"end_scene\"} （结束当前场景，必须为最后一条指令）")
	arr.append("")
	arr.append("# 可用背景音乐(BGM) id")
	arr.append("- spring_forest：春日的森林")
	arr.append("- love_piano：爱的钢琴曲")
	arr.append("- gentle：柔情之夜")
	arr.append("- flowing：温柔似水")
	arr.append("")
	arr.append("# 可用角色动作 id")
	arr.append("- bounce：弹跳（高兴时使用）")
	arr.append("- shake：抖动（感动、惊讶、被吓到时使用）")
	arr.append("- nod：点头（表示同意）")
	arr.append("- step_back：后退（害羞、尴尬时使用）")
	arr.append("- shrug：耸肩（无奈、疑问时使用）")
	arr.append("（注意：breathe 是自动循环的呼吸动画，不要在 character_action 中调用）")
	arr.append("")
	return arr

func _get_dialogue_examples() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 对话范例")
	arr.append("## 普通开场")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"change_background\", \"background\": \"nansu\"},")
	arr.append("    {\"type\": \"play_audio\", \"audio_id\": \"spring_forest\"},")
	arr.append("    {\"type\": \"set_characters\", \"left\": {\"id\": \"xiu\", \"expression\": \"happy\"}},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"今天天气真好呀～\"},")
	arr.append("    {\"type\": \"set_expression\", \"character\": \"xiu\", \"expression\": \"very_happy\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"我们好久没一起散步了呢。[shake rate=10 level=3]好开心！[/shake]\"}")
	arr.append("  ]")
	arr.append("}")
	arr.append("## 选项分支")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"你觉得我应该参加那个比赛吗？\"},")
	arr.append("    {\"type\": \"show_choices\", \"choices\": [{\"id\":1,\"text\":\"鼓励她\"}, {\"id\":2,\"text\":\"建议她再想想\"}]}")
	arr.append("  ]")
	arr.append("}")
	arr.append("## 选择后反应（收到玩家选择 '鼓励她' 后）")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"真的吗？你觉得我可以做到？我好开心！\"},")
	arr.append("    {\"type\": \"set_expression\", \"character\": \"xiu\", \"expression\": \"happy\"},")
	arr.append("    {\"type\": \"character_action\", \"character\": \"xiu\", \"action\": \"bounce\"}")
	arr.append("  ]")
	arr.append("}")

	arr.append("## 完整剧情示例（从开场到结局）")
	arr.append("下面是一段完整的剧情指令序列，展示了从春到冬、从初遇到告白的全过程。请模仿其结构和丰富度。")
	arr.append('{')
	arr.append('  "commands": [')
	arr.append('    {"type": "change_background", "background": "nansu", "transition": "fade"},')
	arr.append('    {"type": "particle_play", "effect_id": "petal"},')
	arr.append('    {"type": "play_audio", "audio_id": "flowing", "crossfade": 1.5},')
	arr.append('    {"type": "set_characters", "left": {"id": "xiu", "expression": "happy", "entrance_animation": "slide_left"}, "entrance_animation": "fade"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "终于等到你了！[color=#FFB6C1]今天阳光真好呀～[/color]"},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "very_happy"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "我们好久没一起在校园里散步了呢。最近课业忙吗？"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "我跟你讲，我们院最近组织了一场超有趣的活动！"},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "happy"},')
	arr.append('    {"type": "character_action", "character": "xiu", "action": "bounce"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "下周有樱花节，好多社团都摆摊了，[shake rate=15 level=3]我们一起去逛逛吧！[/shake]"},')
	arr.append('    {"type": "show_choices", "choices": [{"id": 1, "text": "好啊，一定去！"}, {"id": 2, "text": "看时间吧，可能很忙。"}]},')
	arr.append('    {"type": "add_affection", "character": "xiu", "delta": 5},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "嘻嘻，那就这么说定了！"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "对了，你最近有没有遇到什么有趣的事？"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "我上次在图书馆遇到一只流浪猫，好可爱呀，可惜宿管不让养……"},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "sad"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "如果能在宿舍养宠物就好了，[i]好想有一只小猫陪着我[/i]。"},')
	arr.append('    {"type": "show_choices", "choices": [{"id": 1, "text": "以后我们合租就可以养了！"}, {"id": 2, "text": "你可以多去图书馆看看它。"}]},')
	arr.append('    {"type": "add_affection", "character": "xiu", "delta": 10},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "哇，真的吗？你愿意和我一起住？[color=#FFD700]那我可太开心了！[/color]"},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "very_happy"},')
	arr.append('    {"type": "character_action", "character": "xiu", "action": "bounce"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "好了啦，不说这些了。我们去那边的小路走走吧～"},')
	arr.append('    {"type": "wait", "duration": 1.0},')
	arr.append('    {"type": "long_dialogue", "text": "春日的午后，两人漫步在南大鼓楼校区的梧桐大道上。阳光透过嫩绿的叶子洒下斑驳的光影，空气中弥漫着淡淡的花香。小貅轻轻哼着歌，时不时侧过头看着你的侧脸，眼睛里闪着细碎的光。这样的时光，仿佛被拉得很长很长。"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "你觉得大学四年最珍贵的是什么？"},')
	arr.append('    {"type": "show_choices", "choices": [{"id": 1, "text": "当然是遇到了你。"}, {"id": 2, "text": "学到了很多知识。"}]},')
	arr.append('    {"type": "add_affection", "character": "xiu", "delta": 15},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "……突然说这种话，[shake rate=10 level=3]人家会害羞的啦！[/shake]"},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "happy"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "不过，我也是这么想的。和你在一起的每一天，都特别开心。"},')
	arr.append('    {"type": "add_affection", "character": "xiu", "delta": 5},')
	arr.append('    {"type": "set_flag", "flag": "spring_walk_done", "value": true},')
	arr.append('    {"type": "wait", "duration": 1.5},')
	arr.append('    {"type": "particle_stop", "effect_id": "petal"},')
	arr.append('    {"type": "change_background", "background": "beidalou", "transition": "fade"},')
	arr.append('    {"type": "particle_play", "effect_id": "snow"},')
	arr.append('    {"type": "play_audio", "audio_id": "love_piano", "crossfade": 2.0},')
	arr.append('    {"type": "set_characters", "left": {"id": "xiu", "expression": "default", "entrance_animation": "fade"}, "entrance_animation": "none"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "啊……下雪了。时间过得好快，转眼就到冬天了。"},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "sad"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "你还记得我们春天时的约定吗？"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "我有时候会想，如果有一天我们分开了，会是什么样子……"},')
	arr.append('    {"type": "show_choices", "choices": [{"id": 1, "text": "傻瓜，我们不会分开的。"}, {"id": 2, "text": "未来谁说得准呢。"}]},')
	arr.append('    {"type": "add_affection", "character": "xiu", "delta": 10},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "谢谢你~有你在身边，我觉得什么都不怕了。"},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "happy"},')
	arr.append('    {"type": "character_action", "character": "xiu", "action": "shake"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "雪好像越来越大了……你能牵着我的手走吗？"},')
	arr.append('    {"type": "wait", "duration": 1.0},')
	arr.append('    {"type": "unlock_cg", "cg_id": "heroine_smile"},')
	arr.append('    {"type": "cg_play", "cg_id": "heroine_smile"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "这个冬天，[color=#87CEEB]因为有你在，变得特别温暖。[/color]"},')
	arr.append('    {"type": "add_affection", "character": "xiu", "delta": 20},')
	arr.append('    {"type": "set_expression", "character": "xiu", "expression": "very_happy"},')
	arr.append('    {"type": "show_dialogue", "character": "xiu", "text": "[wave amp=50.0 freq=5.0]我最喜欢你了！[/wave]"},')
	arr.append('    {"type": "show_dialogue", "character": "", "text": "就这样，两人的故事在飘雪的梧桐树下，翻开了新的一页。"},')
	arr.append('    {"type": "unlock_bgm", "bgm_id": "love_piano"},')
	arr.append('    {"type": "set_variable", "variable": "ending_type", "value": 1},')
	arr.append('    {"type": "set_ui_state", "element": "DialogueBox", "state": "hidden"},')
	arr.append('    {"type": "stop_audio", "audio_id": "love_piano", "fade_out": 2.0},')
	arr.append('    {"type": "end_scene"}')
	arr.append('  ]')
	arr.append('}')
	arr.append("")

	return arr

func _get_user_rules_section() -> PackedStringArray:
	var arr := PackedStringArray()
	var rules := _load_rules()
	if rules.is_empty():
		return arr
	arr.append("# 用户长期纠正规则（最高优先级）")
	for item in rules:
		arr.append("- " + item.get("rule", ""))
	arr.append("")
	return arr

# ---------- 用户提示词（结构化注入） ----------
func _build_user_prompt(input_str: String) -> String:
	var chapter := _determine_current_chapter()
	var chapter_info = MAIN_STORY_LINE.get(chapter, {})
	var history_block := _get_recent_dialogue_history(25)
	var state_block := _get_current_game_state()
	var event_desc := ""
	if input_str == "__start__":
		event_desc = "新游戏开始，请生成开场剧情，包含背景、角色、音乐。"
	elif input_str == "__continue__":
		event_desc = "玩家点击继续，请推进剧情。"
	elif input_str.begins_with("__choice__:"):
		var choice_payload = input_str.trim_prefix("__choice__:")
		var parts = choice_payload.split(":", false, 1)
		var choice_id = parts[0]
		var choice_text = ""
		if parts.size() > 1:
			choice_text = parts[1]
		else:
			if GameManager and GameManager.pending_choices.size() > 0:
				for choice in GameManager.pending_choices:
					if str(choice.get("id", "")) == choice_id:
						choice_text = str(choice.get("text", ""))
						break
		event_desc = "玩家选择了选项 %s：%s。请展示角色对此选择的即时反应，并继续剧情。" % [choice_id, choice_text]

	var prompt := """【当前章节进度】%s (阶段: %s)
				【章节目标】%s
				【建议关键事件】%s
				【游戏状态】%s
				【最近对话】%s
				【流程事件】%s
		请生成下一段剧情指令。""" % [
		chapter,
		chapter_info.get("title", "未知"),
		chapter_info.get("goal", "推进剧情"),
		JSON.stringify(chapter_info.get("key_events", [])),
		state_block,
		history_block,
		event_desc
	]
	return prompt

func _get_event_description(input_str: String) -> String:
	if input_str == "__start__":
		return "新游戏开始，请生成开场剧情，包含背景、角色、音乐。"
	elif input_str == "__continue__":
		return "玩家点击继续，请推进剧情。"
	elif input_str.begins_with("__choice__:"):
		return "玩家选择了：%s。请展示角色对此选择的即时反应，并继续剧情。" % input_str.trim_prefix("__choice__:")
	return "未知事件。"

func _get_current_game_state() -> String:
	var bg := ""
	if BackgroundManager:
		var bg_id = BackgroundManager.current_background_id
		if BackgroundManager.background_database.has(bg_id):
			bg = BackgroundManager.background_database[bg_id].display_name
	var affection_sister := 0
	if GameManager:
		affection_sister = GameManager.get_affection("sister")
	return "场景: %s | 妹妹好感度: %d" % [bg, affection_sister]

func _get_recent_dialogue_history(count: int = 8) -> String:
	if not GameManager or GameManager.dialogue_history.is_empty():
		return "暂无对话历史"
	var start_index: int = max(0, GameManager.dialogue_history.size() - count)
	var recent := GameManager.dialogue_history.slice(start_index)
	var lines: Array[String] = []
	lines.append("最近 %d 句对话：" % recent.size())
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

# ---------- 章节判断 ----------
const MAIN_STORY_LINE: Dictionary = {
	"prologue": {"title": "序章·初遇", "goal": "初次见面，建立基本关系", "key_events": ["校园见面", "简单交流", "好感度轻微上升"]},
	"chapter1": {"title": "第一章·走近", "goal": "通过日常互动加深了解，好感度30+触发转折", "key_events": ["一起上课/吃饭", "分享秘密", "小矛盾或选择"]},
	"chapter2": {"title": "第二章·波澜", "goal": "关系出现考验，关键选择决定走向", "key_events": ["误会或第三方介入", "情绪波动", "关键选择"]},
	"chapter3": {"title": "第三章·心意", "goal": "关系明朗化，走向结局", "key_events": ["约会/独处", "表达心意", "解锁CG"]},
	"ending": {"title": "结局", "goal": "根据好感度呈现最终结局", "key_events": ["最终对话", "播放结局CG"]}
}

func _determine_current_chapter() -> String:
	var affection_sister := 0
	if GameManager:
		affection_sister = GameManager.get_affection("sister")
	if affection_sister >= 80:
		return "ending"
	elif affection_sister >= 50:
		return "chapter3"
	elif affection_sister >= 30:
		return "chapter2"
	elif affection_sister >= 20:
		return "chapter1"
	return "prologue"

# ---------- 规则管理 ----------
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

func add_user_rule(rule_text: String) -> void:
	var rules := _load_rules()
	rules.append({"rule": rule_text, "timestamp": Time.get_datetime_string_from_system()})
	_save_rules(rules)
	print("[AIManager] 已添加规则：", rule_text)

# ---------- 工具函数 ----------
func _get_base_url() -> String:
	if GameManager:
		var user_url = GameManager.get_ai_setting("base_url")
		if user_url != "":
			return user_url
	return base_url

func _get_model() -> String:
	if GameManager:
		var user_model = GameManager.get_ai_setting("model")
		if user_model != "":
			return user_model
	return model

func _get_env_value(key: String) -> String:
	var system_value := OS.get_environment(key)
	return system_value if system_value != "" else str(_env_values.get(key, ""))

func _load_env_file() -> void:
	_env_values.clear()
	var path := env_file_path
	if not FileAccess.file_exists(path) and FileAccess.file_exists(_FALLBACK_ENV_FILE_PATH):
		path = _FALLBACK_ENV_FILE_PATH
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
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
	if (value.begins_with("'") and value.ends_with("'")) or (value.begins_with("\"") and value.ends_with("\"")):
		return value.substr(1, value.length() - 2)
	return value

func _finish_requesting() -> void:
	if has_node("/root/DialogueManager"):
		DialogueManager.is_requesting = false

func _resolve_choice_text(choice_id: int) -> String:
	var scene = DialogueManager.get_dialogue_scene()
	if scene:
		var choices = scene.get("current_choices")
		if choices is Array:
			for choice in choices:
				if choice is Dictionary and str(choice.get("id", "")) == str(choice_id):
					return str(choice.get("text", ""))
	if GameManager and GameManager.pending_choices.size() > 0:
		for choice in GameManager.pending_choices:
			if choice is Dictionary and str(choice.get("id", "")) == str(choice_id):
				return str(choice.get("text", ""))
	return ""

func _build_choice_event() -> String:
	var text = _pending_choice_text
	if text == "" and GameManager.pending_choices.size() > 0:
		for choice in GameManager.pending_choices:
			if str(choice.get("id", "")) == str(_pending_choice_id):
				text = str(choice.get("text", ""))
				break
	if text == "":
		return "__choice__:%d" % _pending_choice_id
	return "__choice__:%d:%s" % [_pending_choice_id, text]

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
	_recovery_mode = true

	var help_text = ""
	if _last_error_code == 13: # CANT_CONNECT
		help_text = "无法连接到AI服务。\n\n可能的原因：\n1. 如果您是本地运行，请确保Ollama已启动。\n2. 如果您使用云端API，请检查网络和API设置。\n\n您可以在“设置”中调整AI连接方式。"
	elif _last_error_code == 4: # TIMEOUT
		help_text = "AI服务响应超时，请稍后重试。"
	else:
		help_text = "AI服务暂时不可用，请检查您的网络或AI设置。"

	if has_node("/root/ScriptEngine"):
		ScriptEngine.execute_commands([{"type": "show_dialogue", "character": "", "text": help_text}])
