# dialogue_manager.gd
extends Node

# ================= 信号 =================
signal dialogue_finished()
signal line_finished
signal choice_made(choice_id: int)

# ================= 属性 =================
var ai_adapter = null
var dialogue_queue: Array = []
var is_requesting = false
var ui_is_ready = false
var _scene_instance: Control = null
var _first_response: bool = false


# ================= 初始化 =================
func _ready() -> void:
	call_deferred("_cache_scene_instance")
	if has_node("/root/ScriptEngine"):
		if not ScriptEngine.is_connected("execution_finished", _on_script_engine_finished):
			ScriptEngine.connect("execution_finished", _on_script_engine_finished)


func _cache_scene_instance() -> void:
	_scene_instance = get_tree().current_scene as Control


func _on_script_engine_finished() -> void:
	if ai_adapter and not is_requesting:
		await request_ai_response("__continue__")
		

# ================= 旧版对话启动流程（保留用于未来 AI 接入） =================
func start_dialogue() -> void:
	dialogue_queue.clear()
	_first_response = true
	await request_ai_response("__start__")


func request_next() -> void:
	if dialogue_queue.is_empty():
		await request_ai_response("__continue__")
	else:
		show_next_line()


func submit_choice(choice_id: int) -> void:
	await request_ai_response("__choice__:" + str(choice_id))


