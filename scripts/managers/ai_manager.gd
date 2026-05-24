# ai_manager.gd
extends Node

## AI 功能总开关（尚未启用）
@export var ai_enabled: bool = false

func _ready() -> void:
	# 目前无需连接信号，AI 接入后可能会扩展
	pass

## 处理 AI 返回的响应数据，将其中的命令列表交给 ScriptEngine 执行
func process_ai_response(response: Dictionary) -> void:
	if not response.has("commands"):
		return
	var commands = response["commands"]
	if not commands is Array:
		push_warning("[AIManager] 响应中的 'commands' 不是数组，已忽略。")
		return
	if not has_node("/root/ScriptEngine"):
		push_error("[AIManager] ScriptEngine 未找到，无法执行命令。")
		return
	ScriptEngine.execute_commands(commands)
