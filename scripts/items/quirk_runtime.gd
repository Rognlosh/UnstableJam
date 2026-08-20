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

var item: BreakableItem = null
var quirk: ItemQuirk = null
## Сила свойства на этом теле: 1.0 у целой вещи, piece_strength у осколка.
## Считается один раз при подключении, чтобы каждое свойство не выясняло
## заново, кто оно такое.
var strength: float = 1.0


func attach(target: BreakableItem, source: ItemQuirk) -> void:
	item = target
	quirk = source
	strength = 1.0 if target.level == 0 else source.piece_strength
	_setup()


func _setup() -> void:
	pass


func physics_step(_state: PhysicsDirectBodyState2D) -> void:
	pass


## at — где вещь была в момент разрушения. Отдельным параметром, потому что
## тело уже помечено на удаление и полагаться на его трансформ не стоит.
func on_break(_impact: float, _at: Vector2) -> void:
	pass
