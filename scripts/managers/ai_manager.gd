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
var _last_response_code: int = 0
var _pending_choice_text: String = ""
var _waiting_for_choice_continuation: bool = false
var _prediction_requests: Dictionary = {}
var _prediction_request_meta: Dictionary = {}
var _prediction_retry_counts: Dictionary = {}
var _prediction_asset: Dictionary = {}
var _active_prediction_context_key: String = ""
var _prediction_history_snapshot: Array = []
var _prediction_choices_snapshot: Array = []
var _selected_prediction_key: String = ""
var _selected_prediction_commands: Array = []
var _waiting_for_prediction_result: bool = false
var _selected_prediction_execute_queued: bool = false
var _selected_prediction_choice_id: int = -1
var _warmup_request: HTTPRequest = null
var _warmup_start_response: Dictionary = {}
var _warmup_start_pending: bool = false
var _warmup_consume_pending: bool = false
var _head_warmup_asset: Dictionary = {}
var _active_input_str: String = ""
var _main_retry_count: int = 0
var _main_retry_timer: Timer = null
var _warmup_retry_count: int = 0
var _warmup_retry_timer: Timer = null
var _suppress_next_auto_continue: bool = false

const _FALLBACK_TEXT := "AI 暂时不可用，请稍后再试。"
const DEFAULT_OUTPUT_TOKENS := 1200
const MAX_PREDICTION_REQUESTS := 3
const MAX_MAIN_RETRIES := 3
const MAX_WARMUP_RETRIES := 3
const RETRY_BASE_DELAY := 1.5
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

	_clear_main_retry_timer()
	_main_retry_count = 0
	_active_input_str = input_str
	_start_main_request(input_str)

func _start_main_request(input_str: String) -> void:
	_is_requesting = true
	_show_ai_waiting(input_str == "__start__")
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

func warmup_start_request(force_retry: bool = false) -> void:
	if not ai_enabled:
		return
	if _is_check_only_run():
		return
	if not GameManager or not GameManager.ai_enabled:
		return
	if GameManager.current_scene != "":
		_head_warmup_asset.clear()
		return
	if not force_retry and not _head_warmup_asset.is_empty() and str(_head_warmup_asset.get("status", "")) in ["pending", "requesting", "completed"]:
		return
	if _warmup_start_pending or not _warmup_start_response.is_empty():
		return
	_clear_warmup_retry_timer()
	_head_warmup_asset = {
		"asset_id": "head:start",
		"context_key": "head:start",
		"input": "__start__",
		"status": "requesting",
		"response": {},
		"retry_count": 0
	}
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
		_head_warmup_asset["status"] = "failed"
		_cleanup_request_node(_warmup_request)
		_warmup_request = null

func _is_check_only_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg == "--check-only":
			return true
	return false

func consume_warmup_start() -> Dictionary:
	if _warmup_start_response.is_empty():
		return {}
	var response := _warmup_start_response.duplicate(true)
	_warmup_start_response.clear()
	_head_warmup_asset.clear()
	return response

func _try_use_warmup_start() -> bool:
	var warmup_response := consume_warmup_start()
	if not warmup_response.is_empty():
		_is_requesting = true
		_show_ai_waiting(true)
		call_deferred("_process_warmup_start_response", warmup_response)
		return true
	if _warmup_start_pending:
		_is_requesting = true
		_warmup_consume_pending = true
		_show_ai_waiting(true)
		print("[AIManager] 等待已启动的开场预热请求。")
		return true
	return false

func _process_warmup_start_response(response: Dictionary) -> void:
	_is_requesting = false
	_finish_requesting()
	_warmup_retry_count = 0
	process_ai_response(response)

func _schedule_main_retry() -> bool:
	if _active_input_str == "" or _main_retry_count >= MAX_MAIN_RETRIES:
		return false
	_main_retry_count += 1
	var delay := _get_retry_delay(_main_retry_count)
	print("[AIManager] 主请求 429，%.1f 秒后重试 (%d/%d)。" % [delay, _main_retry_count, MAX_MAIN_RETRIES])
	_is_requesting = true
	_show_ai_waiting(_active_input_str == "__start__")
	_clear_main_retry_timer()
	_main_retry_timer = Timer.new()
	_main_retry_timer.one_shot = true
	_main_retry_timer.wait_time = delay
	add_child(_main_retry_timer)
	_main_retry_timer.timeout.connect(_on_main_retry_timeout)
	_main_retry_timer.start()
	return true

func _on_main_retry_timeout() -> void:
	_clear_main_retry_timer()
	if _active_input_str == "":
		_is_requesting = false
		_finish_requesting()
		return
	_start_main_request(_active_input_str)

