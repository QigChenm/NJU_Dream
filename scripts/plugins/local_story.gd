# local_story.gd
extends Node

const EXTENDED_SCRIPT = [
	# ================= 序章：在图书馆里发现焦虑的你 =================
	{"type": "change_background", "background": "duxia"},
	{"type": "play_audio", "audio_id": "gentle"},
	{"type": "set_characters", "left": {"id": "xiu", "expression": "sad"}},
	{"type": "show_dialogue", "character": "xiu", "text": "（轻声）你还好吗？我看你在这里坐了好久，书都没翻几页……"},
	{"type": "show_dialogue", "character": "", "text": "你抬起头，发现小貅正关切地看着你。"},
	{"type": "set_expression", "character": "xiu", "expression": "default"},
	{"type": "show_dialogue", "character": "xiu", "text": "是不是最近压力太大了？[shake rate=10 level=3]别一个人扛着呀！[/shake]"},
	{"type": "show_choices", "choices": [{"id": 1, "text": "唉，确实有点累。"}, {"id": 2, "text": "没什么，我能应付。"}]},
	{"type": "add_affection", "character": "xiu", "delta": 5},
	{"type": "show_dialogue", "character": "xiu", "text": "我懂那种感觉。不过今天天气这么好，我们出去走走吧！"},
	{"type": "character_action", "character": "xiu", "action": "bounce"},
	{"type": "set_expression", "character": "xiu", "expression": "happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "[color=#FFB6C1]校园里的樱花开了，我带你去看！[/color]"},

	# ================= 第一幕：北大楼前的花雨与百年记忆 =================
	{"type": "change_background", "background": "beidalou"},
	{"type": "particle_play", "effect_id": "petal"},
	{"type": "show_dialogue", "character": "xiu", "text": "看，这就是北大楼！南京大学最标志性的建筑，建于1919年，已经有一百多年的历史了。"},
	{"type": "show_dialogue", "character": "xiu", "text": "它见证了无数先辈的求学岁月，也承载了南大人“诚朴雄伟、励学敦行”的精神。"},
	{"type": "show_dialogue", "character": "xiu", "text": "满墙的爬山虎四季变换，春天嫩绿，夏天浓荫，秋天火红，冬天静默。就像人的心境，总有起落。"},
	{"type": "long_dialogue", "text": "樱花如雪片般飘落，你们站在北大楼前的台阶上。小貅伸出手，接住一瓣花瓣，轻轻吹向空中。“每一片花瓣都带走一点烦恼，这是我自创的减压小仪式。”她说。远处传来钟楼的整点报时，浑厚的钟声在校园里回荡，仿佛在告诉你：无论过去多少年，这里的每一块砖石都在默默陪伴着每一个南大学子。"},
	{"type": "show_dialogue", "character": "xiu", "text": "怎么样，好点了吗？"},
	{"type": "show_choices", "choices": [{"id": 1, "text": "嗯，舒服多了。"}, {"id": 2, "text": "谢谢你，小貅。"}]},
	{"type": "add_affection", "character": "xiu", "delta": 10},
	{"type": "set_expression", "character": "xiu", "expression": "very_happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "那我们继续逛！我带你去大礼堂，今天有惊喜哦～"},
	{"type": "character_action", "character": "xiu", "action": "bounce"},

	# ================= 第二幕：大礼堂的音乐疗愈 =================
	{"type": "change_background", "background": "litang"},
	{"type": "play_audio", "audio_id": "love_piano"},
	{"type": "show_dialogue", "character": "xiu", "text": "大礼堂建于1930年，由著名建筑师杨廷宝设计，中西合璧的风格，特别典雅。"},
	{"type": "show_dialogue", "character": "xiu", "text": "今天我们运气真好，校乐团正在排练德彪西的《月光》！找个位置坐下来吧。"},
	{"type": "show_dialogue", "character": "", "text": "你们悄悄从后门进入，空旷的观众席只有寥寥几人。舞台上，钢琴手正在演奏。"},
	{"type": "long_dialogue", "text": "音符如水般流淌，在穹顶下回荡。你闭上眼睛，仿佛置身于一片宁静的湖泊，所有的焦虑、烦躁、不安，都随着音乐的涟漪慢慢消散。小貅安静地坐在你旁边，偶尔看看舞台，偶尔看看你。这一刻，你觉得整个世界都温柔了。"},
	{"type": "show_dialogue", "character": "xiu", "text": "（耳语）心理学上有个词叫“心流”。当我们完全沉浸在音乐中时，大脑会释放出多巴胺，让人感到幸福和满足。"},
	{"type": "character_action", "character": "xiu", "action": "shake"},
	{"type": "show_dialogue", "character": "xiu", "text": "[wave amp=50.0 freq=5.0]所以，不开心的时候就来找我吧，我带你听音乐！[/wave]"},
	{"type": "add_affection", "character": "xiu", "delta": 5},
	{"type": "set_expression", "character": "xiu", "expression": "happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "听完这一段，我们再去一个地方。走，去心理中心！"},

	# ================= 第三幕：心理中心的心灵加油站 =================
	{"type": "change_background", "background": "nansu"},
	{"type": "particle_stop", "effect_id": "petal"},
	{"type": "play_audio", "audio_id": "flowing"},
	{"type": "show_dialogue", "character": "xiu", "text": "我们学校的心理中心就在大学生活动中心三楼，环境特别温馨。"},
	{"type": "show_dialogue", "character": "xiu", "text": "这里有专业的心理咨询师，也有各种减压设备：放松椅、沙盘、情绪宣泄室……"},
	{"type": "show_dialogue", "character": "xiu", "text": "你看，墙上这些画都是来体验的同学画的“情绪曼陀罗”，每个人心里都有一朵独特的花。"},
#	{"type": "unlock_cg", "cg_id": "heroine_smile"},
#	{"type": "cg_play", "cg_id": "heroine_smile"},
	{"type": "show_dialogue", "character": "xiu", "text": "今天我给你预约了一次“正念冥想”体验，跟着老师的引导，把注意力集中在呼吸上。"},
	{"type": "long_dialogue", "text": "你坐在舒适的沙发上，耳边是轻柔的引导语，小貅在旁边安静地陪伴。你从未如此认真地感受过自己的呼吸，一呼一吸之间，仿佛将积压的疲惫和压力一点点呼出体外。十五分钟后，你睁开眼睛，窗外的阳光格外明亮。"},
	{"type": "add_affection", "character": "xiu", "delta": 10},
	{"type": "set_expression", "character": "xiu", "expression": "very_happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "感觉怎么样？是不是整个人都轻盈了？记住，关注自己的心理健康，是爱自己的第一步。"},
	{"type": "show_choices", "choices": [{"id": 1, "text": "真的很有效！"}, {"id": 2, "text": "谢谢你带我来这里。"}]},
	{"type": "add_affection", "character": "xiu", "delta": 5},
	{"type": "show_dialogue", "character": "xiu", "text": "那我们再去最后一个地方——操场！运动也是抗压的良药哦。"},

	# ================= 第四幕：操场的夜跑与汗水 =================
	{"type": "change_background", "background": "beidalou"},
	{"type": "play_audio", "audio_id": "spring_forest"},
	{"type": "show_dialogue", "character": "xiu", "text": "南大的操场到了晚上特别热闹，大家都来跑步、跳绳、打羽毛球，超级有活力！"},
	{"type": "show_dialogue", "character": "xiu", "text": "运动时大脑会分泌内啡肽，那是天然的快乐激素。来，我们慢跑两圈，感受一下身体的变化。"},
	{"type": "show_dialogue", "character": "", "text": "你们沿着跑道慢跑起来，晚风拂过脸颊，汗水带走了烦恼。跑完两圈，你双手撑着膝盖喘气，心里却说不出的畅快。"},
	{"type": "character_action", "character": "xiu", "action": "shake"},
	{"type": "show_dialogue", "character": "xiu", "text": "怎么样，是不是觉得心里的石头轻了一点？我每天都会来这里，以后我们一起！"},
	{"type": "add_affection", "character": "xiu", "delta": 5},
	{"type": "set_expression", "character": "xiu", "expression": "happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "天快黑了，最后带你回图书馆顶楼，那里是全校看星星最棒的地方。走吧～"},

	# ================= 第五幕：星空下的约定 =================
	{"type": "change_background", "background": "duxia_night"},
	{"type": "play_audio", "audio_id": "gentle"},
	{"type": "show_dialogue", "character": "", "text": "你们坐在图书馆顶楼的长椅上，夜风轻拂，头顶是稀疏的星光。小貅指着天空，教你看星座。"},
	{"type": "show_dialogue", "character": "xiu", "text": "你看，那颗最亮的星是木星，它周围其实有很多小卫星在环绕着它。我们每个人都不是孤独的，就像那些小卫星一样，总有温暖的力量在身边。"},
	{"type": "long_dialogue", "text": "小貅没有再说话，只是静静地陪着你。这一刻，你感到一种前所未有的安宁。那些压在心头的事情，似乎变得不再那么沉重。也许，正如她说的，生活原本就是有起有落，重要的是，你知道在哪里可以找到温暖的光。"},
	{"type": "add_affection", "character": "xiu", "delta": 15},
	{"type": "character_action", "character": "xiu", "action": "shake"},
	{"type": "show_dialogue", "character": "xiu", "text": "记住今天的感受吧。[color=#87CEEB]当你觉得累的时候，就想想北大楼的花香、礼堂的音乐、操场的汗水，还有——[/color]"},
	{"type": "set_expression", "character": "xiu", "expression": "very_happy"},
	{"type": "show_dialogue", "character": "xiu", "text": "[wave amp=50.0 freq=5.0]还有我呀！我可是你的专属校园向导兼心灵充电宝！[/wave]"},
	{"type": "show_dialogue", "character": "", "text": "你笑了，发自内心地。也许未来的路依然有挑战，但此刻，你觉得自己充满了勇气。"},
	{"type": "set_variable", "variable": "ending_type", "value": 2},
	{"type": "stop_audio", "audio_id": "flowing"},
	{"type": "show_dialogue", "character": "xiu", "text": "好啦，我们下去吧。今晚睡个好觉，明天又是崭新的一天！"},
	{"type": "set_ui_state", "element": "DialogueBox", "state": "hidden"},
	{"type": "end_scene"}
]

func execute_local_story() -> void:
	if not has_node("/root/ScriptEngine"):
		return
	print("[ExtendedLocalStory] 正在播放本地剧情...")
	ScriptEngine.execute_commands(EXTENDED_SCRIPT.duplicate(true))
