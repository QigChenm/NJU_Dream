# audio_manager.gd
extends Node

# ---------- 音频数据库 ----------
var audio_database: Dictionary = {}

# ---------- 播放器实例 ----------
var _bgm_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []

# ---------- BGM 交叉淡入淡出控制 ----------
var _bgm_tween: Tween
var current_bgm_id: String = ""

# ---------- 音频总线索引 ----------
var _bgm_bus_idx: int = -1
var _sfx_bus_idx: int = -1
var _voice_bus_idx: int = -1


# ================= 初始化 =================
func _ready() -> void:
	print("[AudioManager] 音频管理器初始化...")
	_init_buses()
	_create_pool()
	_load_database()


func _init_buses() -> void:
	_bgm_bus_idx = AudioServer.get_bus_index("BGM")
	_sfx_bus_idx = AudioServer.get_bus_index("SFX")
	_voice_bus_idx = AudioServer.get_bus_index("Voice")
	if _bgm_bus_idx == -1 or _sfx_bus_idx == -1 or _voice_bus_idx == -1:
		print("[AudioManager] 错误：音频总线未正确配置！请检查音频布局。")


func _create_pool() -> void:
	# BGM 播放器
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM"
	_bgm_player.process_mode = PROCESS_MODE_ALWAYS
	add_child(_bgm_player)

	# 语音播放器
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Voice"
	_voice_player.process_mode = PROCESS_MODE_ALWAYS
	add_child(_voice_player)

	# SFX 播放器池（16 个）
	for i in range(16):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		player.process_mode = PROCESS_MODE_ALWAYS
		add_child(player)
		_sfx_players.append(player)

	print("[AudioManager] 播放器池创建完毕（均设为 Always 模式）。")


func _load_database() -> void:
	var dir = DirAccess.open("res://assets/audio")
	if not dir:
		return
	_scan_audio_dir("res://assets/audio")


func _scan_audio_dir(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and not file_name.begins_with("."):
				_scan_audio_dir(dir_path + "/" + file_name)
			elif file_name.ends_with(".tres"):
				var res = load(dir_path + "/" + file_name)
				if res is AudioData and res.audio_id != "":
					audio_database[res.audio_id] = res
			file_name = dir.get_next()
		dir.list_dir_end()


# ================= 公共接口 =================
func play_audio(audio_id: String, crossfade_duration: float = 0.5) -> void:
	if not audio_database.has(audio_id):
		print("[AudioManager] 错误：音频ID '%s' 未找到。" % audio_id)
		return
	var data: AudioData = audio_database[audio_id]
	match data.audio_type:
		AudioData.AudioType.BGM:
			_play_bgm(data, crossfade_duration)
		AudioData.AudioType.SFX:
			_play_sfx(data)
		AudioData.AudioType.VOICE:
			_play_voice(data)


func stop_audio(audio_id: String, fade_out_duration: float = 0.3) -> void:
	if not audio_database.has(audio_id):
		print("[AudioManager] 警告：音频ID '%s' 未找到，停止当前BGM。" % audio_id)
		_stop_bgm(0.0)
		return
	var data: AudioData = audio_database[audio_id]
	match data.audio_type:
		AudioData.AudioType.BGM:
			_stop_bgm(fade_out_duration)
		AudioData.AudioType.SFX:
			_stop_sfx(data)
		AudioData.AudioType.VOICE:
			_stop_voice(fade_out_duration)


func stop_all() -> void:
	print("[AudioManager] 正在停止所有音频...")
	if _bgm_player and _bgm_player.playing:
		_stop_bgm(0.0)
	for sfx_player in _sfx_players:
		if sfx_player.playing:
			sfx_player.stop()
	if _voice_player and _voice_player.playing:
		_voice_player.stop()
	print("[AudioManager] 所有音频已停止。")


func set_bus_volume(bus_name: String, volume_db: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, volume_db)


func get_current_bgm_id() -> String:
	return current_bgm_id


func get_bgm_player() -> AudioStreamPlayer:
	return _bgm_player


# ================= BGM 内部实现 =================
func _play_bgm(data: AudioData, crossfade_duration: float) -> void:
	if _bgm_player.playing and _bgm_player.stream == data.stream:
		return
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm_player, "volume_db", -80.0, crossfade_duration / 2.0)
	_bgm_tween.tween_callback(_set_bgm_stream.bind(data))
	_bgm_tween.tween_property(_bgm_player, "volume_db", data.default_volume_db, crossfade_duration / 2.0)
	current_bgm_id = data.audio_id


func _set_bgm_stream(data: AudioData) -> void:
	_bgm_player.stream = data.stream
	_bgm_player.play()


func _stop_bgm(fade_out_duration: float) -> void:
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm_player, "volume_db", -80.0, fade_out_duration)
	_bgm_tween.tween_callback(_bgm_player.stop)
	current_bgm_id = ""


# ================= SFX 内部实现 =================
func _play_sfx(data: AudioData) -> void:
	for player in _sfx_players:
		if not player.playing:
			player.stream = data.stream
			player.volume_db = data.default_volume_db
			player.play()
			return
	# 池满，替换最早播放的
	_sfx_players[0].stream = data.stream
	_sfx_players[0].volume_db = data.default_volume_db
	_sfx_players[0].play()


func _stop_sfx(data: AudioData) -> void:
	for player in _sfx_players:
		if player.playing and player.stream == data.stream:
			player.stop()
			return


# ================= Voice 内部实现 =================
func _play_voice(data: AudioData) -> void:
	_voice_player.stream = data.stream
	_voice_player.volume_db = data.default_volume_db
	_voice_player.play()


func _stop_voice(fade_out_duration: float) -> void:
	var tween = create_tween()
	tween.tween_property(_voice_player, "volume_db", -80.0, fade_out_duration)
	tween.tween_callback(_voice_player.stop)
