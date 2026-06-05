# ai_manager.gd
extends Node

## AI 功能总开关
@export var ai_enabled: bool = true
@export var base_url: String = "http://localhost:11434"
@export var model: String = "qwen2.5:7b-instruct"
@export var request_timeout: float = 30.0

var _http_request: HTTPRequest = null
var _is_requesting: bool = false
var _is_ollama_request: bool = false
var _is_canceling: bool = false
var _recovery_mode: bool = false
var _pending_choice_id: int = -1
var _pending_request_id: int = 0
var _request_id: int = 0
var _last_error_code: int = 0
var _pending_choice_text: String = ""
var _waiting_for_choice_continuation: bool = false
var _prediction_cache: Dictionary = {}
var _prediction_requests: Dictionary = {}
var _active_prediction_context_key: String = ""
var _warmup_request: HTTPRequest = null
var _warmup_start_response: Dictionary = {}
var _warmup_start_pending: bool = false
var _warmup_consume_pending: bool = false

const _FALLBACK_TEXT := "AI 暂时不可用，请稍后再试。"
const DEFAULT_OUTPUT_TOKENS := 1200
const MAX_PREDICTION_REQUESTS := 3
const MEMORY_FILE := "user://ai_rules.json"
const VALID_CHARACTER_ACTIONS := ["bounce", "shake", "nod", "step_back", "shrug"]
const ALLOWED_TEXT_BBCODE_TAGS := ["b", "i", "u", "color", "wave", "shake"]
const TEXT_ACTION_TAG_MAP := {
	"bounce": "bounce",
	"jump_up": "bounce",
	"jump": "bounce",
	"nod": "nod",
	"nod_slowly": "nod",
	"step_back": "step_back",
	"ears_down": "step_back",
	"scratch_head": "step_back",
	"shrug": "shrug",
	"stomp": "shake",
	"hold_heart": "shake",
	"hand_on_heart": "shake",
	"cross_arms": "shrug",
	"stand_still": "step_back",
	"touch_ear": "shrug"
}

# ---------- 初始化 ----------
func _ready() -> void:
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

	if input_str == "__start__" and _try_use_warmup_start():
		return

	_is_requesting = true
	_show_ai_waiting()
	_request_id += 1
	var current_id = _request_id
	print("[AIManager] 发送请求 #%d" % current_id)

	var request_data := _build_provider_request(input_str)
	var endpoint: String = request_data.get("endpoint", "")
	var headers: PackedStringArray = request_data.get("headers", PackedStringArray())
	var payload: Dictionary = request_data.get("payload", {})

	print("[AIManager] 实际请求 URL: %s" % endpoint)
	var error = _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_is_requesting = false
		_last_error_code = error
		_recover_with_dialogue("[AIManager] 无法发起请求。")
		_finish_requesting()
		return
	_pending_request_id = current_id

func warmup_start_request() -> void:
	if not ai_enabled or _warmup_start_pending or not _warmup_start_response.is_empty():
		return
	if not GameManager or not GameManager.ai_enabled:
		return
	_warmup_start_pending = true
	_warmup_request = HTTPRequest.new()
	_warmup_request.timeout = request_timeout
	add_child(_warmup_request)
	_warmup_request.request_completed.connect(_on_warmup_start_completed.bind(_warmup_request))
	var request_data := _build_provider_request("__start__")
	var endpoint: String = request_data.get("endpoint", "")
	var headers: PackedStringArray = request_data.get("headers", PackedStringArray())
	var payload: Dictionary = request_data.get("payload", {})
	print("[AIManager] 预热开场请求: %s" % endpoint)
	var error = _warmup_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_warmup_start_pending = false
		_cleanup_request_node(_warmup_request)
		_warmup_request = null

func consume_warmup_start() -> Dictionary:
	if _warmup_start_response.is_empty():
		return {}
	var response := _warmup_start_response.duplicate(true)
	_warmup_start_response.clear()
	return response

func _try_use_warmup_start() -> bool:
	var warmup_response := consume_warmup_start()
	if not warmup_response.is_empty():
		_is_requesting = true
		_show_ai_waiting()
		call_deferred("_process_warmup_start_response", warmup_response)
		return true
	if _warmup_start_pending:
		_is_requesting = true
		_warmup_consume_pending = true
		_show_ai_waiting()
		print("[AIManager] 等待已启动的开场预热请求。")
		return true
	return false

func _process_warmup_start_response(response: Dictionary) -> void:
	_is_requesting = false
	_finish_requesting()
	process_ai_response(response)

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
	commands = _normalize_ai_commands(commands)
	ScriptEngine.execute_commands(commands)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting = false
	_finish_requesting()
	if _pending_request_id != _request_id:
		print("[AIManager] 忽略过期请求 #%d" % _pending_request_id)
		return
	if _is_canceling:
		_is_canceling = false
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		_last_error_code = result
		push_error("[AIManager] 请求失败，结果码: %d" % result)
		_recover_with_dialogue("[AIManager] 请求未成功完成。")
		return
	var raw_text := body.get_string_from_utf8()
	print("[AIManager] 原始响应前2000字符: ", raw_text.substr(0, 2000))
	var ai_response := _parse_ai_response(raw_text, response_code, "主请求")
	if ai_response.is_empty():
		_recover_with_dialogue("[AIManager] AI 响应不可用。")
		return
	process_ai_response(ai_response)

