## Стадия продажи: превращает итог заезда в деньги и закрывает день.
extends Control

@onready var _info_label: Label = $VBoxContainer/InfoLabel
@onready var _next_day_button: Button = $VBoxContainer/NextDayButton


func _ready() -> void:
	_next_day_button.pressed.connect(_on_next_day_pressed)
	_sell_cargo()


## Выручка считается по долям доехавшей ценности, а не по числу ящиков:
## ваза без одного донца стоит дешевле целой, но дороже нуля. Поверх этого
## ложится коэффициент за скорость: за долгую доставку платят меньше.
func _sell_cargo() -> void:
	# get() со значением по умолчанию — на случай, если стадию открыли
	# в обход перевозки (например, запустив сцену напрямую из редактора).
	var items: Array = GameState.run_result.get("items", [])
	var revenue := 0
	for entry: Dictionary in items:
		var data := ItemCatalog.get_by_id(entry.get("id", &""))
		if data == null:
			continue
		var ratio: float = entry.get("ratio", 0.0)
		revenue += int(round(float(data.base_price) * ratio))

	var payout: float = GameState.run_result.get("payout_factor", 1.0)
	var full_revenue := revenue
	revenue = int(round(float(revenue) * payout))
	GameState.earn_money(revenue)

	# Про потерю на опоздании говорим прямо: без этой строки игрок увидит
	# только меньшее число и не поймёт, за что.
	var late_note := ""
	if payout < 1.0:
		late_note = "\nЗа опоздание: %d%% (было бы %d)" % [
			int(round(payout * 100.0)), full_revenue,
		]

	_info_label.text = "ПРОДАЖА — итог дня %d\nДоехало целыми: %d\nПовреждено: %d\nПотеряно: %d\nВ пути: %d с%s\nВыручка: %d\nВсего денег: %d\nНа складе: %d шт." % [
		GameState.get_day(),
		GameState.run_result.get("delivered", 0),
		GameState.run_result.get("damaged", 0),
		GameState.run_result.get("lost", 0),
		int(GameState.run_result.get("run_time", 0.0)),
		late_note,
		revenue,
		GameState.get_money(),
		GameState.cargo_actual.size(),
	]


func _on_next_day_pressed() -> void:
	GameState.advance_day()
	StageManager.instance.change_stage(StageManager.Stage.SHOP)
