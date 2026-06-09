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
@onready var feedback_input: LineEdit = $TipRect/InputEdit

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
			  show_close: bool = false, close_callable: Callable = Callable()):
	feedback_input.visible = false
	feedback_input.text = ""
	message_label.visible = true
	close_btn.visible = show_close
	
	message_label.text = text
	confirm_txt.text = confirm_text
	cancel_txt.text = cancel_text
	
	_disconnect_all()
	
	confirm_btn.pressed.connect(func():
		confirm_callable.call()
		visible = false
		_disconnect_all()
	, CONNECT_ONE_SHOT)

	cancel_btn.pressed.connect(func():
		cancel_callable.call()
		visible = false
		_disconnect_all()
	, CONNECT_ONE_SHOT)
	
	if show_close and close_callable.is_valid():
		close_btn.pressed.connect(func():
			close_callable.call()
			visible = false
			_disconnect_all()
		, CONNECT_ONE_SHOT)
	
	visible = true

func show_feedback_tip(prompt_text: String, submit_callable: Callable, cancel_callable: Callable) -> void:
	message_label.visible = false
	feedback_input.visible = true
	feedback_input.text = ""
	close_btn.visible = false
	
	confirm_txt.text = "提交"
	cancel_txt.text = "取消"
	
	_disconnect_all()
	
	confirm_btn.pressed.connect(func():
		var text = feedback_input.text.strip_edges()
		if text != "" and submit_callable.is_valid():
			submit_callable.call(text)
	, CONNECT_ONE_SHOT)
	
	cancel_btn.pressed.connect(func():
		if cancel_callable.is_valid():
			cancel_callable.call()
	, CONNECT_ONE_SHOT)

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