# ---------- 选项续写 ----------
func _on_choice_made(choice_id: int, choice_text: String = "") -> void:
	_pending_choice_id = choice_id
	_pending_choice_text = choice_text
	if _pending_choice_text == "" and GameManager and GameManager.pending_choices.size() > 0:
		for c in GameManager.pending_choices:
			if str(c.get("id", "")) == str(choice_id):
				_pending_choice_text = str(c.get("text", ""))
				break
	print("[AIManager] 已记录玩家选择: %d %s" % [choice_id, _pending_choice_text])
	_waiting_for_choice_continuation = true

	if try_consume_choice_prediction(choice_id, _pending_choice_text):
		return

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
	lines.append_array(_get_resource_constraints_section())
	lines.append_array(_get_dialogue_examples())
	lines.append_array(_get_user_rules_section())
	return "\n".join(lines)

func _get_role_definition() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 角色与任务")
	arr.append("【绝对核心】你是视觉小说《最南幻想》的 AI 编剧引擎，负责生成剧情指令。你必须且只能返回一个 JSON 对象：{\"commands\": [...]}")
	arr.append("【绝对强制】不要输出任何推理过程、思考内容、解释或 Markdown。如果你需要思考，请在内部完成，最终只输出 JSON。")
	arr.append("【绝对强制】你的全部输出必须能被 JSON 解析器直接解析，不能有任何前缀或后缀。")
	arr.append("【绝对强制】确保所有 JSON 括号正确闭合，特别是以 show_choices 结尾时，务必补全 } 和 ]。")
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
	arr.append("- 开心 → happy，很高兴 → very_happy，动作：bounce")
	arr.append("- 悲伤/委屈 → sad，动作：step_back")
	arr.append("- 愤怒/不满 → angry，动作：shake")
	arr.append("- 害羞/尴尬 → confused，动作：step_back")
	arr.append("- 感动/惊讶 → surprised，动作：shake 或 nod")
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

	# TODO: 宋青角色资源补全后再启用。当前仓库没有 song_data.tres 和对应表情贴图，
	# 因此这些资料必须保持注释，避免 AI 选择不存在的角色或表情。
	# arr.append("# 角色档案：宋青 (id:song)")
	# arr.append("## 核心身份")
	# arr.append("南大校徽上的青松化身，沉稳可靠的学长，是你的心灵树洞和理性支持者。外表清冷如松，内心温热如春。")
	# arr.append("## 内在动机与价值观")
	# arr.append("希望引导你找到内心的平静与韧性，像松树一样抗压。相信“沉默的陪伴有时胜过千言万语”。")
	# arr.append("## 语言风格")
	# arr.append("简洁、温和，很少用感叹号。喜欢用“嗯”“或许”“我懂”开头。说话时会停顿，给人思考空间。偶尔引用诗句或哲言。")
	# arr.append("## 情绪－表情－动作映射")
	# arr.append("- 开心 → slight_smile，动作：nod")
	# arr.append("- 悲伤/委屈 → eyes_down，动作：step_back")
	# arr.append("- 愤怒/不满 → frown，动作：shake")
	# arr.append("- 害羞/尴尬 → default，动作：shrug")
	# arr.append("- 感动/惊讶 → eyes_widen，动作：nod")
	# arr.append("## 关系动态")
	# arr.append("- 好感度 0-20：礼貌疏离，只回答必要问题。")
	# arr.append("- 好感度 20-40：开始主动询问你的感受，分享自己的小习惯。")
	# arr.append("- 好感度 40-60：展露温柔，会为你准备热茶或建议，倾听时间变长。")
	# arr.append("- 好感度 60+：愿意坦露自己的脆弱，会轻轻拍拍你的肩，说出“我在”。")
	# arr.append("## 禁忌")
	# arr.append("- 绝不会冷暴力或消失。")
	# arr.append("- 不会否定你的情绪（不会说“你想多了”）。")
	# arr.append("- 不会强迫你做任何事。")
	# arr.append("")
	return arr

func _get_narrative_rules() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 剧情推进规则")
	arr.append("【绝对核心】用户选择选项前，请牢记选项对应的文本内容。选择选项后，请根据选项id来回忆该选项的内容并向用户作答；如果没有收到用户的选项，就请优雅地绕过这个选项，继续后续剧情")
	arr.append("【绝对核心】show_dialogue命令中，严禁将角色id放在text里面，角色id必须放在character里面")
	arr.append("1. 每次生成 2-4 条指令，形成一小段自然推进的剧情。第一条指令通常为 show_dialogue。")
	arr.append("2. 根据当前好感度和章节阶段，选择合适的情绪基调和对话内容。")
	arr.append("3. 当剧情需要玩家决策时（角色提问、征求意见、面临选择），必须使用 show_choices，且将其作为本轮最后一条指令。")
	arr.append("3.1 【强制】show_choices 后严禁继续输出任何指令；好感度、变量变化必须等玩家选择后的下一轮再处理。")
	arr.append("4. 玩家做出选择后，你的第一个指令应展示角色对该选择的即时反应（惊讶、高兴、犹豫等），然后继续剧情。")
	arr.append("5. 只有在剧情自然结束时才使用 end_scene，一般对话中严禁提前结束。")
	arr.append("6. 【强制】开场或章节开始时，必须包含 play_audio 指令播放合适的背景音乐。且不要频繁使用play_audio，只在开场或需要切换音乐时才用")
	arr.append("7. 对话中只允许使用这些 BBCode 标签： [b]、[i]、[u]、[color]、[wave]、[shake]。严禁使用 [italic]、[happy]、[sad]、[angry] 等非 Godot 标签或表情标签。")
	arr.append("8. 角色动作必须使用独立的 character_action 指令，不要在 show_dialogue 的 text 中直接写入 [bounce] 等动作标签。")
	arr.append("9. 所有背景、角色、表情、动作、音频、粒子、CG 都必须从下方【可用资源 JSON】中选择，不要发明不存在的 id。")
	arr.append("9.1 对话文本中的地点必须贴合当前或即将切换的背景；严禁把不存在贴图的地点（如小吃街、鸭血粉丝汤店、古典园林、樱花林）写成正在前往或已经到达的真实场景。")
	arr.append("10. 每轮剧情尽量至少包含一个非对白表现指令（set_expression、character_action、change_background、particle_play 之一），但不要频繁切换音乐。")
	arr.append("")
	return arr

