# background_data.gd
class_name BackgroundData
extends Resource

## 背景唯一标识符 (例如: "classroom_day", "street_night")。
@export var background_id: String = ""

## 在脚本或UI中可选用的显示名称。
@export var display_name: String = ""

## 如果为空，则不显示场景提示条
@export var location_name: String = ""

## 场景名称字体（如果为空则使用默认字体）
@export var location_font: Font = null

## 场景名称字体大小
@export var location_font_size: int = 30

## 背景图片资源。
@export var texture: Texture2D

## 该背景默认的BGM资源。
@export var default_bgm: AudioStream
