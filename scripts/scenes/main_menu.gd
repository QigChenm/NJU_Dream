# main_menu.gd
extends Control

# ================= 节点引用 =================
@onready var new_game_btn: Button = $VBoxContainer/NewGameButton
@onready var continue_btn: Button = $VBoxContainer/ContinueButton
@onready var settings_btn: Button = $VBoxContainer/SettingsButton
@onready var quit_btn: Button = $VBoxContainer/QuitButton


# ================= 初始化 =================
func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

	continue_btn.disabled = not SaveManager.has_any_save()


# ================= 按钮回调 =================
func _on_new_game() -> void:
	# 彻底重置引擎状态，防止旧场景残留影响新游戏
	if ScriptEngine:
		ScriptEngine.hard_reset()

	# 确保游戏未处于暂停状态
	if get_tree().paused:
		get_tree().paused = false

	# 重置游戏全局状态
	GameManager.start_new_game()

	# 清除背景管理器可能残留的旧背景ID
	if has_node("/root/BackgroundManager"):
		var bg_manager = get_node("/root/BackgroundManager")
		bg_manager.current_background_id = ""

	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_continue() -> void:
	SaveManager.continue_mode = true
	# 清空对话历史，等待读档时由存档数据恢复
	GameManager.dialogue_history.clear()
	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_settings() -> void:
	GameManager.open_settings_on_load = true
	get_tree().change_scene_to_file("res://scenes/dialogue_scene.tscn")


func _on_quit() -> void:
	get_tree().quit()