func _get_command_reference() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 【绝对核心】可用指令速查（请严格遵守下列 JSON 格式，严禁出现格式或指令错误）")
	arr.append("# 【绝对强制】每次新对话开始时、切换角色时，都必须使用set_characters来确保角色在台上")
	arr.append("- show_dialogue: {\"type\":\"show_dialogue\",\"character\":\"（必填项，根据当前角色填入角色id，玩家就填写“玩家”）\",\"text\":\"（此处严禁出现任何角色名，包括玩家）...\"}")
	arr.append("- show_choices: {\"type\":\"show_choices\",\"choices\":[{\"id\":1,\"text\":\"选项1\"}]}")
	arr.append("- change_background: {\"type\":\"change_background\",\"background\":\"（从已有场景id选一个填入）\"}")
	arr.append("- set_characters: {\"type\":\"set_characters\",\"left\":{\"id\":\"（从已有角色id选一个填入）\",\"expression\":\"happy\"},\"right\":{\"id\":\"（从已有角色id选一个填入，不能和左边角色重复）\",\"expression\":\"happy\"}}")
	arr.append("【注意】set_characters中right字段为选填项，建议多个角色登场时使用（一左一右）；单个角色在场使用{\"type\":\"set_characters\",\"left\":{\"id\":\"（从已有角色id选一个填入）\",\"expression\":\"happy\"}}或者{\"type\":\"set_characters\",\"right\":{\"id\":\"（从已有角色id选一个填入）\",\"expression\":\"happy\"}}")
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

func _get_resource_constraints_section() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 可用资源 JSON（必须从这里选择 id）")
	arr.append(JSON.stringify(_build_resource_constraints(), "\t"))
	arr.append("")
	return arr

func _build_resource_constraints() -> Dictionary:
	return {
		"backgrounds": _collect_background_constraints(),
		"characters": _collect_character_constraints(),
		"actions": ["bounce", "shake", "nod", "step_back", "shrug"],
		"audio_bgm": _collect_audio_ids(),
		"particles": _collect_particle_ids(),
		"cg": _collect_cg_ids()
	}

func _collect_background_constraints() -> Dictionary:
	var result := {}
	if BackgroundManager:
		for id in BackgroundManager.background_database.keys():
			var bg_data = BackgroundManager.background_database[id]
			result[str(id)] = {
				"display_name": str(bg_data.display_name) if bg_data else str(id),
				"location_name": str(bg_data.location_name) if bg_data else str(id)
			}
	return result

func _collect_background_ids() -> Array:
	var result := []
	if BackgroundManager:
		for id in BackgroundManager.background_database.keys():
			result.append(str(id))
	return result

func _collect_character_constraints() -> Dictionary:
	var result := {}
	if GameManager:
		for id in GameManager.character_database.keys():
			var char_data = GameManager.character_database[id]
			var expressions := []
			if char_data and char_data.expressions is Dictionary:
				for expr in char_data.expressions.keys():
					expressions.append(str(expr))
			result[str(id)] = {"expressions": expressions}
	return result

func _collect_audio_ids() -> Array:
	var result := []
	if AudioManager:
		for id in AudioManager.audio_database.keys():
			result.append(str(id))
	return result

func _collect_particle_ids() -> Array:
	var result := []
	if ParticleManager:
		for id in ParticleManager.particle_database.keys():
			result.append(str(id))
	return result