func request_ai_response(input_str: String) -> void:
	if ai_adapter and ai_adapter.has_method("send_message"):
		is_requesting = true
		await ai_adapter.send_message(input_str, _on_ai_response)
	else:
		# 测试用命令序列（未接入 AI 时自动执行）
		var test_script = [
	{"type": "change_background", "background": "nansu", "transition": "fade"},
	{"type": "particle_play", "effect_id": "petal"},
	{"type": "play_audio", "audio_id": "spring_forest", "crossfade": 1.5},
	{"type": "set_characters", "left": {"id": "xiu", "expression": "default", "entrance_animation": "slide_left"}, "entrance_animation": "fade"},
	{"type": "show_dialogue", "character": "xiu", "text": "！终于等到你了！[color=#FFB6C1]今天阳光真好呀～[/color]"},
	{"type": "set_expression", "character": "xiu", "expression": "very_happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "我们好久没一起在校园里散步了呢。最近课业忙吗？"},
	{"type": "show_dialogue", "character": "xiu", "text": "我跟你讲，我们院最近组织了一场超有趣的活动！"},
	{"type": "set_expression", "character": "xiu", "expression": "happy"},
	{"type": "character_action", "character": "xiu", "action": "bounce"},
	{"type": "show_dialogue", "character": "xiu", "text": "下周有樱花节，好多社团都摆摊了，[shake rate=15 level=3]我们一起去逛逛吧！[/shake]"},
	{"type": "show_choices", "choices": [{"id": 1, "text": "好啊，一定去！"}, {"id": 2, "text": "看时间吧，可能很忙。"}]},
	{"type": "add_affection", "character": "xiu", "delta": 5},
	{"type": "show_dialogue", "character": "xiu", "text": "嘻嘻，那就这么说定了！"},
	{"type": "show_dialogue", "character": "xiu", "text": "对了哥哥，你最近有没有遇到什么有趣的事？"},
	{"type": "show_dialogue", "character": "xiu", "text": "我上次在图书馆遇到一只流浪猫，好可爱呀，可惜宿管不让养……"},
	{"type": "set_expression", "character": "xiu", "expression": "sad"},
	{"type": "show_dialogue", "character": "xiu", "text": "如果能在宿舍养宠物就好了，[i]好想有一只小猫陪着我[/i]。"},
	{"type": "show_choices", "choices": [{"id": 1, "text": "以后我们合租就可以养了！"}, {"id": 2, "text": "你可以多去图书馆看看它。"}]},
	{"type": "add_affection", "character": "xiu", "delta": 10},
	{"type": "show_dialogue", "character": "xiu", "text": "哇，真的吗？哥哥你愿意和我一起住？[color=#FFD700]那我可太开心了！[/color]"},
	{"type": "set_expression", "character": "xiu", "expression": "very_happy"},
	{"type": "character_action", "character": "xiu", "action": "bounce"},
	{"type": "show_dialogue", "character": "xiu", "text": "好了啦，不说这些了。我们去那边的小路走走吧～"},
	{"type": "wait", "duration": 1.0},
	{"type": "long_dialogue", "text": "春日的午后，两人漫步在南大鼓楼校区的梧桐大道上。阳光透过嫩绿的叶子洒下斑驳的光影，空气中弥漫着淡淡的花香。妹妹轻轻哼着歌，时不时侧过头看着哥哥的侧脸，眼睛里闪着细碎的光。这样的时光，仿佛被拉得很长很长。"},
	{"type": "show_dialogue", "character": "xiu", "text": "哥哥，你觉得大学四年最珍贵的是什么？"},
	{"type": "show_choices", "choices": [{"id": 1, "text": "当然是遇到了你。"}, {"id": 2, "text": "学到了很多知识。"}]},
	{"type": "add_affection", "character": "xiu", "delta": 15},
	{"type": "show_dialogue", "character": "xiu", "text": "……哥哥你突然说这种话，[shake rate=10 level=3]人家会害羞的啦！[/shake]"},
	{"type": "set_expression", "character": "xiu", "expression": "happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "不过，我也是这么想的。和你在一起的每一天，都特别开心。"},
	{"type": "add_affection", "character": "xiu", "delta": 5},
	{"type": "set_flag", "flag": "spring_walk_done", "value": true},
	{"type": "wait", "duration": 1.5},
	{"type": "change_background", "background": "beidalou", "transition": "fade"},
	{"type": "particle_stop", "effect_id": "petal"},
	{"type": "particle_play", "effect_id": "snow"},
	{"type": "play_audio", "audio_id": "love_piano", "crossfade": 2.0},
	{"type": "set_characters", "left": {"id": "xiu", "expression": "default", "entrance_animation": "fade"}, "entrance_animation": "none"},
	{"type": "show_dialogue", "character": "xiu", "text": "啊……下雪了。时间过得好快，转眼就到冬天了。"},
	{"type": "set_expression", "character": "xiu", "expression": "sad"},
	{"type": "show_dialogue", "character": "xiu", "text": "哥哥，你还记得我们春天时的约定吗？"},
	{"type": "show_dialogue", "character": "xiu", "text": "我有时候会想，如果有一天我们分开了，会是什么样子……"},
	{"type": "show_choices", "choices": [{"id": 1, "text": "傻瓜，我们不会分开的。"}, {"id": 2, "text": "未来谁说得准呢。"}]},
	{"type": "add_affection", "character": "xiu", "delta": 10},
	{"type": "show_dialogue", "character": "xiu", "text": "谢谢你，哥哥。有你在身边，我觉得什么都不怕了。"},
	{"type": "set_expression", "character": "xiu", "expression": "happy"},
	{"type": "character_action", "character": "xiu", "action": "shake"},
	{"type": "show_dialogue", "character": "xiu", "text": "雪好像越来越大了……你能牵着我的手走吗？"},
	{"type": "wait", "duration": 1.0},
	{"type": "unlock_cg", "cg_id": "heroine_smile"},
	{"type": "cg_play", "cg_id": "heroine_smile"},
	{"type": "show_dialogue", "character": "xiu", "text": "这个冬天，[color=#87CEEB]因为有你在，变得特别温暖。[/color]"},
	{"type": "add_affection", "character": "xiu", "delta": 20},
	{"type": "set_expression", "character": "xiu", "expression": "very_happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "哥哥，[wave amp=50.0 freq=5.0]我最喜欢你了！[/wave]"},
	{"type": "show_dialogue", "character": "", "text": "就这样，两人的故事在飘雪的梧桐树下，翻开了新的一页。"},
	{"type": "unlock_bgm", "bgm_id": "love_piano"},
	{"type": "set_variable", "variable": "ending_type", "value": 1},
	{"type": "set_ui_state", "element": "DialogueBox", "state": "hidden"},
	{"type": "stop_audio", "audio_id": "love_piano", "fade_out": 2.0},
	{"type": "end_scene"}
]
		ScriptEngine.execute_commands(test_script)


func _on_ai_response(data: Dictionary) -> void:
	is_requesting = false
	AIManager.process_ai_response(data)
	dialogue_queue.append(data)
	if not is_waiting_for_ui_input():
		show_next_line()


# ================= ScriptEngine 调用接口 =================
func display_line(data: Dictionary) -> void:
	if not _scene_instance:
		_cache_scene_instance()
	if _scene_instance and _scene_instance.has_method("display_dialogue"):
		_scene_instance.display_dialogue(data)
		if not _scene_instance.is_connected("continue_pressed", _on_continue):
			_scene_instance.connect("continue_pressed", _on_continue, CONNECT_ONE_SHOT)


func display_options(choices: Array) -> void:
	if not _scene_instance:
		_cache_scene_instance()
	if _scene_instance and _scene_instance.has_method("display_choices"):
		_scene_instance.display_choices(choices)
		if _scene_instance.is_connected("choice_selected", _on_choice):
			_scene_instance.disconnect("choice_selected", _on_choice)
		_scene_instance.connect("choice_selected", _on_choice, CONNECT_ONE_SHOT)
		print("[DialogueManager] 选项信号已连接")
	else:
		push_error("[DialogueManager] 无法显示选项，场景实例无效。")


# ================= 信号回调 =================
func _on_continue() -> void:
	print("[DialogueManager] 玩家点击继续，发射 line_finished")
	line_finished.emit()


func _on_choice(choice_id: int) -> void:
	print("[DialogueManager] 玩家选择选项 %d，发射 choice_made" % choice_id)
	choice_made.emit(choice_id)


# ================= 辅助方法 =================
func show_next_line() -> void:
	if dialogue_queue.is_empty():
		return
	var data = dialogue_queue.pop_front()
	var scene = get_dialogue_scene()
	if scene:
		scene.display_dialogue(data)
		if data.has("choices") and data.choices.size() > 0:
			scene.display_choices(data.choices)


func get_dialogue_scene() -> Control:
	var root = get_tree().current_scene
	if root is Control:
		return root
	return null


func is_waiting_for_ui_input() -> bool:
	var scene = get_dialogue_scene()
	if scene and scene.has_method("is_waiting"):
		return scene.is_waiting_for_input
	return false


func display_long_dialogue(text: String) -> void:
	if not _scene_instance:
		_cache_scene_instance()
	if _scene_instance and _scene_instance.has_method("show_long_dialogue"):
		_scene_instance.show_long_dialogue(text)
		if not _scene_instance.is_connected("long_dialogue_finished", _on_long_dialogue_finished):
			_scene_instance.connect("long_dialogue_finished", _on_long_dialogue_finished, CONNECT_ONE_SHOT)


func _on_long_dialogue_finished() -> void:
	print("[DialogueManager] 长对话结束，发射 line_finished")
	line_finished.emit()