func _schedule_warmup_retry() -> bool:
	if _warmup_retry_count >= MAX_WARMUP_RETRIES:
		_head_warmup_asset["status"] = "failed"
		return false
	_warmup_retry_count += 1
	_head_warmup_asset["status"] = "pending"
	_head_warmup_asset["retry_count"] = _warmup_retry_count
	var delay := _get_retry_delay(_warmup_retry_count)
	print("[AIManager] 开场预热 429，%.1f 秒后重试 (%d/%d)。" % [delay, _warmup_retry_count, MAX_WARMUP_RETRIES])
	_warmup_start_pending = true
	_clear_warmup_retry_timer()
	_warmup_retry_timer = Timer.new()
	_warmup_retry_timer.one_shot = true
	_warmup_retry_timer.wait_time = delay
	add_child(_warmup_retry_timer)
	_warmup_retry_timer.timeout.connect(_on_warmup_retry_timeout)
	_warmup_retry_timer.start()
	return true

func _on_warmup_retry_timeout() -> void:
	_clear_warmup_retry_timer()
	_warmup_start_pending = false
	warmup_start_request(true)

func _get_retry_delay(retry_count: int) -> float:
	var jitter := randf_range(0.0, 0.4)
	return RETRY_BASE_DELAY * pow(2.0, retry_count - 1) + jitter

func _clear_main_retry_timer() -> void:
	if _main_retry_timer and is_instance_valid(_main_retry_timer):
		_main_retry_timer.stop()
		_main_retry_timer.queue_free()
	_main_retry_timer = null

func _clear_warmup_retry_timer() -> void:
	if _warmup_retry_timer and is_instance_valid(_warmup_retry_timer):
		_warmup_retry_timer.stop()
		_warmup_retry_timer.queue_free()
	_warmup_retry_timer = null

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
	_prefetch_predictions_from_commands(commands)
	ScriptEngine.execute_commands(commands)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting = false
	if _pending_request_id != _request_id:
		print("[AIManager] 忽略过期请求 #%d" % _pending_request_id)
		_finish_requesting()
		return
	if _is_canceling:
		_is_canceling = false
		_finish_requesting()
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		_last_error_code = result
		_last_response_code = 0
		push_error("[AIManager] 请求失败，结果码: %d" % result)
		_finish_requesting()
		_recover_with_dialogue("[AIManager] 请求未成功完成。")
		return
	var raw_text := body.get_string_from_utf8()
	print("[AIManager] 原始响应前2000字符: ", raw_text.substr(0, 2000))
	_last_error_code = 0
	_last_response_code = response_code
	if response_code == 429 and _schedule_main_retry():
		return
	var ai_response := _parse_ai_response(raw_text, response_code, "主请求")
	if ai_response.is_empty():
		_finish_requesting()
		_recover_with_dialogue("[AIManager] AI 响应不可用。")
		return
	_finish_requesting()
	_main_retry_count = 0
	_active_input_str = ""
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

	print("[AIManager] 选项 %d 暂无可用预测分支，等待预测请求重建。" % choice_id)
	_show_ai_waiting()

func _on_script_execution_finished() -> void:
	if _recovery_mode:
		_recovery_mode = false
		return
	if _selected_prediction_key != "":
		_try_execute_selected_prediction()
		return
	if _waiting_for_choice_continuation or _is_requesting:
		return
	if _suppress_next_auto_continue:
		_suppress_next_auto_continue = false
		print("[AIManager] 读档恢复完成，跳过本次自动续写。")
		return
	call_deferred("send_message", "__continue__")

