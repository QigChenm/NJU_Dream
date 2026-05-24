# character_data.gd
class_name CharacterData
extends Resource

## 角色唯一标识符 (例如: "sister", "friend_a")。
@export var character_id: String = ""

## 在对话框中显示的角色名。
@export var display_name: String = ""

## 对话中名字的颜色。
@export var name_color: Color = Color.WHITE

## 默认好感度。
@export var default_affection: int = 0

## 表情资源字典，键为表情名 (String)，值为表情图片 (Texture2D)。
@export var expressions: Dictionary = {}

## 角色动态动作
@export var action_animations: Dictionary = {}

## 角色显示头像
@export var portrait: Texture2D

## 可选，配音演员名字或信息。
@export var voice_actor: String = ""

## 可选，角色背景故事或简介。
@export_multiline var description: String = ""
