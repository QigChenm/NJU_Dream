# backlog_ui.gd
extends CanvasLayer

@export var custom_font: Font

@onready var history_text: RichTextLabel = $Panel/VBoxContainer/ScrollContainer/HistoryText


func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	if not history_text:
		return

	if custom_font:
		history_text.add_theme_font_override("normal_font", custom_font)
		history_text.add_theme_font_size_override("normal_font_size", 32)
	else:
		history_text.add_theme_font_size_override("normal_font_size", 32)

	history_text.add_theme_constant_override("line_spacing", 12)
	history_text.bbcode_enabled = true


func refresh_history() -> void:
	if not history_text:
		return

	history_text.clear()
	var entries = GameManager.dialogue_history

	for i in range(entries.size()):
		var entry = entries[i]
		var character: String = entry.get("character", "")
		var text: String = entry.get("text", "")

		if character != "":
			history_text.append_text("[color=#FFD700][b]%s[/b][/color]\n" % character)
		history_text.append_text("[color=#FFFFFF]%s[/color]\n" % text)

		if i < entries.size() - 1:
			history_text.append_text("[color=#555555]──────────────────────────────[/color]\n")

	await get_tree().process_frame
	var scroll = history_text.get_v_scroll_bar()
	if scroll:
		scroll.value = scroll.max_value
