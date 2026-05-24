# particle_effect_data.gd
class_name ParticleEffectData
extends Resource

## 粒子效果唯一标识符 (例如: "rain", "snow")。
@export var effect_id: String = ""

## 效果显示名称 (例如: "下雨", "下雪")。
@export var display_name: String = ""

## 粒子效果场景 (PackedScene)。这是你创建好的 .tscn 文件。
@export var particle_scene: PackedScene

## 可选，该效果是否循环播放 (通常都是 true)。
@export var is_looping: bool = true
