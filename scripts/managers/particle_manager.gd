# particle_manager.gd
extends Node

# ================= 属性 =================
var _weather_layer: Node
var _active_particles: Dictionary = {}
var particle_database: Dictionary = {}


# ================= 初始化 =================
func _ready() -> void:
	_load_particle_database()


func _load_particle_database() -> void:
	var dir = DirAccess.open("res://assets/particles/tres")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with("_data.tres"):
				var resource = load("res://assets/particles/tres/" + file_name)
				if resource is ParticleEffectData and resource.effect_id != "":
					particle_database[resource.effect_id] = resource
			file_name = dir.get_next()
		dir.list_dir_end()
		print("[ParticleManager] 粒子数据库加载完成，共找到 %d 个效果。" % particle_database.size())
	else:
		print("[ParticleManager] 错误：无法打开 assets/particles 目录。")


# ================= 注册 =================
func register_weather_layer(node: Node) -> void:
	_weather_layer = node
	print("[ParticleManager] 天气层已注册。")


# ================= 播放与停止 =================
func play_effect(effect_id: String) -> void:
	if not _weather_layer:
		print("[ParticleManager] 错误：天气层未注册。")
		return
	if not particle_database.has(effect_id):
		print("[ParticleManager] 错误：未找到粒子效果ID '%s'。" % effect_id)
		return

	# 如果已经在播放，则停止旧实例
	if _active_particles.has(effect_id):
		stop_effect(effect_id)

	var effect_data: ParticleEffectData = particle_database[effect_id]
	var particle_node = effect_data.particle_scene.instantiate()
	_weather_layer.add_child(particle_node)
	_active_particles[effect_id] = particle_node
	print("[ParticleManager] 粒子效果 '%s' 已开始播放。" % effect_data.display_name)


func stop_effect(effect_id: String) -> void:
	if _active_particles.has(effect_id):
		var node = _active_particles[effect_id]
		if is_instance_valid(node):
			node.queue_free()
		_active_particles.erase(effect_id)
		print("[ParticleManager] 粒子效果 '%s' 已停止。" % effect_id)


func stop_all_effects() -> void:
	for effect_id in _active_particles.keys():
		var node = _active_particles[effect_id]
		if is_instance_valid(node):
			node.queue_free()
	_active_particles.clear()
	print("[ParticleManager] 所有粒子效果已停止。")


# ================= 存档辅助 =================
func get_active_effects() -> Array:
	var effects: Array = []
	for effect_id in _active_particles.keys():
		if is_instance_valid(_active_particles[effect_id]):
			effects.append(effect_id)
	return effects
