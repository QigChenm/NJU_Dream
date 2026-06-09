# affection_ui.gd
extends CanvasLayer

# ================= 属性 =================
var _rows: Dictionary = {}
var _time_timer: Timer = null

# ================= 节点 =================
@onready var pad_triangle: Control = $VBoxContainer/PADContainer/PADTriangle
@onready var pad_description: Label = $VBoxContainer/PADContainer/PadDescription
@onready var current_time_label: Label = $VBoxContainer/PADContainer/CurrentTime

# ================= 初始化 =================
func _ready() -> void:
	visible = false
	_scan_rows()
	if GameManager.has_signal("variable_changed"):
		GameManager.variable_changed.connect(_on_variable_changed)
	_refresh_all()
	
	_time_timer = Timer.new()
	_time_timer.name = "TimeUpdateTimer"
	_time_timer.wait_time = 1.0
	_time_timer.one_shot = false
	_time_timer.process_mode = PROCESS_MODE_ALWAYS
	_time_timer.timeout.connect(_update_time)
	add_child(_time_timer)
	_time_timer.start()
	_update_time()

	if GameManager.has_signal("pad_description_changed"):
		GameManager.pad_description_changed.connect(_on_pad_description_changed)
	_refresh_pad_triangle()

	visibility_changed.connect(_on_visibility_changed)

# ================= 内部方法 =================
func _scan_rows() -> void:
	var vbox = $VBoxContainer
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
		var key: String = name_label.get_meta("character_id", name_label.text.to_lower())
		if key == "":
			match name_label.text:
				"小貅":
					key = "xiu"
				"宋青":
					key = "song"
				_:
					key = name_label.text.to_lower()
		
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

func _update_time():
	if not is_instance_valid(current_time_label):
		return
	var dt = Time.get_datetime_dict_from_system()
	current_time_label.text = "当前时间：%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]

func _refresh_pad_triangle():
	if pad_triangle and pad_triangle.has_method("update_pad"):
		pad_triangle.update_pad(GameManager.pad_pleasure, GameManager.pad_arousal, GameManager.pad_dominance)

func _on_pad_description_changed(new_text: String):
	if pad_description:
		pad_description.text = new_text

func _on_visibility_changed():
	if visible:
		_refresh_pad_triangle()
		if GameManager.pad_description != "":
			pad_description.text = GameManager.pad_description
		_update_time()

func _exit_tree():
	if _time_timer:
		_time_timer.queue_free()