func suppress_next_auto_continue() -> void:
	_suppress_next_auto_continue = true

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
	arr.append("故事发生在南大不同校区，充满人文气息。")
	arr.append("【绝对强制】请严格区分鼓楼校区、仙林校区和苏州校区，不同校区场景严禁混用！")
	arr.append("可用场景id如下：")
	arr.append("鼓楼校区部分：")
	arr.append("- beidalou：【鼓楼校区】北大楼，南京大学标志性建筑，气氛唯美，适合浪漫、唯美的情节。")
	arr.append("- litang：【鼓楼校区】大礼堂，南京大学标志性建筑，气氛庄重，适合大型的活动情节。")
	arr.append("- classroom：【鼓楼校区】南京大学教学楼教室，适合学习、谈论等情节。")
	arr.append("- classroom2：【鼓楼校区】南京大学教学楼教室前门口，同上。")
	arr.append("- flowers：【鼓楼校区】一处开满鲜花的地方，适合浪漫的场景。")
	arr.append("- gate：【鼓楼校区】最具代表性的地标，南京大学正门口。")
	arr.append("- path：【鼓楼校区】一处小径上，人很少，适合宁静、慢节奏的场景。")
	arr.append("- playground_gulou：【鼓楼校区】苏浙运动场，适合运动、激情相关情节。")
	arr.append("- playground_gulou2：【鼓楼校区】苏浙运动场另一张图，同上。")
	arr.append("- xingzheng：【鼓楼校区】行政楼南楼，老师办公的地方。")
	arr.append("")
	arr.append("仙林校区部分：")
	arr.append("- duxia：【仙林校区】杜厦图书馆，气氛安静，适合学术讨论或安静的读书情节。")
	arr.append("- classroom_big：【仙林校区】南京大学阶梯教室，是大型教学、活动举办地。")
	arr.append("- duxia_front：【仙林校区】杜厦图书馆正门口。")
	arr.append("- duxia_night：【仙林校区】夜晚的杜厦图书馆，适合安静、温馨的场景。")
	arr.append("- playground_xianlin：【仙林校区】运动场，特别注意不要和前面鼓楼校区运动场混用！")
	arr.append("- xiangxuehai：【仙林校区】著名景点，适合放松、游玩等剧情。")
	arr.append("")
	arr.append("苏州校区部分：")
	arr.append("- nansu：【苏州校区】地标，适合普通对话、正常生活活动等情节。")
	arr.append("")
	return arr

func _get_character_profile() -> PackedStringArray:
	var arr := PackedStringArray()
	arr.append("# 角色档案：小貅 (id:xiu)")
	arr.append("【绝对强制】小貅只能放置在左侧")
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

	# TODO: 宋青角色已补全
	arr.append("# 角色档案：宋青 (id:song)")
	arr.append("【绝对强制】宋青只能放置在右侧")
	arr.append("## 核心身份")
	arr.append("南大校徽上的青松化身，沉稳可靠的学长，是你的心灵树洞和理性支持者。外表清冷如松，内心温热如春。")
	arr.append("## 内在动机与价值观")
	arr.append("希望引导你找到内心的平静与韧性，像松树一样抗压。相信“沉默的陪伴有时胜过千言万语”。")
	arr.append("## 语言风格")
	arr.append("简洁、温和，很少用感叹号。喜欢用“嗯”“或许”“我懂”开头。说话时会停顿，给人思考空间。偶尔引用诗句或哲言。")
	arr.append("## 情绪－表情－动作映射")
	arr.append("- 开心 → slight_smile，动作：nod")
	arr.append("- 悲伤/委屈 → eyes_down，动作：step_back")
	arr.append("- 愤怒/不满 → frown，动作：shake")
	arr.append("- 害羞/尴尬 → default，动作：shrug")
	arr.append("- 感动/惊讶 → eyes_widen，动作：nod")
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
	arr.append("- active：青春活力")
	arr.append("- smooth：舒缓深沉")
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

func _show_ai_waiting(is_initial_start: bool = false) -> void:
	var scene = DialogueManager.get_dialogue_scene() if has_node("/root/DialogueManager") else null
	if scene and scene.has_method("show_ai_waiting"):
		scene.show_ai_waiting(is_initial_start)

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

func prefetch_choice_predictions(choices: Array, history_snapshot: Array = [], preserve_completed: bool = false) -> void:
	if not ai_enabled or not GameManager or not GameManager.ai_enabled:
		return
	if choices.is_empty():
		return
	if history_snapshot.is_empty():
		history_snapshot = GameManager.dialogue_history.duplicate(true)
	var choices_snapshot := choices.duplicate(true)
	var context_key := _build_prediction_context_key(history_snapshot, choices_snapshot)
	var same_asset := preserve_completed and str(_prediction_asset.get("context_key", "")) == context_key
	if not same_asset:
		_cancel_prediction_requests()
	if not same_asset:
		_prediction_retry_counts.clear()
		_prediction_asset = _create_prediction_asset(context_key, history_snapshot, choices_snapshot)
	elif _prediction_asset.is_empty() or str(_prediction_asset.get("context_key", "")) != context_key:
		_prediction_asset = _create_prediction_asset(context_key, history_snapshot, choices_snapshot)
	_active_prediction_context_key = context_key
	_prediction_history_snapshot = history_snapshot.duplicate(true)
	_prediction_choices_snapshot = choices_snapshot.duplicate(true)
	for i in range(min(choices.size(), MAX_PREDICTION_REQUESTS)):
		var choice = choices[i]
		if not choice is Dictionary:
			continue
		var choice_id := int(choice.get("id", i + 1))
		var choice_text := str(choice.get("text", ""))
		var cache_key := _build_prediction_cache_key(_active_prediction_context_key, choice_id, choice_text)
		var branch_key := str(choice_id)
		_ensure_prediction_branch(choice_id, choice_text, cache_key)
		if not _should_request_prediction_branch(branch_key):
			continue
		var meta := {
			"branch_key": branch_key,
			"cache_key": cache_key,
			"context_key": _active_prediction_context_key,
			"choice_id": choice_id,
			"choice_text": choice_text,
			"history_snapshot": history_snapshot.duplicate(true),
			"choices_snapshot": choices_snapshot.duplicate(true)
		}
		_start_prediction_request(meta)

