# pad_triangle.gd
extends Control

var pad_pleasure: float = 0.0
var pad_arousal: float = 0.0
var pad_dominance: float = 0.0

# 顶点位置（对应截图：P顶部，A右下，D左下）
const P_POS = Vector2(0.5, 0.1)   # 顶部：愉悦(P)
const A_POS = Vector2(0.9, 0.9)   # 右下：激活(A)
const D_POS = Vector2(0.1, 0.9)   # 左下：支配(D)

# 视觉参数（白色背景高对比度）
const GRID_LAYERS: int = 4        # 同心网格层数
const GRID_COLOR: Color = Color(0.3, 0.3, 0.3, 0.4)  # 深灰网格线
const FILL_COLOR: Color = Color(0.2, 0.4, 0.8, 0.25) # 天蓝色填充
const BORDER_COLOR: Color = Color(0.2, 0.2, 0.2, 1.0)# 深灰外边框
const POINT_COLOR: Color = Color(0.1, 0.3, 0.7, 1.0) # 深蓝色状态点
const POINT_SIZE: float = 9.0     # 状态点大小

var current_time_label: Label     # 引用你已有的时间标签
var current_point: Vector2 = Vector2.ZERO
var center: Vector2 = Vector2.ZERO

func _ready():
	set_process(true)
	
	# 获取你已有的时间标签
	current_time_label = get_node_or_null("../CurrentTime")
	if not current_time_label:
		print("未找到CurrentTime节点，请检查路径")

func update_pad(p: float, a: float, d: float):
	pad_pleasure = clamp(p, -1.0, 1.0)
	pad_arousal  = clamp(a, -1.0, 1.0)
	pad_dominance= clamp(d, -1.0, 1.0)
	queue_redraw()

func _process(delta):
	# 每秒更新一次时间
	if current_time_label:
		var current_seconds = Time.get_ticks_msec() / 1000
		var previous_seconds = (Time.get_ticks_msec() - delta * 1000) / 1000
		
		if int(current_seconds) != int(previous_seconds):
			var now = Time.get_datetime_dict_from_system(true)
			current_time_label.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]

func _draw():
	var size = get_size()
	if size.x <= 0 or size.y <= 0: return

	# 计算实际像素坐标
	var vp = Vector2(P_POS.x * size.x, P_POS.y * size.y)
	var va = Vector2(A_POS.x * size.x, A_POS.y * size.y)
	var vd = Vector2(D_POS.x * size.x, D_POS.y * size.y)
	center = (vp + va + vd) / 3.0

	# 1. 绘制多层同心三角形网格
	for i in range(1, GRID_LAYERS + 1):
		var t = i / (GRID_LAYERS + 1.0)
		var p_layer = center.lerp(vp, t)
		var a_layer = center.lerp(va, t)
		var d_layer = center.lerp(vd, t)
		
		draw_line(p_layer, a_layer, GRID_COLOR, 1.0)
		draw_line(a_layer, d_layer, GRID_COLOR, 1.0)
		draw_line(d_layer, p_layer, GRID_COLOR, 1.0)

	# 2. 绘制最外层三角形边框
	draw_line(vp, va, BORDER_COLOR, 2.0)
	draw_line(va, vd, BORDER_COLOR, 2.0)
	draw_line(vd, vp, BORDER_COLOR, 2.0)

	# 3. 计算当前状态点
	var p_norm = (pad_pleasure + 1.0) / 2.0
	var a_norm = (pad_arousal + 1.0) / 2.0
	var d_norm = (pad_dominance + 1.0) / 2.0
	var total = p_norm + a_norm + d_norm
	if total == 0: total = 1.0
	current_point = (vp * p_norm + va * a_norm + vd * d_norm) / total

	# 4. 绘制填充区域
	var angle_to_point = (current_point - center).angle()
	var angle_offset = deg_to_rad(15)
	var radius = current_point.distance_to(center) * 1.5 # 初始放大1.5倍
	
	var p1 = center + Vector2.RIGHT.rotated(angle_to_point - angle_offset) * radius
	var p2 = center + Vector2.RIGHT.rotated(angle_to_point + angle_offset) * radius
	
	var fill_points = PackedVector2Array([center, p1, current_point, p2])
	var fill_colors = PackedColorArray([FILL_COLOR, FILL_COLOR, FILL_COLOR, FILL_COLOR])
	draw_polygon(fill_points, fill_colors)

	# 5. 绘制填充区域边框
	draw_line(center, p1, BORDER_COLOR, 1.0)
	draw_line(p1, current_point, BORDER_COLOR, 1.0)
	draw_line(current_point, p2, BORDER_COLOR, 1.0)
	draw_line(p2, center, BORDER_COLOR, 1.0)

	# 6. 绘制顶点标签
	var font = ThemeDB.fallback_font
	var font_size = 24
	draw_string(font, vp + Vector2(-15, -20), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.1, 0.1, 0.1))
	draw_string(font, va + Vector2(20, 5), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.1, 0.1))
	draw_string(font, vd + Vector2(-40, 5), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.1, 0.1))

	# 7. 绘制状态点（蓝色小三角形）
	var point_angle = (center - current_point).angle()
	var triangle_points = PackedVector2Array([
		current_point + Vector2.RIGHT.rotated(point_angle) * POINT_SIZE,
		current_point + Vector2.RIGHT.rotated(point_angle + deg_to_rad(120)) * POINT_SIZE * 0.6,
		current_point + Vector2.RIGHT.rotated(point_angle - deg_to_rad(120)) * POINT_SIZE * 0.6
	])
	var point_colors = PackedColorArray([POINT_COLOR, POINT_COLOR, POINT_COLOR])
	draw_polygon(triangle_points, point_colors)
