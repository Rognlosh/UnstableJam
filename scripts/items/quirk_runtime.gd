class_name QuirkRuntime
extends RefCounted

## Поведение свойства на конкретном теле. Здесь и только здесь живёт
## состояние: фаза дрейфа, время до следующего прыжка, остаток утяжеления.
##
## Три точки входа, все уже есть в жизненном цикле предмета:
##   _setup()      — тело готово (BreakableItem._ready);
##   physics_step  — каждый физкадр, рядом с детектором удара;
##   on_break      — вещь разрушается, последний шанс что-то сделать.
## Наследник переопределяет только нужные ему: в GDScript нет ключевого
## слова override, достаточно объявить метод с тем же именем.
##
## Тело типизировано как RigidBody2D, а не BreakableItem: последнее замкнуло
## бы кольцо ссылок между предметом, его описанием и свойством. Всё, что
## свойству нужно сверх физики, приходит параметрами.

var item: RigidBody2D = null
var quirk: ItemQuirk = null
## Уровень тела: 0 — целая вещь, больше — осколок.
var level: int = 0
## Сила свойства на этом теле: 1.0 у целой вещи, piece_strength у осколка.
## Считается один раз при подключении, чтобы каждое свойство не выясняло
## заново, кто оно такое.
var strength: float = 1.0


func attach(target: RigidBody2D, source: ItemQuirk, piece_level: int) -> void:
	item = target
	quirk = source
	level = piece_level
	strength = 1.0 if piece_level == 0 else source.piece_strength
	if source.keeps_awake:
		target.can_sleep = false
	_setup()


func _setup() -> void:
	pass


func physics_step(_state: PhysicsDirectBodyState2D) -> void:
	pass


## at — где вещь была в момент разрушения. Отдельным параметром, потому что
## тело уже помечено на удаление и полагаться на его трансформ не стоит.
func on_break(_impact: float, _at: Vector2) -> void:
	pass