func _create_prediction_asset(context_key: String, history_snapshot: Array, choices_snapshot: Array) -> Dictionary:
	return {
		"asset_id": context_key,
		"context_key": context_key,
		"history_snapshot": history_snapshot.duplicate(true),
		"choices_snapshot": choices_snapshot.duplicate(true),
		"branches": {},
		"selected_choice_id": -1,
		"selected_branch_key": ""
	}

func _ensure_prediction_branch(choice_id: int, choice_text: String, cache_key: String) -> Dictionary:
	if _prediction_asset.is_empty():
		_prediction_asset = _create_prediction_asset(_active_prediction_context_key, _prediction_history_snapshot, _prediction_choices_snapshot)
	var branches: Dictionary = _prediction_asset.get("branches", {})
	var branch_key := str(choice_id)
	if not branches.has(branch_key):
		branches[branch_key] = {
			"choice_id": choice_id,
			"choice_text": choice_text,
			"cache_key": cache_key,
			"status": "idle",
			"commands": [],
			"retry_count": 0,
			"request_meta": {},
			"last_error": ""
		}
	var branch: Dictionary = branches[branch_key]
	branch["choice_text"] = choice_text if choice_text != "" else str(branch.get("choice_text", ""))
	branch["cache_key"] = cache_key
	branches[branch_key] = branch
	_prediction_asset["branches"] = branches
	return branch

func _get_prediction_branch(branch_key: String) -> Dictionary:
	var branches: Dictionary = _prediction_asset.get("branches", {})
	if branches.has(branch_key):
		return branches[branch_key]
	return {}

func _set_prediction_branch(branch_key: String, branch: Dictionary) -> void:
	if branch_key == "" or _prediction_asset.is_empty():
		return
	var branches: Dictionary = _prediction_asset.get("branches", {})
	branches[branch_key] = branch
	_prediction_asset["branches"] = branches

func _should_request_prediction_branch(branch_key: String) -> bool:
	if _prediction_requests.has(branch_key):
		return false
	var branch := _get_prediction_branch(branch_key)
	if branch.is_empty():
		return false
	var status := str(branch.get("status", "idle"))
	if status == "completed":
		return false
	return status in ["idle", "failed", "cancelled"]

func _start_prediction_request(meta: Dictionary) -> void:
	var branch_key: String = str(meta.get("branch_key", meta.get("choice_id", "")))
	var cache_key: String = meta.get("cache_key", "")
	if branch_key == "" or cache_key == "" or _prediction_requests.has(branch_key):
		return
	var branch := _get_prediction_branch(branch_key)
	if branch.is_empty() or str(branch.get("status", "")) == "completed":
		return
	var request := HTTPRequest.new()
	request.timeout = request_timeout
	add_child(request)
	_prediction_requests[branch_key] = request
	_prediction_request_meta[branch_key] = meta.duplicate(true)
	branch["status"] = "requesting"
	branch["request_meta"] = meta.duplicate(true)
	branch["last_error"] = ""
	_set_prediction_branch(branch_key, branch)
	request.request_completed.connect(_on_prediction_request_completed.bind(branch_key, request))
	var choice_id := int(meta.get("choice_id", 0))
	var choice_text := str(meta.get("choice_text", ""))
	var history_snapshot: Array = meta.get("history_snapshot", [])
	var choices_snapshot: Array = meta.get("choices_snapshot", [])
	var input_str := "__choice__:%d:%s" % [choice_id, choice_text]
	var request_data := _build_provider_request(input_str, history_snapshot, choices_snapshot)
	var endpoint: String = request_data.get("endpoint", "")
	var headers: PackedStringArray = request_data.get("headers", PackedStringArray())
	var payload: Dictionary = request_data.get("payload", {})
	print("[AIManager] 预测选项 %d 请求: %s" % [choice_id, endpoint])
	var error = request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_prediction_requests.erase(branch_key)
		_prediction_request_meta.erase(branch_key)
		_cleanup_request_node(request)
		call_deferred("_retry_prediction_request", meta, "request_error=%d" % error)

