# cg_data.gd
class_name CGData
extends Resource

## CG唯一标识符 (e.g. "heroine_smile")。
@export var cg_id: String = ""

## CG的显示名称，可选。
@export var display_name: String = ""

## CG的纹理资源。
@export var texture: Texture2D

## 可选，与CG绑定的动画库。如果不为空，则会优先使用这个预制的动画。
@export var animation_lib: AnimationLibrary
