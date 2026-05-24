# audio_data.gd
class_name AudioData
extends Resource

enum AudioType { BGM, SFX, VOICE }

## 音频唯一标识符
@export var audio_id: String = ""

## 展示名
@export var display_name: String = ""

## 音频类型
@export var audio_type: AudioType = AudioType.SFX

## 音频资源
@export var stream: AudioStream

## 音量
@export var default_volume_db: float = 0.0