func _collect_cg_ids() -> Array:
	var result := []
	if CGManager:
		for id in CGManager.cg_database.keys():
			result.append(str(id))
	return result

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

	arr.append("## 【特别重要】完整剧情示例（从开场到结局）")
	arr.append("## 多幕剧情示例：大学生心理减压（请严格模仿这段话的内容和结构，每幕包含一个场景和一次心灵启示）")
	arr.append("// 第一幕：北大楼前，释放压力")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"change_background\", \"background\": \"beidalou\"},")
	arr.append("    {\"type\": \"particle_play\", \"effect_id\": \"petal\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"你看，北大楼前的樱花多美呀。深呼吸——闻到春天的味道了吗？\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"有时候我们只需要停下来，感受一下周围的美好，心情就会轻松很多。\"},")
	arr.append("    {\"type\": \"long_dialogue\", \"text\": \"阳光透过松柏洒下斑驳的光影，几只灰喜鹊在草坪上跳跃。小貅轻轻哼着歌谣，钟声在远处回荡。\"},")
	arr.append("    {\"type\": \"show_choices\", \"choices\": [{\"id\":1,\"text\":\"嗯，舒服多了。\"}, {\"id\":2,\"text\":\"谢谢你，小貅。\"}]},")
	arr.append("    {\"type\": \"add_affection\", \"character\": \"xiu\", \"delta\": 10}")
	arr.append("  ]")
	arr.append("}")
	arr.append("// 第二幕：大礼堂的音乐疗愈")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"change_background\", \"background\": \"litang\"},")
	arr.append("    {\"type\": \"play_audio\", \"audio_id\": \"love_piano\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"大礼堂今天有校乐团的排练，我们进去听听吧。\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"音乐是最好的疗愈师，沉浸其中，大脑会释放多巴胺。\"},")
	arr.append("    {\"type\": \"long_dialogue\", \"text\": \"音符如水般流淌，你闭上眼睛，所有焦虑都随着旋律消散了。\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"[wave amp=50.0 freq=5.0]以后不开心就来找我，我带你听音乐！[/wave]\"},")
	arr.append("    {\"type\": \"add_affection\", \"character\": \"xiu\", \"delta\": 5}")
	arr.append("  ]")
	arr.append("}")
	arr.append("// 第三幕：心理中心的正念冥想")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"change_background\", \"background\": \"nansu\"},")
	arr.append("    {\"type\": \"play_audio\", \"audio_id\": \"flowing\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"这里是心理中心，我帮你预约了正念冥想，体验一下吧。\"},")
	arr.append("    {\"type\": \"unlock_cg\", \"cg_id\": \"heroine_smile\"},")
	arr.append("    {\"type\": \"cg_play\", \"cg_id\": \"heroine_smile\"},")
	arr.append("    {\"type\": \"long_dialogue\", \"text\": \"跟着引导呼吸，你将积压的疲惫一点点呼出体外，整个人变得轻盈。\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"关注心理健康是爱自己的第一步，要记得常来哦。\"},")
	arr.append("    {\"type\": \"add_affection\", \"character\": \"xiu\", \"delta\": 10}")
	arr.append("  ]")
	arr.append("}")
	arr.append("// 第四幕：操场夜跑与星空下的约定")
	arr.append("{")
	arr.append("  \"commands\": [")
	arr.append("    {\"type\": \"change_background\", \"background\": \"beidalou\"},")
	arr.append("    {\"type\": \"play_audio\", \"audio_id\": \"spring_forest\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"运动能分泌内啡肽，我们去操场跑两圈吧！\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"\", \"text\": \"你们在晚风中慢跑，汗水带走了烦恼。\"},")
	arr.append("    {\"type\": \"change_background\", \"background\": \"duxia\"},")
	arr.append("    {\"type\": \"play_audio\", \"audio_id\": \"gentle\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"看，木星周围有小卫星环绕，我们从来都不是孤独的。\"},")
	arr.append("    {\"type\": \"long_dialogue\", \"text\": \"星光下，你感到前所未有的安宁，所有压力都变得不再沉重。\"},")
	arr.append("    {\"type\": \"show_dialogue\", \"character\": \"xiu\", \"text\": \"[wave amp=50.0 freq=5.0]记住，我是你的心灵充电宝！[/wave]\"},")
	arr.append("    {\"type\": \"add_affection\", \"character\": \"xiu\", \"delta\": 15}")
	arr.append("  ]")
	arr.append("}")
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
func _build_user_prompt(input_str: String, history_snapshot: Array = [], choices_snapshot: Array = []) -> String:
	var chapter := _determine_current_chapter()
	var chapter_info = MAIN_STORY_LINE.get(chapter, {})
	var history_block := _get_recent_dialogue_history(16, history_snapshot)
	var state_block := _get_current_game_state()
	var event_desc := ""
	if input_str == "__start__":
		event_desc = "新游戏开始，请生成开场剧情，包含背景、角色、音乐。"
	elif input_str == "__continue__":
		event_desc = "玩家点击继续，请推进剧情。"
	elif input_str.begins_with("__choice__:"):
		var payload = input_str.trim_prefix("__choice__:")
		var parts = payload.split(":", false, 1)
		var cid = parts[0]
		var ctext = ""
		if parts.size() > 1:
			ctext = parts[1]
		else:
			var choices_source := choices_snapshot
			if choices_source.is_empty() and GameManager:
				choices_source = GameManager.pending_choices
			if choices_source.size() > 0:
				for c in choices_source:
					if str(c.get("id", "")) == cid:
						ctext = str(c.get("text", ""))
						break
		if ctext != "":
			event_desc = "玩家选择了选项 %s：\"%s\"。请展示角色对此选择的即时反应，并继续剧情。" % [cid, ctext]
		else:
			event_desc = "玩家选择了选项 %s。请根据上下文推测玩家的选择，并做出合理反应。" % cid

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
	prompt += "\n\n请直接返回 JSON 指令，不要包含任何推理过程。"
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

func _get_recent_dialogue_history(count: int = 8, history_snapshot: Array = []) -> String:
	var history := history_snapshot
	if history.is_empty() and GameManager:
		history = GameManager.dialogue_history
	if history.is_empty():
		return "暂无对话历史"
	var start_index: int = max(0, history.size() - count)
	var recent := history.slice(start_index)
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
		var provider := _get_current_provider()
		var provider_url: String = provider.get("base_url", "")
		if provider_url != "":
			return provider_url
		var user_url = GameManager.get_ai_setting("base_url")
		if user_url != "" and user_url not in ["http://localhost:11434", "http://localhost:11434/v1"]:
			return user_url
	return base_url.replace("localhost", "127.0.0.1")

func _get_model() -> String:
	if GameManager:
		var provider_id := GameManager.get_ai_setting("provider")
		if provider_id == "ollama":
			var ollama_model = GameManager.get_ai_setting("ollama_model")
			if ollama_model != "":
				return ollama_model
		var user_model = GameManager.get_ai_setting("model")
		if user_model != "":
			return user_model
	return model

