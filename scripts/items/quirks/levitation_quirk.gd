class_name LevitationQuirk
extends ItemQuirk

## Левитация: вещь почти ничего не весит и медленно сносится в стороны.
##
## Сделано через gravity_scale, а не через постоянную силу вверх: сила,
## равная весу, держала бы предмет в невесомости ровно до первого удара,
## а масштаб гравитации честно меняет и падение, и отскок, и то, как вещь
## давит на соседей в стопке.

## Доля обычной гравитации у целой вещи. 0.15 — оседает как перо, но всё же
## оседает: при нуле она зависла бы над полкой и на полку бы не легла.
@export_range(-0.5, 1.0, 0.01) var gravity_scale: float = 0.15
## Сила бокового сноса. Среднее за период равно нулю, поэтому вещь
## болтается вокруг своего места, а не улетает в одну сторону.
@export var drift_force: float = 55.0
@export var drift_period: float = 2.4
## Сопротивление среды: без него подброшенная вещь долго ходит маятником.
@export var linear_damp: float = 0.7
@export var angular_damp: float = 1.5


func create_runtime() -> RefCounted:
	return Runtime.new()


## Вложенный класс — как nested class в C#. Держим поведение рядом с его
## настройками: искать их по двум файлам смысла нет.
class Runtime extends QuirkRuntime:
	var _time: float = 0.0
	## Сдвиг фазы: без него все парящие вещи в кузове качались бы
	## синхронно, как одно тело.
	var _phase: float = 0.0

	func _setup() -> void:
		var cfg := quirk as LevitationQuirk
		if cfg == null:
			return
		# Ослабление на осколке — это движение к обычной гравитации,
		# а не доля от 0.15: умножение сделало бы черепок ЛЕГЧЕ целой вещи.
		item.gravity_scale = lerpf(1.0, cfg.gravity_scale, strength)
		item.linear_damp = lerpf(0.0, cfg.linear_damp, strength)
		item.angular_damp = lerpf(0.0, cfg.angular_damp, strength)
		_phase = randf() * TAU

	func physics_step(state: PhysicsDirectBodyState2D) -> void:
		var cfg := quirk as LevitationQuirk
		if cfg == null or cfg.drift_period <= 0.0:
			return
		_time += state.step
		var speed := TAU / cfg.drift_period
		# Несоизмеримые частоты по осям — движение не замыкается в круг
		# и не читается как заводная игрушка.
		var force := Vector2(
			sin(_time * speed + _phase),
			cos(_time * speed * 0.63 + _phase * 1.7)
		) * cfg.drift_force * strength
		state.apply_central_force(force)
