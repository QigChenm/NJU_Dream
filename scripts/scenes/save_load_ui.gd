# save_load_ui.gd
extends CanvasLayer

# ================= 属性 =================
@export var custom_font: Font

const MAX_SLOTS := 20
var _mode: String = "save"
var _slot_buttons: Array = []
var _confirm_dialog: ConfirmationDialog = null
var _pending_delete_slot: int = -1

@onready var slot_grid := $Panel/VBoxContainer/ScrollContainer/SlotGrid


# ================= 初始化 =================
func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS
	_generate_slots()
	_create_confirm_dialog()


func _generate_slots() -> void:
	for btn in _slot_buttons:
		btn.queue_free()
	_slot_buttons.clear()

	var slot_width := 452.0
	var slot_height := 200.0

	for i in range(MAX_SLOTS):
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(slot_width, slot_height)
		slot_btn.name = "Slot_%d" % i
		slot_btn.expand_icon = true
		slot_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_grid.add_child(slot_btn)
		_slot_buttons.append(slot_btn)

	_refresh_slots()
	print("[SaveLoadUI] 槽位按钮已生成：%d 个" % MAX_SLOTS)


func _create_confirm_dialog() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "删除存档"
	_confirm_dialog.dialog_text = "确定要删除该存档吗？"
	_confirm_dialog.ok_button_text = "是（删除）"
	_confirm_dialog.cancel_button_text = "否（返回）"
	_confirm_dialog.process_mode = PROCESS_MODE_ALWAYS
	_confirm_dialog.min_size = Vector2(450, 200)

	if custom_font:
		_confirm_dialog.add_theme_font_override("title_font", custom_font)
	_confirm_dialog.add_theme_font_size_override("title_font_size", 30)
	_confirm_dialog.add_theme_constant_override("title_margin_top", 15)

	var content_label = _confirm_dialog.get_label()
	if content_label:
		if custom_font:
			content_label.add_theme_font_override("font", custom_font)
		content_label.add_theme_font_size_override("font_size", 30)

	var ok_btn = _confirm_dialog.get_ok_button()
	var cancel_btn = _confirm_dialog.get_cancel_button()
	if custom_font:
		ok_btn.add_theme_font_override("font", custom_font)
		cancel_btn.add_theme_font_override("font", custom_font)
	ok_btn.add_theme_font_size_override("font_size", 30)
	cancel_btn.add_theme_font_size_override("font_size", 30)

	var button_container = ok_btn.get_parent()
	if button_container is Container:
		button_container.add_theme_constant_override("separation", 10)

	for btn in [ok_btn, cancel_btn]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm_dialog)


# ================= 删除逻辑 =================
func _on_delete_confirmed() -> void:
	if _pending_delete_slot < 0:
		return
	print("[SaveLoadUI] 确认删除槽位 %d" % _pending_delete_slot)
	SaveManager.delete_save(_pending_delete_slot)
	_compact_slots(_pending_delete_slot)
	_pending_delete_slot = -1
	_refresh_slots()


