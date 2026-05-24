# affection_ui.gd
extends CanvasLayer

# ================= 属性 =================
var _rows: Dictionary = {}


# ================= 初始化 =================
func _ready() -> void:
	visible = false
	_scan_rows()
	if GameManager.has_signal("variable_changed"):
		GameManager.variable_changed.connect(_on_variable_changed)
	_refresh_all()


# ================= 内部方法 =================
func _scan_rows() -> void:
	var panel = $Panel
	if not panel:
		return
	var vbox = panel.get_node_or_null("VBoxContainer")
	if not vbox:
		return

	for child in vbox.get_children():
		if not child is HBoxContainer:
			continue
		var name_label: Label = child.get_node_or_null("NameLabel") as Label
		var value_label: Label = child.get_node_or_null("ValueLabel") as Label
		var bar: ProgressBar = child.get_node_or_null("ProgressBar") as ProgressBar
		if not name_label or not value_label or not bar:
			continue

		# 尝试从元数据获取角色 ID，否则降级为标签文本
		var key: String = name_label.get_meta("character_id", name_label.text.to_lower())
		_rows[key] = {
			"name_label": name_label,
			"value_label": value_label,
			"bar": bar,
			"target_value": bar.value,
			"tween": null
		}


func _refresh_all() -> void:
	for key in _rows.keys():
		_update_row(key)


func _update_row(key: String) -> void:
	if not _rows.has(key):
		return
	var row = _rows[key]
	if not is_instance_valid(row.get("value_label")) or not is_instance_valid(row.get("bar")):
		return

	var var_name = "affection_" + key
	var value = GameManager.get_variable(var_name)
	if value == null:
		value = 0

	row["target_value"] = float(value)
	row["value_label"].text = str(int(value))

	if row["tween"] and row["tween"].is_valid():
		row["tween"].kill()
	row["tween"] = create_tween()
	row["tween"].tween_property(row["bar"], "value", row["target_value"], 0.3).set_ease(Tween.EASE_OUT)


func _on_variable_changed(variable: String, _new_value) -> void:
	if variable.begins_with("affection_"):
		var key = variable.replace("affection_", "")
		_update_row(key)
