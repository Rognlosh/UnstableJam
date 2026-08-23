extends Node

## Единственная точка, через которую предметы рождаются и разрушаются.
## Здесь же живёт бюджет осколков — страховка от просадки FPS в браузере.

signal item_broken(item_id: StringName, instance_id: int, impact: float)
signal item_pulverized(item_id: StringName, instance_id: int)

## Потолок живых осколков в сцене. Если куски не влезают в бюджет,
## предмет уходит сразу в крошку, а не плодит тела.
const MAX_FRAGMENTS: int = 64
## Разлёт кусков в стороны при разбитии, px/s.
const PIECE_KICK: float = 90.0

const ITEM_SCENE: PackedScene = preload("res://scenes/items/breakable_item.tscn")

var _next_id: int = 0


func spawn_item(item_data: ItemData, parent: Node2D, at: Vector2) -> BreakableItem:
	var item := ITEM_SCENE.instantiate() as BreakableItem
	item.setup_whole(item_data, take_instance_id())
	# Позицию задаём ДО add_child: двигать физическое тело после входа
	# в дерево — плохая привычка, физика этого не любит.
	item.transform = _local_transform(parent, Transform2D(0.0, at))
	parent.add_child(item)
	return item


## Рождение одинокого осколка — того, что пережил прошлый заезд и лежал
## на складе. Разбиение тут ни при чём: кусок появляется сам по себе.
func spawn_piece(
	item_data: ItemData, piece: ItemPieceData, parent: Node2D, at: Vector2
) -> BreakableItem:
	var item := ITEM_SCENE.instantiate() as BreakableItem
	item.setup_piece(item_data, take_instance_id(), piece)
	item.transform = _local_transform(parent, Transform2D(0.0, at))
	parent.add_child(item)
	return item


func break_item(item: BreakableItem, impact: float) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return

	var item_data: ItemData = item.data
	var parent := item.get_parent() as Node2D
	var xform := item.global_transform
	var velocity := item.linear_velocity
	var spin := item.angular_velocity
	var instance_id := item.instance_id
	var was_piece := item.level > 0

	# Звук берётся здесь, а не подпиской на сигналы: сигнал item_broken несёт
	# только идентификатор, и слушателю пришлось бы лезть в каталог за тем,
	# что тут уже лежит под рукой. Заодно озвучивается и ветка перерасхода
	# бюджета, где сигнал item_broken не испускается вовсе.
	if was_piece:
		# Осколок не бьётся заново, он рассыпается — звук тише и глуше.
		Audio.play(&"dust", -4.0)
	else:
		Audio.play(StringName("break_" + item_data.sound_material))
	_spawn_dust(parent, xform.origin, item_data.color)
	item.queue_free()

	var over_budget := live_fragment_count() + item_data.pieces.size() > MAX_FRAGMENTS
	if was_piece or item_data.pieces.is_empty() or over_budget:
		item.notify_broken(impact, xform.origin)
		item_pulverized.emit(item_data.id, instance_id)
		return

	for piece: ItemPieceData in item_data.pieces:
		var fragment := ITEM_SCENE.instantiate() as BreakableItem
		fragment.setup_piece(item_data, instance_id, piece)
		var target := xform.translated_local(fragment.rest_offset)
		fragment.transform = _local_transform(parent, target)
		var arm := target.origin - xform.origin
		# Скорость вращения целого предмета превращается в линейную у куска:
		# перпендикуляр к плечу, умноженный на угловую скорость.
		fragment.linear_velocity = velocity \
			+ Vector2(-arm.y, arm.x) * spin \
			+ arm.normalized() * PIECE_KICK
		fragment.angular_velocity = spin + randf_range(-2.5, 2.5)
		parent.add_child(fragment)

	# Хук зовётся после рождения кусков — иначе будущий взрыв не задел бы
	# собственные осколки, а это половина его эффекта.
	item.notify_broken(impact, xform.origin)
	item_broken.emit(item_data.id, instance_id, impact)


func live_fragment_count() -> int:
	return get_tree().get_nodes_in_group(&"fragments").size()


## Публичный намеренно: осколки, родившиеся при одном разбитии, делят номер
## родителя, и стадии перевозки нужно уметь развести их по собственным
## номерам, когда они становятся самостоятельным грузом.
func take_instance_id() -> int:
	_next_id += 1
	return _next_id


func _local_transform(parent: Node2D, global_target: Transform2D) -> Transform2D:
	if parent == null:
		return global_target
	return parent.get_global_transform().affine_inverse() * global_target


func _spawn_dust(parent: Node2D, at: Vector2, color: Color) -> void:
	if parent == null:
		return
	# CPUParticles2D, а не GPU: гарантированно работает в Compatibility/WebGL 2
	# и не требует отдельного материала.
	var dust := CPUParticles2D.new()
	dust.emitting = false
	dust.one_shot = true
	dust.amount = 14
	dust.lifetime = 0.5
	dust.explosiveness = 1.0
	dust.direction = Vector2.UP
	dust.spread = 180.0
	dust.initial_velocity_min = 40.0
	dust.initial_velocity_max = 170.0
	dust.gravity = Vector2(0.0, 500.0)
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.5
	dust.color = color
	parent.add_child(dust)
	dust.global_position = at
	dust.emitting = true
	get_tree().create_timer(dust.lifetime + 0.3).timeout.connect(dust.queue_free)