func _compact_slots(deleted_slot: int) -> void:
	for i in range(deleted_slot + 1, MAX_SLOTS):
		if not SaveManager.has_save(i):
			continue

		var src_path = SaveManager._get_save_path(i)
		var dst_path = SaveManager._get_save_path(i - 1)
		var file = FileAccess.open(src_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var dst_file = FileAccess.open(dst_path, FileAccess.WRITE)
			if dst_file:
				dst_file.store_string(content)
				dst_file.close()
		DirAccess.remove_absolute(src_path)

		var src_thumb = SaveManager._get_thumbnail_path(i)
		var dst_thumb = SaveManager._get_thumbnail_path(i - 1)
		if FileAccess.file_exists(src_thumb):
			var img = Image.load_from_file(src_thumb)
			if img:
				img.save_png(dst_thumb)
			DirAccess.remove_absolute(src_thumb)

	# 清理最后一个槽位的残留文件
	var last_path = SaveManager._get_save_path(MAX_SLOTS - 1)
	if FileAccess.file_exists(last_path):
		DirAccess.remove_absolute(last_path)
	var last_thumb = SaveManager._get_thumbnail_path(MAX_SLOTS - 1)
	if FileAccess.file_exists(last_thumb):
		DirAccess.remove_absolute(last_thumb)

	print("[SaveLoadUI] 槽位已重排，从槽位 %d 开始向前移动" % deleted_slot)


# ================= 界面刷新 =================
func _refresh_slots() -> void:
	for i in range(MAX_SLOTS):
		var info = SaveManager.get_save_info(i)
		var btn = _slot_buttons[i]
		if info.get("exists", false):
			btn.text = "存档口 %d\n%s\n%s" % [i + 1, info.get("date", ""), info.get("description", "")]
			var thumb_path = info.get("thumbnail", "")
			if thumb_path != "" and FileAccess.file_exists(thumb_path):
				var img = Image.load_from_file(thumb_path)
				if img:
					btn.icon = ImageTexture.create_from_image(img)
		else:
			btn.text = "存档口 %d\n（空）" % (i + 1)
			btn.icon = null

		if custom_font:
			btn.add_theme_font_override("font", custom_font)
		btn.add_theme_font_size_override("font_size", 30)


func set_mode(mode: String) -> void:
	_mode = mode
	var title = $Panel/VBoxContainer/TitleLabel
	title.text = "存档" if mode == "save" else "读档"
	_refresh_slots()
	print("[SaveLoadUI] 模式切换到：%s" % _mode)


# ================= 输入处理 =================
func _input(event: InputEvent) -> void:
	if not visible or not get_tree().paused:
		return

	# 1. 检测“返回主界面”按钮
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if UIManager._return_to_menu_active:
			var rect = UIManager.get_return_to_menu_button_rect()
			if rect.has_point(get_viewport().get_mouse_position()):
				var scene = get_tree().current_scene
				if scene and scene.has_method("_on_return_to_menu_pressed"):
					scene._on_return_to_menu_pressed()
				return

		# 2. 检测普通返回按钮
		var return_rect = UIManager.get_return_button_rect()
		if return_rect.has_point(get_viewport().get_mouse_position()):
			UIManager.close_current_panel()
			return

	# 3. 检测槽位点击
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos := get_viewport().get_mouse_position()
		for i in range(_slot_buttons.size()):
			var btn = _slot_buttons[i]
			if Rect2(btn.global_position, btn.size).has_point(mouse_pos):
				if event.button_index == MOUSE_BUTTON_LEFT:
					print("[SaveLoadUI] 槽位 %d 左键点击，当前模式：%s" % [i, _mode])
					_on_slot_pressed(i)
				elif event.button_index == MOUSE_BUTTON_RIGHT and SaveManager.has_save(i):
					print("[SaveLoadUI] 槽位 %d 右键点击，弹出删除确认" % i)
					_pending_delete_slot = i
					_confirm_dialog.popup_centered()
				return


func _on_slot_pressed(slot: int) -> void:
	if _mode == "save":
		_capture_and_save(slot)
	elif _mode == "load":
		if SaveManager.load_game(slot):
			SaveManager.continue_mode = false
			UIManager.hide_return_to_menu_button()
			UIManager.close_panel("SaveLoadUI")


func _capture_and_save(slot: int) -> void:
	visible = false

	var scene = get_tree().current_scene
	if scene and scene.has_method("hide_all_ui_for_screenshot"):
		scene.hide_all_ui_for_screenshot()

	await get_tree().process_frame
	await get_tree().process_frame

	var viewport := get_viewport()
	var img := viewport.get_texture().get_image()
	if not img.is_empty():
		var new_width := int(img.get_width() * 0.25)
		var new_height := int(img.get_height() * 0.25)
		if new_width > 0 and new_height > 0:
			img.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)
		img.save_png(SaveManager._get_thumbnail_path(slot))

	if scene and scene.has_method("show_all_ui"):
		scene.show_all_ui()

	SaveManager.save_game(slot)

	visible = true
	_refresh_slots()
