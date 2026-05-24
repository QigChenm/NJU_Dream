# position_helper.gd
extends Node

## 自动调整立绘在舞台上的位置和大小
## @param sprite: CharacterDisplay 节点（继承自 TextureRect），如果为空或无纹理则直接返回
## @param position: "left" 或 "right"
static func adjust_sprite(sprite: TextureRect, position: String) -> void:
	if not sprite or not sprite.texture:
		return

	var tex_size: Vector2 = sprite.texture.get_size()
	if tex_size.y <= 0:
		return

	# 设定立绘显示高度（可根据游戏分辨率调整）
	const DISPLAY_HEIGHT := 600.0
	var scale_factor: float = DISPLAY_HEIGHT / tex_size.y
	var display_width: float = tex_size.x * scale_factor

	sprite.scale = Vector2(scale_factor, scale_factor)

	match position:
		"left":
			sprite.anchor_left = 0.0
			sprite.anchor_right = 0.0
			sprite.anchor_top = 1.0
			sprite.anchor_bottom = 1.0
			sprite.offset_left = 50
			sprite.offset_right = 50 + display_width
			sprite.offset_top = -DISPLAY_HEIGHT
			sprite.offset_bottom = 0
		"right":
			sprite.anchor_left = 1.0
			sprite.anchor_right = 1.0
			sprite.anchor_top = 1.0
			sprite.anchor_bottom = 1.0
			sprite.offset_left = -(display_width + 50)
			sprite.offset_right = -50
			sprite.offset_top = -DISPLAY_HEIGHT
			sprite.offset_bottom = 0
