# gallery_ui.gd
extends CanvasLayer

# ================= 属性 =================
@export var custom_font: Font

@onready var tab_bar: TabBar = $Panel/VBoxContainer/TabBar
@onready var cg_page: Control = $Panel/VBoxContainer/CGPage
@onready var music_page: Control = $Panel/VBoxContainer/MusicPage
@onready var cg_grid: GridContainer = $Panel/VBoxContainer/CGPage/CGGrid
@onready var music_list: ItemList = $Panel/VBoxContainer/MusicPage/VBoxContainer/MusicList
@onready var play_btn: Button = $Panel/VBoxContainer/MusicPage/VBoxContainer/MusicControls/PlayBtn
@onready var stop_btn: Button = $Panel/VBoxContainer/MusicPage/VBoxContainer/MusicControls/StopBtn
@onready var now_playing: Label = $Panel/VBoxContainer/MusicPage/VBoxContainer/MusicControls/NowPlaying
@onready var preview_player: AudioStreamPlayer = $PreviewPlayer

var _cg_preview_popup: Popup = null


# ================= 初始化 =================
func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_init_preview_player()
	_apply_fonts()
	_connect_signals()
	_refresh_content()


# ================= 内部方法 =================
func _init_preview_player() -> void:
	if not preview_player:
		preview_player = AudioStreamPlayer.new()
		preview_player.name = "PreviewPlayer"
		preview_player.bus = "Music"
		preview_player.process_mode = PROCESS_MODE_ALWAYS
		add_child(preview_player)
	else:
		preview_player.bus = "Music"
		preview_player.process_mode = PROCESS_MODE_ALWAYS


func _apply_fonts() -> void:
	var title_label = $Panel/VBoxContainer/TitleLabel
	if custom_font:
		if title_label:
			title_label.add_theme_font_override("font", custom_font)
			title_label.add_theme_font_size_override("font_size", 32)
		if play_btn:
			play_btn.add_theme_font_override("font", custom_font)
			play_btn.add_theme_font_size_override("font_size", 26)
		if stop_btn:
			stop_btn.add_theme_font_override("font", custom_font)
			stop_btn.add_theme_font_size_override("font_size", 26)
		if now_playing:
			now_playing.add_theme_font_override("font", custom_font)
			now_playing.add_theme_font_size_override("font_size", 22)
		if music_list:
			music_list.add_theme_font_override("font", custom_font)
			music_list.add_theme_font_size_override("font_size", 32)
			music_list.add_theme_constant_override("line_separation", 20)
	else:
		if title_label:
			title_label.add_theme_font_size_override("font_size", 32)
		if play_btn:
			play_btn.add_theme_font_size_override("font_size", 26)
		if stop_btn:
			stop_btn.add_theme_font_size_override("font_size", 26)
		if now_playing:
			now_playing.add_theme_font_size_override("font_size", 22)
		if music_list:
			music_list.add_theme_font_size_override("font_size", 32)
			music_list.add_theme_constant_override("line_separation", 20)


func _connect_signals() -> void:
	tab_bar.tab_changed.connect(_on_tab_changed)
	play_btn.pressed.connect(_on_play_pressed)
	stop_btn.pressed.connect(_on_stop_pressed)
	music_list.item_activated.connect(_on_music_item_activated)
	GameManager.cg_unlocked.connect(_on_cg_unlocked)
	GameManager.bgm_unlocked.connect(_on_bgm_unlocked)
	UIManager.panel_opened.connect(_on_gallery_opened)
	UIManager.panel_closed.connect(_on_gallery_closed)


func _refresh_content() -> void:
	_refresh_cg_page()
	_refresh_music_page()
	if AudioManager:
		print("[GalleryUI] 音频数据库大小：%d" % AudioManager.audio_database.size())


func _on_tab_changed(tab: int) -> void:
	cg_page.visible = (tab == 0)
	music_page.visible = (tab == 1)