func rebuild_predictions_for_current_state(preserve_completed: bool = true) -> void:
	_cancel_prediction_requests()
	if not ai_enabled or not GameManager or not GameManager.ai_enabled:
		if not preserve_completed:
			cancel_predictions()
		return
	if preserve_completed and not _prediction_asset.is_empty():
		_resume_prediction_asset_requests()
		return
	var scene = DialogueManager.get_dialogue_scene() if has_node("/root/DialogueManager") else null
	if scene:
		var visible_choices = scene.get("current_choices")
		var choice_panel = scene.get("choice_panel")
		if visible_choices is Array and visible_choices.size() > 0 and choice_panel and choice_panel.visible:
			prefetch_choice_predictions(visible_choices, GameManager.dialogue_history.duplicate(true), preserve_completed)
			return
	if has_node("/root/ScriptEngine") and ScriptEngine.has_method("get_pending_commands"):
		var pending_commands: Array = ScriptEngine.get_pending_commands()
		_prefetch_predictions_from_commands(pending_commands, preserve_completed)

func _resume_prediction_asset_requests() -> void:
	if _prediction_asset.is_empty():
		return
	_normalize_restored_prediction_asset()
	_active_prediction_context_key = str(_prediction_asset.get("context_key", ""))
	var history = _prediction_asset.get("history_snapshot", [])
	var choices = _prediction_asset.get("choices_snapshot", [])
	_prediction_history_snapshot = history.duplicate(true) if history is Array else []
	_prediction_choices_snapshot = choices.duplicate(true) if choices is Array else []
	var branches: Dictionary = _prediction_asset.get("branches", {})
	for branch_key in branches.keys():
		if not _should_request_prediction_branch(str(branch_key)):
			continue
		var branch: Dictionary = branches[branch_key]
		var meta = branch.get("request_meta", {})
		if not meta is Dictionary or meta.is_empty():
			meta = _build_prediction_meta_for_choice(
				int(branch.get("choice_id", 0)),
				str(branch.get("choice_text", "")),
				str(branch_key)
			)
		if meta is Dictionary and not meta.is_empty():
			_start_prediction_request(meta)

func get_prediction_state_for_save() -> Dictionary:
	return {
		"asset": _prediction_asset.duplicate(true)
	}

func restore_prediction_state_from_save(state: Dictionary) -> void:
	cancel_predictions()
	if state.is_empty():
		return
	var asset = state.get("asset", {})
	_prediction_asset = asset.duplicate(true) if asset is Dictionary else {}
	_active_prediction_context_key = str(_prediction_asset.get("context_key", ""))
	var history = _prediction_asset.get("history_snapshot", [])
	var choices = _prediction_asset.get("choices_snapshot", [])
	_prediction_history_snapshot = history.duplicate(true) if history is Array else []
	_prediction_choices_snapshot = choices.duplicate(true) if choices is Array else []
	_normalize_restored_prediction_asset()

func _normalize_restored_prediction_asset() -> void:
	var branches: Dictionary = _prediction_asset.get("branches", {})
	for key in branches.keys():
		var branch: Dictionary = branches[key]
		if str(branch.get("status", "")) in ["requesting", "retrying"]:
			branch["status"] = "failed"
		if not branch.has("last_error"):
			branch["last_error"] = ""
		branches[key] = branch
	_prediction_asset["branches"] = branches