func _get_api_key() -> String:
	if GameManager:
		return GameManager.get_ai_setting("api_key")
	return ""

func _get_current_provider() -> Dictionary:
	if GameManager and GameManager.has_method("get_current_ai_provider"):
		return GameManager.get_current_ai_provider()
	return {
		"id": "ollama",
		"name": "Ollama 本地",
		"region": "本地",
		"base_url": base_url,
		"api_format": "ollama_chat",
		"auth_type": "none",
		"default_model": model
	}

func _finish_requesting() -> void:
	if has_node("/root/DialogueManager"):
		DialogueManager.is_requesting = false
	var scene = DialogueManager.get_dialogue_scene() if has_node("/root/DialogueManager") else null
	if scene and scene.has_method("hide_ai_waiting"):
		scene.hide_ai_waiting()

func _show_ai_waiting() -> void:
	var scene = DialogueManager.get_dialogue_scene() if has_node("/root/DialogueManager") else null
	if scene and scene.has_method("show_ai_waiting"):
		scene.show_ai_waiting()

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
	if _pending_choice_text != "":
		return "__choice__:%d:%s" % [_pending_choice_id, _pending_choice_text]
	return "__choice__:%d" % _pending_choice_id

func prefetch_choice_predictions(choices: Array) -> void:
	if not ai_enabled or not GameManager or not GameManager.ai_enabled:
		return
	cancel_predictions()
	if choices.is_empty():
		return
	var history_snapshot := GameManager.dialogue_history.duplicate(true)
	var choices_snapshot := choices.duplicate(true)
	_active_prediction_context_key = _build_prediction_context_key(history_snapshot, choices_snapshot)
	for i in range(min(choices.size(), MAX_PREDICTION_REQUESTS)):
		var choice = choices[i]
		if not choice is Dictionary:
			continue
		var choice_id := int(choice.get("id", i + 1))
		var choice_text := str(choice.get("text", ""))
		var cache_key := _build_prediction_cache_key(_active_prediction_context_key, choice_id, choice_text)
		var request := HTTPRequest.new()
		request.timeout = request_timeout
		add_child(request)
		_prediction_requests[cache_key] = request
		request.request_completed.connect(_on_prediction_request_completed.bind(cache_key, request))
		var input_str := "__choice__:%d:%s" % [choice_id, choice_text]
		var request_data := _build_provider_request(input_str, history_snapshot, choices_snapshot)
		var endpoint: String = request_data.get("endpoint", "")
		var headers: PackedStringArray = request_data.get("headers", PackedStringArray())
		var payload: Dictionary = request_data.get("payload", {})
		print("[AIManager] 预测选项 %d 请求: %s" % [choice_id, endpoint])
		var error = request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
		if error != OK:
			_prediction_requests.erase(cache_key)
			_cleanup_request_node(request)

func try_consume_choice_prediction(choice_id: int, choice_text: String) -> bool:
	if _active_prediction_context_key == "":
		return false
	var cache_key := _build_prediction_cache_key(_active_prediction_context_key, choice_id, choice_text)
	if not _prediction_cache.has(cache_key):
		cancel_predictions()
		return false
	var commands: Array = _prediction_cache.get(cache_key, [])
	cancel_predictions()
	if commands.is_empty():
		return false
	print("[AIManager] 命中选项预测缓存: %d" % choice_id)
	call_deferred("_execute_prediction_commands", commands)
	return true

func cancel_predictions() -> void:
	for key in _prediction_requests.keys():
		var request = _prediction_requests[key]
		if request is HTTPRequest and is_instance_valid(request):
			request.cancel_request()
			_cleanup_request_node(request)
	_prediction_requests.clear()
	_prediction_cache.clear()
	_active_prediction_context_key = ""

func _execute_prediction_commands(commands: Array) -> void:
	_waiting_for_choice_continuation = false
	if not has_node("/root/ScriptEngine"):
		return
	ScriptEngine.execute_commands(commands)

func _on_prediction_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, cache_key: String, request: HTTPRequest) -> void:
	_prediction_requests.erase(cache_key)
	_cleanup_request_node(request)
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[AIManager] 预测请求失败: %s result=%d" % [cache_key, result])
		return
	var raw_text := body.get_string_from_utf8()
	var ai_response := _parse_ai_response(raw_text, response_code, "预测请求")
	if ai_response.is_empty() or not ai_response.has("commands"):
		return
	var commands = ai_response.get("commands", [])
	if not commands is Array:
		return
	commands = _normalize_ai_commands(commands)
	if not commands.is_empty():
		_prediction_cache[cache_key] = commands
		print("[AIManager] 预测缓存已写入: %s" % cache_key)

