class_name ItemQuirk
extends Resource

## Нестабильное свойство предмета: цифры баланса и подача в интерфейсе.
##
## Ресурс общий на все экземпляры товара — один .tres обслуживает все кубки
## в кузове сразу. Поэтому состояния (таймеров, фаз, счётчиков) здесь быть
## не может: две вещи затёрли бы друг другу счётчик. Состояние живёт
## в QuirkRuntime, по объекту на тело, а фабрикой служит create_runtime().

@export var id: StringName = &""

## Ключи локализации, а не готовый текст: строки живут в localization/ui.csv.
@export var name_key: String = ""
## Одна фраза для витрины: чем эта вещь опасна в дороге.
@export var hint_key: String = ""

## Оттенок, которым свойство метит вещь, пока нет рисованного арта.
@export var tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.05) var tint_amount: float = 0.0

## Во сколько раз слабее свойство работает на осколке. Ноль выключает его
## совсем. Что именно ослабляется, решает само свойство: левитация тянет
## гравитацию обратно к обычной, взрыв делит импульс.
@export_range(0.0, 1.0, 0.05) var piece_strength: float = 0.5


## Поведение для одного тела. Переопределяется наследниками.
##
## Возвращаемый тип — RefCounted, а не QuirkRuntime, намеренно: иначе
## описание свойства и его поведение ссылались бы друг на друга, а такой
## цикл движок не разрешает. Приведение делает вызывающая сторона.
func create_runtime() -> RefCounted:
	push_error("ItemQuirk: у свойства \"%s\" не задано поведение" % id)
	return null


func tinted(base: Color) -> Color:
	if tint_amount <= 0.0:
		return base
	return base.lerp(tint, tint_amount)


## Переведённые строки. tr() зовём здесь, а не в интерфейсе: так вызывающая
## сторона не обязана помнить, что в полях лежат ключи, а не текст.
func get_display_name() -> String:
	return tr(name_key) if not name_key.is_empty() else ""


func get_hint() -> String:
	return tr(hint_key) if not hint_key.is_empty() else ""