func try_consume_choice_prediction(choice_id: int, choice_text: String) -> bool:
	if _active_prediction_context_key == "":
		var choices := GameManager.pending_choices.duplicate(true) if GameManager else []
		if choices.is_empty() or not GameManager:
			return false
		_active_prediction_context_key = _build_prediction_context_key(GameManager.dialogue_history.duplicate(true), choices)
		_prediction_history_snapshot = GameManager.dialogue_history.duplicate(true)
		_prediction_choices_snapshot = choices
		_prediction_asset = _create_prediction_asset(_active_prediction_context_key, _prediction_history_snapshot, _prediction_choices_snapshot)
	var branch_key := _find_prediction_branch_key(choice_id)
	var branch := _get_prediction_branch(branch_key)
	if branch.is_empty():
		var cache_key := _build_prediction_cache_key(_active_prediction_context_key, choice_id, choice_text)
		branch = _ensure_prediction_branch(choice_id, choice_text, cache_key)
	var commands = branch.get("commands", [])
	if not commands is Array:
		commands = []
	if commands.is_empty() and not _prediction_requests.has(branch_key):
		var meta := _build_prediction_meta_for_choice(choice_id, choice_text, branch_key)
		if meta.is_empty():
			return false
		_waiting_for_prediction_result = true
		_prediction_retry_counts[branch_key] = 0
		_start_prediction_request(meta)
	_selected_prediction_key = branch_key
	_selected_prediction_commands = commands.duplicate(true)
	_waiting_for_prediction_result = _selected_prediction_commands.is_empty()
	_selected_prediction_execute_queued = false
	_selected_prediction_choice_id = choice_id
	_prediction_asset["selected_choice_id"] = choice_id
	_prediction_asset["selected_branch_key"] = branch_key
	_cancel_unselected_predictions(branch_key)
	print("[AIManager] 锁定选项预测分支: %d" % choice_id)
	_try_execute_selected_prediction()
	return true

func _build_prediction_meta_for_choice(choice_id: int, choice_text: String, branch_key: String) -> Dictionary:
	var resolved_text := choice_text
	if resolved_text == "":
		for choice in _prediction_choices_snapshot:
			if choice is Dictionary and str(choice.get("id", "")) == str(choice_id):
				resolved_text = str(choice.get("text", ""))
				break
	if resolved_text == "":
		resolved_text = _resolve_choice_text(choice_id)
	if resolved_text == "":
		return {}
	var cache_key := _build_prediction_cache_key(_active_prediction_context_key, choice_id, resolved_text)
	if cache_key == "":
		return {}
	_ensure_prediction_branch(choice_id, resolved_text, cache_key)
	return {
		"branch_key": branch_key,
		"cache_key": cache_key,
		"context_key": _active_prediction_context_key,
		"choice_id": choice_id,
		"choice_text": resolved_text,
		"history_snapshot": _prediction_history_snapshot.duplicate(true),
		"choices_snapshot": _prediction_choices_snapshot.duplicate(true)
	}

func _find_prediction_branch_key(choice_id: int) -> String:
	return str(choice_id)

func cancel_predictions() -> void:
	_cancel_prediction_requests()
	_prediction_retry_counts.clear()
	_prediction_asset.clear()
	_active_prediction_context_key = ""
	_prediction_history_snapshot.clear()
	_prediction_choices_snapshot.clear()
	_selected_prediction_key = ""
	_selected_prediction_commands.clear()
	_waiting_for_prediction_result = false
	_selected_prediction_execute_queued = false
	_selected_prediction_choice_id = -1

func _cancel_prediction_requests() -> void:
	for key in _prediction_requests.keys().duplicate():
		var request = _prediction_requests[key]
		if request is HTTPRequest and is_instance_valid(request):
			request.cancel_request()
			_cleanup_request_node(request)
	_prediction_requests.clear()
	_prediction_request_meta.clear()

func _cancel_unselected_predictions(selected_key: String) -> void:
	for key in _prediction_requests.keys().duplicate():
		if key == selected_key:
			continue
		var request = _prediction_requests[key]
		if request is HTTPRequest and is_instance_valid(request):
			request.cancel_request()
			_cleanup_request_node(request)
		_prediction_requests.erase(key)
		_prediction_request_meta.erase(key)
		var branch := _get_prediction_branch(str(key))
		if not branch.is_empty():
			if str(branch.get("status", "")) != "completed":
				branch["status"] = "cancelled"
			_set_prediction_branch(str(key), branch)
	for key in _prediction_retry_counts.keys().duplicate():
		if key != selected_key:
			_prediction_retry_counts.erase(key)

func _execute_prediction_commands(commands: Array) -> void:
	if _is_script_engine_running():
		_selected_prediction_execute_queued = false
		return
	_waiting_for_choice_continuation = false
	_selected_prediction_key = ""
	_selected_prediction_commands.clear()
	_waiting_for_prediction_result = false
	_selected_prediction_execute_queued = false
	_selected_prediction_choice_id = -1
	_prediction_retry_counts.clear()
	_prediction_asset.clear()
	_active_prediction_context_key = ""
	_prediction_history_snapshot.clear()
	_prediction_choices_snapshot.clear()
	if not has_node("/root/ScriptEngine"):
		return
	_prefetch_predictions_from_commands(commands)
	ScriptEngine.execute_commands(commands)

