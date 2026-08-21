class_name ExplosionQuirk
extends ItemQuirk

## Взрыв при разбитии: вещь напоследок расталкивает всё вокруг.
##
## Волна ничего не ломает напрямую — только толкает. Разбиваются соседи сами,
## обычным детектором удара: резкий скачок скорости он и так читает как удар.
## Отсюда правильная зависимость от расстановки — ваза вплотную разлетается,
## ларец на другом конце кузова кувыркается, — и каскад получается даром,
## вместе с уже работающим бюджетом осколков.
##
## Сила задана в скорости, а не в импульсе: так её можно прямо сравнивать
## с break_speed предметов и понимать, кого волна убивает, а кого нет.

## Радиус поражения. За ним не толкает вовсе.
@export var radius: float = 240.0
## Прибавка к скорости в эпицентре, px/с. У вазы порог разбития 420,
## у ларца 850 — отсюда и видно, кто переживёт взрыв вплотную.
@export var kick_speed: float = 560.0
## Закрутка соседей, рад/с. Разброс случайный в обе стороны.
@export var spin_kick: float = 6.0

## Доля волны, достающаяся грузовику. Единица швырнула бы машину со скоростью
## вазы; здесь нужен ощутимый толчок, а не катапульта.
@export_range(0.0, 1.0, 0.01) var vehicle_factor: float = 0.12

## Потолок числа задетых тел. Страховка от кадра, в котором взрыв случился
## посреди плотной кучи осколков.
@export_range(4, 64) var max_targets: int = 32


func create_runtime() -> RefCounted:
	return Runtime.new()


class Runtime extends QuirkRuntime:

	func on_break(_impact: float, at: Vector2) -> void:
		var cfg := quirk as ExplosionQuirk
		if cfg == null or strength <= 0.0:
			return
		var reach := cfg.radius * strength
		if reach <= 1.0:
			return

		var world := item.get_world_2d()
		if world == null:
			return

		var shape := CircleShape2D.new()
		shape.radius = reach
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, at)
		query.collide_with_bodies = true

		for hit: Dictionary in world.direct_space_state.intersect_shape(
			query, cfg.max_targets
		):
			_push(hit.get("collider"), at, reach, cfg)

	## Толкаем только груз и машину. Галька под колёсами — тоже RigidBody2D,
	## но взрыв, разметающий насыпь, читался бы как баг физики, а не как
	## событие про товар.
	func _push(collider: Object, at: Vector2, reach: float, cfg: ExplosionQuirk) -> void:
		var body := collider as RigidBody2D
		if body == null or body == item:
			return
		var is_cargo := body.is_in_group(&"cargo")
		# Часть грузовика узнаём по типу родителя, а не по имени узла:
		# сцену можно переименовывать, свойство от этого не сломается.
		var is_vehicle := body.get_parent() is Truck
		if not is_cargo and not is_vehicle:
			return

		var offset := body.global_position - at
		var distance := offset.length()
		if distance > reach:
			return
		var falloff := 1.0 - distance / reach

		# Тело точно в эпицентре получает случайное направление: нормализовать
		# нулевой вектор нельзя, а бросить такую вещь без толчка — обидно.
		var direction := offset / distance if distance > 1.0 \
			else Vector2.UP.rotated(randf() * TAU)

		var speed := cfg.kick_speed * falloff * strength
		if is_vehicle:
			speed *= cfg.vehicle_factor
		# Меняем скорость, а не прикладываем импульс: детектор удара у соседа
		# сравнивает скорость по кадрам и сам решит, пережил он это или нет.
		body.linear_velocity += direction * speed
		body.angular_velocity += randf_range(-1.0, 1.0) * cfg.spin_kick \
			* falloff * strength
