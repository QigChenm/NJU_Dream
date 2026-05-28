# tip_ui.gd
extends CanvasLayer

signal confirmed
signal canceled
signal closed

@onready var message_label: RichTextLabel = $TipRect/Message
@onready var confirm_btn: TextureButton = $TipRect/ConfirmBtn
@onready var cancel_btn: TextureButton = $TipRect/CancelBtn
@onready var close_btn: TextureButton = $TipRect/CloseBtn
@onready var confirm_txt: Label = $TipRect/ConfirmBtn/Label
@onready var cancel_txt: Label = $TipRect/CancelBtn/Label

var _current_cancel_callback: Callable
var _current_close_callback: Callable

func _ready():
	visible = false
	process_mode = PROCESS_MODE_ALWAYS
	close_btn.visible = false
	confirm_btn.pressed.connect(func(): confirmed.emit())
	cancel_btn.pressed.connect(func(): canceled.emit())
	close_btn.pressed.connect(_on_close_pressed)


func show_tip(text: String, confirm_text: String, cancel_text: String,
			  confirm_callable: Callable, cancel_callable: Callable,
			  show_close: bool = false, close_callable: Callable = Callable()) -> void:
	message_label.text = text
	confirm_txt.text = confirm_text
	cancel_txt.text = cancel_text
	close_btn.visible = show_close
	_current_cancel_callback = cancel_callable
	_current_close_callback = close_callable

	_disconnect_all()

	confirm_btn.pressed.connect(func():
		confirm_callable.call()
		visible = false
		_current_cancel_callback = Callable()
		_current_close_callback = Callable()
		_disconnect_all()
	, CONNECT_ONE_SHOT)

	cancel_btn.pressed.connect(func():
		cancel_callable.call()
		visible = false
		_current_cancel_callback = Callable()
		_current_close_callback = Callable()
		_disconnect_all()
	, CONNECT_ONE_SHOT)

	visible = true


func _disconnect_all():
	for signal_name in ["pressed"]:
		for connection in confirm_btn.get_signal_connection_list(signal_name):
			connection["signal"].disconnect(connection["callable"])
		for connection in cancel_btn.get_signal_connection_list(signal_name):
			connection["signal"].disconnect(connection["callable"])

func _on_close_pressed():
	closed.emit()
	if _current_close_callback.is_valid():
		_current_close_callback.call()
		_current_close_callback = Callable()
	visible = false

func _emit_confirmed():
	confirmed.emit()

func _emit_canceled():
	canceled.emit()

func _emit_closed():
	closed.emit()

func hide_tip():
	visible = false
	_disconnect_all()