func _on_prediction_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, branch_key: String, request: HTTPRequest) -> void:
	var meta: Dictionary = _prediction_request_meta.get(branch_key, {}).duplicate(true)
	_prediction_requests.erase(branch_key)
	_prediction_request_meta.erase(branch_key)
	_cleanup_request_node(request)
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[AIManager] 预测请求失败: %s result=%d" % [branch_key, result])
		_mark_prediction_branch_failed(branch_key, meta, "result=%d" % result)
		_retry_prediction_request(meta, "result=%d" % result)
		return
	var raw_text := body.get_string_from_utf8()
	var ai_response := _parse_ai_response(raw_text, response_code, "预测请求")
	if ai_response.is_empty() or not ai_response.has("commands"):
		_mark_prediction_branch_failed(branch_key, meta, "empty_response")
		_retry_prediction_request(meta, "empty_response")
		return
	var commands = ai_response.get("commands", [])
	if not commands is Array:
		_mark_prediction_branch_failed(branch_key, meta, "invalid_commands")
		_retry_prediction_request(meta, "invalid_commands")
		return
	commands = _normalize_ai_commands(commands)
	if not commands.is_empty():
		_prediction_retry_counts.erase(branch_key)
		var branch := _get_prediction_branch(branch_key)
		if not branch.is_empty():
			branch["status"] = "completed"
			branch["commands"] = commands.duplicate(true)
			branch["request_meta"] = meta.duplicate(true)
			branch["last_error"] = ""
			_set_prediction_branch(branch_key, branch)
		print("[AIManager] 预测分支已写入: %s" % branch_key)
		if branch_key == _selected_prediction_key:
			_selected_prediction_commands = commands
			_waiting_for_prediction_result = false
			_try_execute_selected_prediction()
	else:
		_mark_prediction_branch_failed(branch_key, meta, "empty_commands")
		_retry_prediction_request(meta, "empty_commands")

func _try_execute_selected_prediction() -> void:
	if _selected_prediction_key == "":
		return
	if not _selected_prediction_commands.is_empty():
		if _selected_prediction_execute_queued:
			return
		if _is_script_engine_running():
			print("[AIManager] 选中分支预测已就绪，等待当前脚本结束后执行。")
			return
		_selected_prediction_execute_queued = true
		_execute_prediction_commands(_selected_prediction_commands.duplicate(true))
	elif _waiting_for_prediction_result:
		_show_ai_waiting()
		print("[AIManager] 等待选中分支预测完成。")

func _retry_prediction_request(meta: Dictionary, reason: String) -> void:
	if meta.is_empty():
		return
	var branch_key: String = str(meta.get("branch_key", meta.get("choice_id", "")))
	var context_key: String = meta.get("context_key", "")
	if context_key != "" and context_key != _active_prediction_context_key:
		return
	if branch_key == "" or _prediction_requests.has(branch_key):
		return
	var branch := _get_prediction_branch(branch_key)
	if not branch.is_empty() and str(branch.get("status", "")) == "completed":
		return
	var retry_count := int(_prediction_retry_counts.get(branch_key, branch.get("retry_count", 0))) + 1
	_prediction_retry_counts[branch_key] = retry_count
	if not branch.is_empty():
		branch["status"] = "retrying"
		branch["retry_count"] = retry_count
		branch["request_meta"] = meta.duplicate(true)
		branch["last_error"] = reason
		_set_prediction_branch(branch_key, branch)
	var delay = min(5.0, 0.5 + float(retry_count) * 0.5)
	print("[AIManager] 预测请求失败，将重新请求 (%d): %s" % [retry_count, reason])
	if branch_key == _selected_prediction_key:
		_waiting_for_prediction_result = true
		_selected_prediction_commands.clear()
		_try_execute_selected_prediction()
	await get_tree().create_timer(delay).timeout
	if _prediction_requests.has(branch_key):
		return
	if context_key != "" and context_key != _active_prediction_context_key:
		return
	if _selected_prediction_key != "" and branch_key != _selected_prediction_key:
		return
	_start_prediction_request(meta)

func _mark_prediction_branch_failed(branch_key: String, meta: Dictionary, reason: String) -> void:
	var branch := _get_prediction_branch(branch_key)
	if branch.is_empty():
		return
	branch["status"] = "failed"
	branch["request_meta"] = meta.duplicate(true)
	branch["last_error"] = reason
	_set_prediction_branch(branch_key, branch)

func _is_script_engine_running() -> bool:
	if not has_node("/root/ScriptEngine"):
		return false
	if ScriptEngine.has_method("is_running"):
		return ScriptEngine.is_running()
	return ScriptEngine.get("_is_running") == true