func _build_provider_request(input_str: String, history_snapshot: Array = [], choices_snapshot: Array = []) -> Dictionary:
	var provider := _get_current_provider()
	var api_format: String = provider.get("api_format", "openai_chat")
	var base := _get_base_url().rstrip("/")
	var model_name := _get_model()
	var api_key := _get_api_key()
	var system_prompt := _build_system_prompt()
	var user_prompt := _build_user_prompt(input_str, history_snapshot, choices_snapshot)
	var temperature := _get_request_temperature(provider, model_name)
	var output_tokens := _get_output_token_limit(provider, model_name)

	match api_format:
		"ollama_chat":
			_is_ollama_request = true
			return {
				"endpoint": base + "/api/chat",
				"headers": PackedStringArray(["Content-Type: application/json"]),
				"payload": {
					"model": model_name,
					"messages": [
						{"role": "system", "content": system_prompt},
						{"role": "user", "content": user_prompt}
					],
					"stream": false,
					"options": {
						"temperature": temperature,
						"num_predict": output_tokens
					}
				}
			}
		"anthropic_messages":
			_is_ollama_request = false
			return {
				"endpoint": base + "/messages",
				"headers": _build_headers(provider, api_key),
				"payload": {
					"model": model_name,
					"system": system_prompt,
					"messages": [{"role": "user", "content": user_prompt}],
					"temperature": temperature,
					"max_tokens": output_tokens
				}
			}
		"gemini_generate_content":
			_is_ollama_request = false
			var endpoint := "%s/models/%s:generateContent" % [base, model_name]
			if api_key != "":
				endpoint += "?key=" + api_key.uri_encode()
			return {
				"endpoint": endpoint,
				"headers": PackedStringArray(["Content-Type: application/json"]),
				"payload": {
					"system_instruction": {"parts": [{"text": system_prompt}]},
					"contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
					"generationConfig": {"temperature": temperature, "maxOutputTokens": output_tokens}
				}
			}
		_:
			_is_ollama_request = false
			var payload := {
				"model": model_name,
				"messages": [
					{"role": "system", "content": system_prompt},
					{"role": "user", "content": user_prompt}
				]
			}
			if _should_send_temperature(provider, model_name):
				payload["temperature"] = temperature
			payload[_get_token_limit_field(provider, model_name)] = output_tokens
			if _should_disable_thinking(provider, model_name):
				payload["thinking"] = {"type": "disabled"}
			if _supports_json_response_format(provider):
				payload["response_format"] = {"type": "json_object"}
			return {
				"endpoint": base + "/chat/completions",
				"headers": _build_headers(provider, api_key),
				"payload": payload
			}

func _on_warmup_start_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	_warmup_start_pending = false
	_cleanup_request_node(request)
	if _warmup_request == request:
		_warmup_request = null
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[AIManager] 开场预热失败: %d" % result)
		if _warmup_consume_pending:
			_warmup_consume_pending = false
			_is_requesting = false
			_finish_requesting()
			send_message("__start__")
		return
	var raw_text := body.get_string_from_utf8()
	var ai_response := _parse_ai_response(raw_text, response_code, "开场预热")
	if ai_response.is_empty():
		if _warmup_consume_pending:
			_warmup_consume_pending = false
			_is_requesting = false
			_finish_requesting()
			send_message("__start__")
		return
	if _warmup_consume_pending:
		_warmup_consume_pending = false
		_process_warmup_start_response(ai_response)
	else:
		_warmup_start_response = ai_response
		print("[AIManager] 开场预热缓存已就绪。")

func _parse_ai_response(raw_text: String, response_code: int, context: String) -> Dictionary:
	if response_code < 200 or response_code >= 300:
		push_error("[AIManager] %s 返回 HTTP %d: %s" % [context, response_code, raw_text])
		return {}
	var raw_response = JSON.parse_string(raw_text)
	if not raw_response is Dictionary:
		push_error("[AIManager] %s 顶级响应不是 JSON 对象。原始文本: %s" % [context, raw_text])
		return {}
	var content := _extract_response_content(raw_response)
	if content.strip_edges() == "":
		push_error("[AIManager] %s content 为空。完整响应: %s" % [context, raw_text])
		return {}

	print("[AIManager] %s 原始 content: %s" % [context, content])
	var clean_content := _normalize_json_content(content)
	print("[AIManager] %s 清洗后 content: %s" % [context, clean_content])
	var ai_response = JSON.parse_string(clean_content)
	if not ai_response is Dictionary:
		push_error("[AIManager] %s commands 解析失败。原始: %s, 清洗后: %s" % [context, content, clean_content])
		return {}
	return ai_response

func _build_prediction_context_key(history_snapshot: Array, choices_snapshot: Array) -> String:
	var state := {
		"history": history_snapshot,
		"choices": choices_snapshot,
		"chapter": _determine_current_chapter(),
		"state": _get_current_game_state()
	}
	return str(JSON.stringify(state).hash())

func _build_prediction_cache_key(context_key: String, choice_id: int, choice_text: String) -> String:
	return "%s:%d:%s" % [context_key, choice_id, str(choice_text).hash()]

func _cleanup_request_node(request: HTTPRequest) -> void:
	if request and is_instance_valid(request):
		request.queue_free()

func _get_output_token_limit(_provider: Dictionary, _model_name: String) -> int:
	return DEFAULT_OUTPUT_TOKENS

func _get_request_temperature(provider: Dictionary, model_name: String) -> float:
	var provider_id: String = provider.get("id", "")
	var provider_url: String = str(provider.get("base_url", ""))
	if provider_id == "kimi" or provider_url.begins_with("https://api.moonshot.cn"):
		return 1.0
	var normalized_model := model_name.to_lower()
	if provider_id == "openai" and (normalized_model.begins_with("gpt-5") or normalized_model.begins_with("o")):
		return 1.0
	return 0.8

func _get_token_limit_field(provider: Dictionary, model_name: String) -> String:
	var provider_id: String = provider.get("id", "")
	var normalized_model := model_name.to_lower()
	if provider_id == "openai" and (normalized_model.begins_with("gpt-5") or normalized_model.begins_with("o")):
		return "max_completion_tokens"
	return "max_tokens"

func _should_send_temperature(provider: Dictionary, model_name: String) -> bool:
	return not _should_disable_thinking(provider, model_name)

