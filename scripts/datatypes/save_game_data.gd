# save_game_data.gd
class_name SaveGameData
extends Resource

# 存档元信息
@export var save_date: String = ""
@export var save_time: String = ""
@export var save_description: String = ""
@export var screenshot_path: String = ""
@export var play_time: float = 0.0

# 游戏状态
@export var current_scene: String = ""
@export var current_background_id: String = ""
@export var current_bgm_id: String = ""
@export var variables: Dictionary = {}

# 对话 UI 状态
@export var dialogue_text: String = ""
@export var character_name: String = ""
@export var choice_options: Array = []
@export var dialogue_history: Array = []

# 角色状态
@export var active_characters: Array = []
@export var character_expressions: Dictionary = {}
@export var character_positions: Dictionary = {}

# 粒子效果
@export var active_particle_effects: Array = []

# 收藏列表
@export var unlocked_cgs: Array = []
@export var unlocked_bgms: Array = []

# 剧本执行状态
@export var commands: Array = []
@export var command_index: int = 0
@export var pending_commands: Array = []


## 从字典恢复数据（供加载时使用）
func restore_from_dict(dict: Dictionary) -> void:
	save_date = dict.get("save_date", "")
	save_time = dict.get("save_time", "")
	save_description = dict.get("save_description", "")
	screenshot_path = dict.get("screenshot_path", "")
	play_time = dict.get("play_time", 0.0)
	current_scene = dict.get("current_scene", "")
	current_background_id = dict.get("current_background_id", "")
	current_bgm_id = dict.get("current_bgm_id", "")
	variables = dict.get("variables", {})
	dialogue_history = dict.get("dialogue_history", [])
	dialogue_text = dict.get("dialogue_text", "")
	character_name = dict.get("character_name", "")
	choice_options = dict.get("choice_options", [])
	active_characters = dict.get("active_characters", [])
	character_expressions = dict.get("character_expressions", {})
	character_positions = dict.get("character_positions", {}) 
	active_particle_effects = dict.get("active_particle_effects", [])
	commands = dict.get("commands", [])
	command_index = dict.get("command_index", 0)
	pending_commands = dict.get("pending_commands", [])


## 将数据转为可 JSON 序列化的字典
func to_dict() -> Dictionary:
	return {
		"save_date": save_date,
		"save_time": save_time,
		"save_description": save_description,
		"screenshot_path": screenshot_path,
		"play_time": play_time,
		"current_scene": current_scene,
		"current_background_id": current_background_id,
		"current_bgm_id": current_bgm_id,
		"variables": variables,
		"dialogue_history": dialogue_history,
		"dialogue_text": dialogue_text,
		"character_name": character_name,
		"choice_options": choice_options,
		"active_characters": active_characters,
		"character_expressions": character_expressions,
		"character_positions": character_positions,
		"active_particle_effects": active_particle_effects,
		"unlocked_cgs": unlocked_cgs,
		"unlocked_bgms": unlocked_bgms,
		"commands": commands,
		"command_index": command_index,
		"pending_commands": pending_commands,
	}