# ================= CG 鉴赏 =================
func _refresh_cg_page() -> void:
	for child in cg_grid.get_children():
		child.queue_free()
	if not CGManager:
		return

	for cg_id in CGManager.cg_database.keys():
		var data: CGData = CGManager.cg_database[cg_id]
		var is_unlocked = GameManager.is_cg_unlocked(cg_id)
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(280, 180)
		btn.disabled = not is_unlocked

		if is_unlocked:
			btn.icon = data.texture
			btn.expand_icon = true
			btn.pressed.connect(_on_cg_clicked.bind(cg_id))
		else:
			btn.text = "???\n（未解锁）"
			if custom_font:
				btn.add_theme_font_override("font", custom_font)
			btn.add_theme_font_size_override("font_size", 24)
		cg_grid.add_child(btn)


func _on_cg_clicked(cg_id: String) -> void:
	if not _cg_preview_popup:
		_cg_preview_popup = Popup.new()
		_cg_preview_popup.process_mode = PROCESS_MODE_ALWAYS
		var img = TextureRect.new()
		img.name = "PreviewImage"
		img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.gui_input.connect(_on_preview_clicked)
		_cg_preview_popup.add_child(img)
		add_child(_cg_preview_popup)

	var img = _cg_preview_popup.get_node("PreviewImage")
	img.texture = CGManager.cg_database[cg_id].texture
	_cg_preview_popup.popup_centered(Vector2(1100, 700))


func _on_preview_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_cg_preview_popup.hide()


# ================= 音乐鉴赏 =================
func _refresh_music_page() -> void:
	music_list.clear()
	if not AudioManager:
		return

	for audio_id in AudioManager.audio_database.keys():
		var data: AudioData = AudioManager.audio_database[audio_id]
		if data.audio_type != AudioData.AudioType.BGM:
			continue
		var is_unlocked = GameManager.is_bgm_unlocked(audio_id)
		var display_name = audio_id
		if "display_name" in data and data.display_name != "":
			display_name = data.display_name
		var idx = music_list.add_item(display_name)
		music_list.set_item_metadata(idx, audio_id)
		music_list.set_item_disabled(idx, not is_unlocked)


func _play_selected_music() -> void:
	var selected = music_list.get_selected_items()
	if selected.is_empty():
		return
	var idx = selected[0]
	var audio_id = music_list.get_item_metadata(idx)
	if not GameManager.is_bgm_unlocked(audio_id):
		now_playing.text = "曲目未解锁"
		return
	if not AudioManager or not AudioManager.audio_database.has(audio_id):
		now_playing.text = "无法播放：音频数据不存在"
		return
	var audio_data: AudioData = AudioManager.audio_database[audio_id]
	if audio_data.stream:
		preview_player.stream = audio_data.stream
		preview_player.play()
		now_playing.text = "正在播放：%s" % music_list.get_item_text(idx)
	else:
		now_playing.text = "无法播放：缺少音频文件"


func _on_play_pressed() -> void:
	_play_selected_music()


func _on_music_item_activated(_idx: int) -> void:
	_play_selected_music()


func _on_stop_pressed() -> void:
	preview_player.stop()
	now_playing.text = "已停止"


# ================= 背景音乐暂停/恢复 =================
func _on_gallery_opened(panel_name: String) -> void:
	if panel_name != "GalleryUI":
		return
	if AudioManager:
		var bgm_player = AudioManager.get_bgm_player()
		if bgm_player and bgm_player.playing:
			bgm_player.stream_paused = true


func _on_gallery_closed(panel_name: String) -> void:
	if panel_name != "GalleryUI":
		return
	preview_player.stop()
	now_playing.text = ""
	if AudioManager:
		var bgm_player = AudioManager.get_bgm_player()
		if bgm_player and bgm_player.stream_paused:
			bgm_player.stream_paused = false


# ================= 解锁刷新 =================
func _on_cg_unlocked(_cg_id: String) -> void:
	_refresh_cg_page()


func _on_bgm_unlocked(_bgm_id: String) -> void:
	_refresh_music_page()
