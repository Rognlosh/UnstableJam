class_name UpgradeLot
extends PanelContainer

## Строка без силуэта: название, пояснение, кнопка. Обслуживает и прокачку,
## и ящик от наставника — у обоих ровно этот набор полей, а силуэта нет
## ни у лавки, ни у набора из четырёх разных вещей.
##
## Про деньги и про то, что означает нажатие, строка не знает: она сообщает
## наверх, что кнопку нажали, а решение принимает стадия закупа. Та же
## граница, что у ShopLot, и ради того же — витрина остаётся отображением.

signal activated

@export var name_label: Label
@export var hint_label: Label
@export var action_button: Button

var _title: String = ""
var _hint: String = ""
var _action: String = ""
var _enabled: bool = true


## Содержимое строки. Готовый текст, а не ключ: у прокачки и у подачки
## ключи лежат в разных ресурсах, и разбираться в этом строке незачем.
func setup(title: String, hint: String) -> void:
	_title = title
	_hint = hint
	if is_node_ready():
		_refresh()


## Подпись и доступность кнопки. Отдельным вызовом от setup(): название
## строки за время закупа не меняется, а кнопка меняется на каждую монету.
func set_action(text: String, enabled: bool) -> void:
	_action = text
	_enabled = enabled
	if is_node_ready():
		_refresh()


func _ready() -> void:
	action_button.pressed.connect(_on_action_pressed)
	_refresh()


func _on_action_pressed() -> void:
	activated.emit()


func _refresh() -> void:
	name_label.text = _title
	if hint_label != null:
		hint_label.text = _hint
		# Пустое пояснение прячем целиком, иначе под строкой болтается
		# пустая полоса высотой в строку текста.
		hint_label.visible = not _hint.is_empty()
	action_button.text = _action
	action_button.disabled = not _enabled
