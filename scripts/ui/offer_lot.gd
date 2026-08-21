class_name OfferLot
extends PanelContainer

## Строка-предложение: название, пояснение, одна кнопка. Обслуживает и прокачку
## в лавке наставника, и бесплатный ящик на витрине товара.
##
## Решение о том, доступно предложение или нет, строка не принимает — ей его
## сообщают. Это отличает её от ShopLot, которая сама сверяет цену с деньгами:
## у прокачек и подачки условия разные (купленное однократно, нищета, место
## на полке), и тащить их все внутрь строки значило бы дублировать здесь
## правила закупа.

signal action_pressed

@export var name_label: Label
@export var hint_label: Label
@export var action_button: Button


func _ready() -> void:
	action_button.pressed.connect(func() -> void: action_pressed.emit())


## Постоянная часть строки. Тексты приходят уже переведёнными: строка не знает,
## пришли они из ItemData, UpgradeData или HandoutData.
func setup(title: String, hint: String) -> void:
	name_label.text = title
	hint_label.text = hint
	# Пустое пояснение прячем целиком, иначе под строкой болтается
	# пустая полоса высотой в строку текста.
	hint_label.visible = not hint.is_empty()


## Меняющаяся часть: что написано на кнопке и нажимается ли она.
## Причина недоступности пишется прямо на кнопке — серая кнопка без
## объяснения читается как поломка.
func set_action(text: String, enabled: bool) -> void:
	action_button.text = text
	action_button.disabled = not enabled
