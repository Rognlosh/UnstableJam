## Стадия закупа — ЗАГЛУШКА этапа 0.
## Настоящий экран лотов появится на этапе 2. Сейчас задача одна:
## доказать, что петля крутится, деньги списываются, груз копится.
extends Control

## Цена условного товара-заглушки.
const DUMMY_ITEM_COST: int = 20

@onready var _info_label: Label = $VBoxContainer/InfoLabel
@onready var _buy_button: Button = $VBoxContainer/BuyButton
@onready var _go_button: Button = $VBoxContainer/GoButton


func _ready() -> void:
	# Подключаем сигналы кодом, а не в редакторе: так связь видно
	# прямо в скрипте, и она не теряется при пересборке сцены.
	_buy_button.pressed.connect(_on_buy_pressed)
	_go_button.pressed.connect(_on_go_pressed)
	# Перерисовываем текст при любом изменении денег.
	GameState.money_changed.connect(_on_money_changed)
	_refresh()


## Сигнал money_changed отдаёт новое значение, но нам проще
## перечитать состояние целиком — параметр не используем.
func _on_money_changed(_new_amount: int) -> void:
	_refresh()


## Обновление текста и доступности кнопок.
func _refresh() -> void:
	_info_label.text = "ЗАКУП\nДень: %d\nДеньги: %d\nВ кузове: %d шт." % [
		GameState.get_day(),
		GameState.get_money(),
		GameState.cargo_actual.size(),
	]
	# Кнопка гаснет, когда денег не хватает — вместо молчаливого отказа.
	_buy_button.disabled = not GameState.can_afford(DUMMY_ITEM_COST)


func _on_buy_pressed() -> void:
	if GameState.spend_money(DUMMY_ITEM_COST):
		GameState.cargo_actual.append("Ваза-заглушка")
		_refresh()


func _on_go_pressed() -> void:
	StageManager.instance.change_stage(StageManager.Stage.DRIVE)