func _prefetch_predictions_from_commands(commands: Array, preserve_completed: bool = false) -> void:
	if commands.is_empty():
		return
	var history_snapshot := GameManager.dialogue_history.duplicate(true) if GameManager else []
	for cmd in commands:
		if not cmd is Dictionary:
			continue
		var type: String = cmd.get("type", "")
		if type == "show_choices":
			prefetch_choice_predictions(cmd.get("choices", []), history_snapshot, preserve_completed)
			return
		elif type == "show_dialogue":
			history_snapshot.append({
				"character": _format_history_character_name(str(cmd.get("character", ""))),
				"text": str(cmd.get("text", "")),
				"type": "dialogue",
				"id": str(cmd.get("character", ""))
			})
		elif type == "long_dialogue":
			history_snapshot.append({
				"character": "",
				"text": str(cmd.get("text", "")),
				"type": "long_dialogue",
				"id": ""
			})

func _format_history_character_name(character_id: String) -> String:
	if character_id != "" and GameManager and GameManager.character_database.has(character_id):
		return "[b]" + GameManager.character_database[character_id].display_name + "[/b]"
	return character_id

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
	var chat_messages := _build_chat_messages(provider, model_name, system_prompt, user_prompt)

	match api_format:
		"ollama_chat":
			_is_ollama_request = true
			return {
				"endpoint": base + "/api/chat",
				"headers": PackedStringArray(["Content-Type: application/json"]),
				"payload": {
					"model": model_name,
					"messages": chat_messages,
					"format": "json",
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
					"generationConfig": {
						"temperature": temperature,
						"maxOutputTokens": output_tokens,
						"responseMimeType": "application/json"
					}
				}
			}
		_:
			_is_ollama_request = false
			var payload := {
				"model": model_name,
				"messages": chat_messages
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
		_head_warmup_asset["status"] = "failed"
		if _warmup_consume_pending:
			_handle_consumed_warmup_failure(0, "[AIManager] 开场预热请求失败。")
		return
	var raw_text := body.get_string_from_utf8()
	if response_code == 429 and _schedule_warmup_retry():
		return
	var ai_response := _parse_ai_response(raw_text, response_code, "开场预热")
	if ai_response.is_empty():
		_head_warmup_asset["status"] = "failed"
		if _warmup_consume_pending:
			_handle_consumed_warmup_failure(response_code, "[AIManager] 开场预热响应不可用。")
		return
	if _warmup_consume_pending:
		_warmup_consume_pending = false
		_process_warmup_start_response(ai_response)
	else:
		_warmup_retry_count = 0
		_head_warmup_asset["status"] = "completed"
		_head_warmup_asset["response"] = ai_response.duplicate(true)
		_warmup_start_response = ai_response
		print("[AIManager] 开场预热缓存已就绪。")

func _handle_consumed_warmup_failure(response_code: int, reason: String) -> void:
	_warmup_consume_pending = false
	_is_requesting = false
	_finish_requesting()
	_last_error_code = 0
	_last_response_code = response_code
	if response_code == 429:
		_recover_with_dialogue(reason)
	else:
		call_deferred("send_message", "__start__")

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

func _build_chat_messages(provider: Dictionary, model_name: String, system_prompt: String, user_prompt: String) -> Array:
	var system_role := "system"
	if _should_use_developer_message(provider, model_name):
		system_role = "developer"
	return [
		{"role": system_role, "content": system_prompt},
		{"role": "user", "content": user_prompt}
	]

func _should_use_developer_message(provider: Dictionary, model_name: String) -> bool:
	var provider_id: String = provider.get("id", "")
	var normalized_model := model_name.to_lower()
	return provider_id == "openai" and (normalized_model.begins_with("gpt-5") or normalized_model.begins_with("o"))

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
	if provider_id == "kimi" or provider_id == "minimax":
		return "max_completion_tokens"
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
	return provider_id in ["kimi", "openai", "deepseek", "zhipu", "mistral"]

func _build_headers(provider: Dictionary, api_key: String) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var auth_type: String = provider.get("auth_type", "bearer")
	if auth_type == "bearer" and api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	elif auth_type == "x-api-key":
		if api_key != "":
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
	result = result.replace("[]", "")
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
	elif _last_response_code == 429:
		help_text = "AI服务现在有点忙，请稍后再试。\n\n如果频繁出现，可以先切换到本地 Ollama，或换一个当前更空闲的模型。"
	else:
		help_text = "AI正在全力思考中，稍等哦~"

	if has_node("/root/ScriptEngine"):
		ScriptEngine.execute_commands([{"type": "show_dialogue", "character": "", "text": help_text}])