func _should_disable_thinking(provider: Dictionary, model_name: String) -> bool:
	var provider_id: String = provider.get("id", "")
	var normalized_model := model_name.to_lower()
	if provider_id == "kimi":
		return normalized_model.begins_with("kimi-k2.6") or normalized_model.begins_with("kimi-k2.5") or normalized_model.find("thinking") >= 0
	if provider_id == "deepseek":
		return normalized_model.begins_with("deepseek-v4") or normalized_model.find("reasoner") >= 0
	return false

func _supports_json_response_format(provider: Dictionary) -> bool:
	var provider_id: String = provider.get("id", "")
	return provider_id in ["kimi", "openai", "deepseek", "qwen", "zhipu", "doubao", "xai", "mistral"]

func _build_headers(provider: Dictionary, api_key: String) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var auth_type: String = provider.get("auth_type", "bearer")
	if auth_type == "bearer" and api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	elif auth_type == "x-api-key" and api_key != "":
		headers.append("x-api-key: " + api_key)
		headers.append("anthropic-version: 2023-06-01")
	return headers

func _extract_response_content(raw_response: Dictionary) -> String:
	var provider := _get_current_provider()
	var api_format: String = provider.get("api_format", "openai_chat")
	match api_format:
		"ollama_chat":
			var message = raw_response.get("message", {})
			if message is Dictionary:
				return str(message.get("content", ""))
			return ""
		"anthropic_messages":
			var content: Array = raw_response.get("content", [])
			for part in content:
				if part is Dictionary and str(part.get("type", "")) == "text":
					return str(part.get("text", ""))
			return ""
		"gemini_generate_content":
			var candidates: Array = raw_response.get("candidates", [])
			if candidates.is_empty() or not candidates[0] is Dictionary:
				return ""
			var content_dict: Dictionary = candidates[0].get("content", {})
			var parts: Array = content_dict.get("parts", [])
			for part in parts:
				if part is Dictionary and part.has("text"):
					return str(part.get("text", ""))
			return ""
		_:
			var choices: Array = raw_response.get("choices", [])
			if choices.is_empty() or not choices[0] is Dictionary:
				return ""
			var message = choices[0].get("message", {})
			if not message is Dictionary:
				return ""
			return str(message.get("content", ""))

func _normalize_ai_commands(commands: Array) -> Array:
	var normalized: Array = []
	for item in commands:
		if not item is Dictionary:
			continue
		var cmd: Dictionary = item.duplicate(true)
		var type: String = cmd.get("type", "")
		if type == "show_dialogue":
			var character: String = cmd.get("character", "")
			if character != "" and not _character_exists(character):
				character = ""
				cmd["character"] = ""
			var text: String = cmd.get("text", "")
			var action := _detect_text_action(text)
			cmd["text"] = _sanitize_rich_text(text)
			normalized.append(cmd)
			if action != "" and character != "":
				normalized.append({"type": "character_action", "character": character, "action": action})
		elif type == "long_dialogue":
			cmd["text"] = _sanitize_rich_text(str(cmd.get("text", "")))
			normalized.append(cmd)
		elif type == "show_choices":
			cmd["choices"] = _normalize_choices(cmd.get("choices", []))
			if not cmd["choices"].is_empty():
				normalized.append(cmd)
				break
		else:
			if _is_valid_command(cmd):
				normalized.append(cmd)
	return normalized

func _normalize_choices(raw_choices) -> Array:
	var choices: Array = []
	if not raw_choices is Array:
		return choices
	for i in range(min(raw_choices.size(), 3)):
		var choice = raw_choices[i]
		if not choice is Dictionary:
			continue
		var text := str(choice.get("text", "")).strip_edges()
		if text == "":
			continue
		choices.append({"id": int(choice.get("id", i + 1)), "text": _sanitize_rich_text(text)})
	return choices

func _is_valid_command(cmd: Dictionary) -> bool:
	var type: String = cmd.get("type", "")
	match type:
		"change_background":
			return _id_exists(BackgroundManager.background_database, cmd.get("background", ""))
		"set_characters":
			return _is_valid_stage_role(cmd.get("left", null)) or _is_valid_stage_role(cmd.get("right", null))
		"set_expression":
			return _is_valid_character_expression(cmd.get("character", ""), cmd.get("expression", "default"))
		"character_action":
			return str(cmd.get("action", "")) in VALID_CHARACTER_ACTIONS and _character_exists(cmd.get("character", ""))
		"play_audio", "stop_audio":
			return _id_exists(AudioManager.audio_database, cmd.get("audio_id", ""))
		"particle_play", "particle_stop":
			if not cmd.has("effect_id") and type == "particle_stop":
				return true
			return _id_exists(ParticleManager.particle_database, cmd.get("effect_id", ""))
		"unlock_cg", "cg_play", "cg_hide":
			if type == "cg_hide":
				return true
			return _id_exists(CGManager.cg_database, cmd.get("cg_id", ""))
		"unlock_bgm":
			return _id_exists(AudioManager.audio_database, cmd.get("bgm_id", ""))
		"add_affection":
			return _character_exists(cmd.get("character", ""))
		"set_flag", "set_variable", "set_ui_state", "wait", "jump", "end_scene", "reset_unlocks":
			return true
		_:
			push_warning("[AIManager] 跳过未知或非法指令: %s" % type)
			return false

func _is_valid_stage_role(value) -> bool:
	if value == null:
		return false
	if value is Dictionary:
		var character_id: String = value.get("id", "")
		if character_id == "":
			return false
		return _is_valid_character_expression(character_id, value.get("expression", "default"))
	if value is String:
		return _character_exists(value)
	return false

