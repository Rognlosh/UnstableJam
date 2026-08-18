@tool
class_name GravelChunk
extends TrackChunk

## Промоина, засыпанная мелкой галькой. Камни — настоящие тела: колесо
## их разгребает, машина теряет ход и вязнет. Борта корыта держат крошку
## на месте, иначе первый же удар растащил бы её по всей трассе.
##
## Камни живут только пока кусок на экране. Полсотни тел в каждой промоине,
## помноженные на три-четыре промоины и сложенные с осколками разбитого
## груза, вышли бы за бюджет веб-сборки; VisibleOnScreenNotifier2D снимает
## вопрос почти бесплатно. Ехать назад игроку незачем, так что убранные
## камни возвращать не нужно — при повторном входе насыпаются новые.

## Ровные площадки по краям — стыковочные хвосты.
@export var flat_margin: float = 40.0
## Длина дна промоины.
@export var pit_length_range: Vector2 = Vector2(340.0, 560.0)
## Глубина промоины. Мелкая не удержит камни, глубокая станет ловушкой.
@export var pit_depth_range: Vector2 = Vector2(34.0, 56.0)
## Длина въездного и выездного скоса.
@export var slope_length: float = 80.0
## Сколько камней насыпается: (минимум, максимум).
@export var gravel_count_range: Vector2i = Vector2i(55, 90)
## Радиус камня: (минимум, максимум).
@export var gravel_radius_range: Vector2 = Vector2(5.0, 9.0)
## Масса камня. Тяжёлые не разгребаются, лёгкие разлетаются от колеса.
@export var gravel_mass: float = 0.5
@export var gravel_color: Color = Color(0.46, 0.44, 0.41)
@export var skirt_depth: float = 1400.0

var _pit_start: float = 0.0
var _pit_end: float = 0.0
var _pit_depth: float = 0.0
var _gravel_seed: int = 0
var _gravel_spawned: bool = false
var _surface_material: PhysicsMaterial


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		apply_seed(0)
		return
	_setup_notifier()


func apply_seed(value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	_gravel_seed = value
	_generate(rng)


## Трение дороги распространяем и на камни, иначе крошка ведёт себя
## как подшипники и машина проскальзывает вместо того, чтобы вязнуть.
func apply_physics_material(surface: PhysicsMaterial) -> void:
	super(surface)
	_surface_material = surface
	for child in get_children():
		if child is RigidBody2D:
			child.physics_material_override = surface


func _generate(rng: RandomNumberGenerator) -> void:
	if _outline == null:
		_collect_nodes()
	if _outline == null:
		return

	var pit := rng.randf_range(pit_length_range.x, pit_length_range.y)
	_pit_depth = rng.randf_range(pit_depth_range.x, pit_depth_range.y)
	length = flat_margin * 2.0 + slope_length * 2.0 + pit
	_pit_start = flat_margin + slope_length
	_pit_end = _pit_start + pit

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	points.append(Vector2(flat_margin, 0.0))
	points.append(Vector2(_pit_start, _pit_depth))
	points.append(Vector2(_pit_end, _pit_depth))
	points.append(Vector2(length - flat_margin, 0.0))
	points.append(Vector2(length, 0.0))
	points.append(Vector2(length, skirt_depth))
	points.append(Vector2(0.0, skirt_depth))

	_outline.polygon = points
	_sync_fill()
	update_configuration_warnings()


func _setup_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	# Рамку берём с запасом по высоте: камни должны насыпаться до того,
	# как промоина въедет в кадр, иначе игрок увидит их падение.
	notifier.rect = Rect2(
		_pit_start - 200.0, _pit_depth - 400.0,
		(_pit_end - _pit_start) + 400.0, 800.0)
	add_child(notifier)
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(_on_screen_exited)


func _on_screen_entered() -> void:
	if _gravel_spawned:
		return
	_gravel_spawned = true
	var rng := RandomNumberGenerator.new()
	rng.seed = _gravel_seed
	_spawn_gravel(rng)


func _on_screen_exited() -> void:
	if not _gravel_spawned:
		return
	_gravel_spawned = false
	for child in get_children():
		if child is RigidBody2D:
			child.queue_free()


func _spawn_gravel(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(
		gravel_count_range.x, maxi(gravel_count_range.x, gravel_count_range.y))
	var span := _pit_end - _pit_start
	for i in count:
		var radius := rng.randf_range(gravel_radius_range.x, gravel_radius_range.y)
		var stone := RigidBody2D.new()
		# Сыплем над дном вразнобой: камни укладываются сами за пару кадров,
		# и раскладка выходит естественнее любой сетки.
		stone.position = Vector2(
			_pit_start + rng.randf_range(radius, span - radius),
			_pit_depth - rng.randf_range(radius, _pit_depth * 0.9))
		stone.rotation = rng.randf_range(0.0, TAU)
		stone.mass = gravel_mass
		stone.angular_damp = 1.5
		if _surface_material != null:
			stone.physics_material_override = _surface_material

		var outline := _make_pebble(rng, radius)
		var shape := CollisionShape2D.new()
		var convex := ConvexPolygonShape2D.new()
		convex.points = outline
		shape.shape = convex
		stone.add_child(shape)

		var visual := Polygon2D.new()
		visual.polygon = outline
		visual.color = gravel_color
		stone.add_child(visual)

		add_child(stone)


## Камешек делаем угловатым, а не круглым: круги ведут себя как подшипники
## и раскатываются из-под колеса, вместо того чтобы держать машину.
func _make_pebble(rng: RandomNumberGenerator, radius: float) -> PackedVector2Array:
	var corners := rng.randi_range(5, 7)
	var points := PackedVector2Array()
	for i in corners:
		var angle := TAU * float(i) / float(corners)
		var r := radius * rng.randf_range(0.7, 1.0)
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return points


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	for child in get_children():
		if child is RigidBody2D:
			issues.append(
				"В сцене сохранились камни — их насыпает скрипт при запуске."
				+ " Удали их, иначе гальки станет вдвое больше."
			)
			break
	return issues
