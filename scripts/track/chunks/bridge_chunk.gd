@tool
class_name BridgeChunk
extends TrackChunk

## Дощатый мост через пропасть. Единственный подвижный кусок в наборе:
## доски — это RigidBody2D, сшитые PinJoint2D в цепь и подвешенные
## к берегам, так что настил прогибается под грузовиком и раскачивается.
##
## Цепь нарочно чуть длиннее пролёта. Натянутая в струну не прогибается
## вовсе и ничем не отличается от обычной дороги, а слишком слабая провисает
## так глубоко, что на выезде машина упирается в берег как в стену.
##
## Доски строятся только в игре. В редакторе остаётся один профиль с провалом:
## иначе десяток тел и шарниров осел бы прямо в файл сцены при первом же
## сохранении, а при следующем открытии удвоился.

## Ровные площадки по краям — стыковочные хвосты.
@export var flat_margin: float = 40.0
## Берег между хвостом и обрывом.
@export var shore_length: float = 180.0
## Сколько досок в пролёте: (минимум, максимум).
@export var plank_count_range: Vector2i = Vector2i(6, 18)
## Насколько цепь длиннее пролёта: (минимум, максимум).
## 1.02 — почти струна, 1.06 — заметный провис.
@export var slack_range: Vector2 = Vector2(1.02, 1.045)
## Толщина доски. Тонкие красивее, но сквозь них проще провалиться.
@export var plank_thickness: float = 18.0
## Масса одной доски. Тяжёлые почти не шевелятся, лёгкие взлетают от колеса.
@export var plank_mass: float = 6.0
## Глубина пропасти. Дно нужно только чтобы полигон замкнулся,
## в кадр оно попадать не должно.
@export var chasm_depth: float = 1800.0
@export var plank_color: Color = Color(0.42, 0.31, 0.2)


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		apply_seed(0)


func apply_seed(value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	var count := rng.randi_range(
		plank_count_range.x, maxi(plank_count_range.x, plank_count_range.y))
	var slack := rng.randf_range(slack_range.x, slack_range.y)
	# Пролёт задаётся числом досок: так средняя доска остаётся одного
	# размера независимо от того, короткий мост выпал или длинный.
	var span := float(count) * 68.0
	_build_profile(span)
	if not Engine.is_editor_hint():
		_build_planks(span, count, slack)


## Трение дороги от сборщика распространяем и на настил, иначе колесо
## по доскам буксует, а по земле — нет.
func apply_physics_material(surface: PhysicsMaterial) -> void:
	super(surface)
	for child in get_children():
		if child is RigidBody2D:
			child.physics_material_override = surface


func _build_profile(span: float) -> void:
	if _outline == null:
		_collect_nodes()
	if _outline == null:
		return

	var left_edge := flat_margin + shore_length
	length = left_edge * 2.0 + span

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	points.append(Vector2(left_edge, 0.0))
	points.append(Vector2(left_edge, chasm_depth))
	points.append(Vector2(left_edge + span, chasm_depth))
	points.append(Vector2(left_edge + span, 0.0))
	points.append(Vector2(length, 0.0))
	points.append(Vector2(length, chasm_depth + 400.0))
	points.append(Vector2(0.0, chasm_depth + 400.0))

	_outline.polygon = points
	_sync_fill()
	update_configuration_warnings()


func _build_planks(span: float, count: int, slack: float) -> void:
	var left_edge := flat_margin + shore_length
	# Шаг — по пролёту, длина доски — по цепи. Доски получаются чуть
	# длиннее шага, слегка находят друг на друга и провисают сами.
	var pitch := span / float(count)
	var plank_length := pitch * slack

	var planks: Array[RigidBody2D] = []
	for i in count:
		var plank := RigidBody2D.new()
		plank.position = Vector2(left_edge + pitch * (float(i) + 0.5), 0.0)
		plank.mass = plank_mass
		# Затухание гасит раскачку после проезда: без него мост качается
		# до самого финиша.
		plank.linear_damp = 0.6
		plank.angular_damp = 1.2

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(plank_length, plank_thickness)
		shape.shape = rect
		plank.add_child(shape)

		var visual := Polygon2D.new()
		var half_x := plank_length * 0.5
		var half_y := plank_thickness * 0.5
		visual.polygon = PackedVector2Array([
			Vector2(-half_x, -half_y), Vector2(half_x, -half_y),
			Vector2(half_x, half_y), Vector2(-half_x, half_y),
		])
		visual.color = plank_color
		plank.add_child(visual)

		add_child(plank)
		planks.append(plank)

	# Шарниры: между соседними досками и по концам — к берегам.
	# Берег это тот же StaticBody2D, что держит профиль куска.
	for i in count + 1:
		var at := Vector2(left_edge + pitch * float(i), 0.0)
		var left_body: Node2D = _body if i == 0 else planks[i - 1]
		var right_body: Node2D = _body if i == count else planks[i]
		var joint := PinJoint2D.new()
		joint.position = at
		joint.node_a = joint.get_path_to(left_body)
		joint.node_b = joint.get_path_to(right_body)
		# Соседние доски перекрываются, и без этого они бы отталкивались.
		joint.disable_collision = true
		add_child(joint)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	for child in get_children():
		if child is RigidBody2D or child is PinJoint2D:
			issues.append(
				"В сцене сохранились доски или шарниры — их строит скрипт при запуске."
				+ " Удали их, иначе мост удвоится."
			)
			break
	return issues