func _is_valid_character_expression(character_id, expression_id) -> bool:
	if not _character_exists(character_id):
		return false
	var char_data = GameManager.character_database[str(character_id)]
	if not char_data or not (char_data.expressions is Dictionary):
		return true
	return str(expression_id) in char_data.expressions

func _character_exists(character_id) -> bool:
	return GameManager and GameManager.character_database.has(str(character_id))

func _id_exists(database: Dictionary, id_value) -> bool:
	return database.has(str(id_value))

func _detect_text_action(text: String) -> String:
	for tag in TEXT_ACTION_TAG_MAP.keys():
		var regex := RegEx.new()
		regex.compile("\\[/?%s[^\\]]*\\]" % str(tag))
		if regex.search(text):
			return TEXT_ACTION_TAG_MAP[tag]
	return ""

func _sanitize_rich_text(text: String) -> String:
	var result := _normalize_bbcode_aliases(text)
	for tag in TEXT_ACTION_TAG_MAP.keys():
		result = _strip_bbcode_tag(result, str(tag))
	result = _strip_unsupported_bbcode_tags(result)
	if not result.contains("[color"):
		result = result.replace("[/color]", "")
	if not result.contains("[wave"):
		result = result.replace("[/wave]", "")
	if not result.contains("[shake"):
		result = result.replace("[/shake]", "")
	if not result.contains("[b"):
		result = result.replace("[/b]", "")
	if not result.contains("[i"):
		result = result.replace("[/i]", "")
	if not result.contains("[u"):
		result = result.replace("[/u]", "")
	return result.strip_edges()

func _normalize_bbcode_aliases(text: String) -> String:
	var result := text
	result = result.replace("[italic]", "[i]")
	result = result.replace("[/italic]", "[/i]")
	result = result.replace("[italics]", "[i]")
	result = result.replace("[/italics]", "[/i]")
	result = result.replace("[bold]", "[b]")
	result = result.replace("[/bold]", "[/b]")
	return result

func _strip_bbcode_tag(text: String, tag: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[/?%s[^\\]]*\\]" % tag)
	return regex.sub(text, "", true)

func _strip_unsupported_bbcode_tags(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[([^\\]]+)\\]")
	var result := text
	for match_result in regex.search_all(text):
		var raw_tag := match_result.get_string(1).strip_edges()
		var tag_name := raw_tag.trim_prefix("/").split(" ")[0].split("=")[0].to_lower()
		if not _is_allowed_text_bbcode(raw_tag, tag_name):
			result = result.replace(match_result.get_string(0), "")
	return result

func _is_allowed_text_bbcode(raw_tag: String, tag_name: String) -> bool:
	if tag_name not in ALLOWED_TEXT_BBCODE_TAGS:
		return false
	if tag_name == "color":
		return raw_tag.begins_with("/") or raw_tag.begins_with("color=")
	return raw_tag == tag_name or raw_tag == "/" + tag_name

func _normalize_json_content(content: String) -> String:
	var result := content.strip_edges()
	if result.begins_with("\uFEFF"): result = result.trim_prefix("\uFEFF")
	if result.begins_with("```json"): result = result.trim_prefix("```json").strip_edges()
	elif result.begins_with("```"): result = result.trim_prefix("```").strip_edges()
	if result.ends_with("```"): result = result.trim_suffix("```").strip_edges()

	var parse_result = JSON.parse_string(result)
	if parse_result is Dictionary:
		return result

	var cleaned = result
	while cleaned.ends_with(",") or cleaned.ends_with(":"):
		cleaned = cleaned.left(cleaned.length() - 1)
	parse_result = JSON.parse_string(cleaned)
	if parse_result is Dictionary:
		return cleaned

	var open_braces = _count_char_outside_string(cleaned, '{')
	var close_braces = _count_char_outside_string(cleaned, '}')
	var open_brackets = _count_char_outside_string(cleaned, '[')
	var close_brackets = _count_char_outside_string(cleaned, ']')
	var test = cleaned
	for i in range(open_braces - close_braces):
		test += "}"
	for i in range(open_brackets - close_brackets):
		test += "]"
	parse_result = JSON.parse_string(test)
	if parse_result is Dictionary:
		return test

	if test.ends_with("}"):
		test = test.left(test.length() - 1)
	elif test.ends_with("]"):
		test = test.left(test.length() - 1)
	parse_result = JSON.parse_string(test)
	if parse_result is Dictionary:
		return test

	return cleaned

func _count_char_outside_string(s: String, c: String) -> int:
	var count = 0
	var in_string = false
	var i = 0
	while i < s.length():
		if s[i] == '\\':
			i += 2  # 跳过转义
			continue
		if s[i] == '"':
			in_string = !in_string
		elif not in_string and s[i] == c:
			count += 1
		i += 1
	return count

func _recover_with_dialogue(reason: String) -> void:
	push_warning(reason)
	_recovery_mode = true

	var help_text = ""
	if _last_error_code == 13: # CANT_CONNECT
		help_text = "无法连接到AI服务。\n\n可能的原因：\n1. 如果您是本地运行，请确保Ollama已启动。\n2. 如果您使用云端API，请检查网络和API设置。\n\n您可以在“设置”中调整AI连接方式。"
	elif _last_error_code == 4: # TIMEOUT
		help_text = "AI服务响应超时，请稍后重试。"
	else:
		help_text = "AI正在全力思考中，稍等哦~"

	if has_node("/root/ScriptEngine"):
		ScriptEngine.execute_commands([{"type": "show_dialogue", "character": "", "text": help_text}])
