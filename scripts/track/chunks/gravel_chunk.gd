@tool
class_name GravelChunk
extends TrackChunk

## Промоина, засыпанная мелкой галькой. Камни — настоящие тела: колесо
## их разгребает, машина теряет ход и вязнет. Борта корыта держат крошку
## на месте, иначе первый же удар растащил бы её по всей трассе.
##
## Камни насыпаются один раз, когда кусок впервые приближается к кадру,
## и больше не пересоздаются. Пока промоина за экраном, тела заморожены:
## это снимает дорогую часть — симуляцию физики, — а сами камни остаются
## лежать где лежали. Удалять и насыпать заново нельзя: стоит игроку
## отъехать и вернуться, как новая насыпь материализуется прямо в машине.

## Ровные площадки по краям — стыковочные хвосты.
@export var flat_margin: float = 40.0
## Длина дна промоины.
@export var pit_length_range: Vector2 = Vector2(850.0, 1400.0)
## Глубина промоины. Мелкая не удержит камни, глубокая станет ловушкой.
## Глубина заодно задаёт вместимость: чем глубже корыто, тем больше
## ярусов гальки в него влезает, не поднимаясь выше краёв.
@export var pit_depth_range: Vector2 = Vector2(64.0, 96.0)
## Длина въездного и выездного скоса. При глубине под семь десятков
## короткий скос читается как обрыв, поэтому он втрое длиннее самой ямы
## по вертикали — выходит около 15 градусов.
@export var slope_length: float = 240.0
## Шаг сетки укладки в радиусах самого крупного камня. Меньше — плотнее
## насыпь и выше риск, что камни родятся друг в друге; больше — сквозь
## гальку проглядывает дно.
@export_range(1.6, 3.0, 0.1) var gravel_packing: float = 2.0
## Потолок числа ярусов. Держит бюджет тел на длинных промоинах.
@export_range(1, 6) var gravel_max_rows: int = 3
## Потолок числа камней — страховка бюджета тел в вебе.
@export var gravel_count_limit: int = 130
## Радиус камня: (минимум, максимум). Камень должен быть заметно мельче
## колеса (радиус 28 px), иначе колесо не вкатывается на насыпь, а бодает её.
@export var gravel_radius_range: Vector2 = Vector2(7.0, 13.0)
## Масса камня. Тяжёлые не разгребаются, лёгкие разлетаются от колеса.
@export var gravel_mass: float = 1.4
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
	# Рамка накрывает весь кусок с большим запасом: камни должны насыпаться
	# и улечься задолго до того, как промоина въедет в кадр, а размораживаться
	# раньше, чем до них доберётся колесо.
	notifier.rect = Rect2(
		-600.0, _pit_depth - 800.0,
		length + 1200.0, 1400.0)
	add_child(notifier)
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(_on_screen_exited)


func _on_screen_entered() -> void:
	if not _gravel_spawned:
		_gravel_spawned = true
		var rng := RandomNumberGenerator.new()
		rng.seed = _gravel_seed
		_spawn_gravel(rng)
		return
	_set_gravel_frozen(false)


func _on_screen_exited() -> void:
	_set_gravel_frozen(true)


## Заморозка вместо удаления. Тело в freeze не считается физикой, но остаётся
## на месте — вернувшись, игрок увидит ту же насыпь, которую разгрёб.
func _set_gravel_frozen(frozen: bool) -> void:
	for child in get_children():
		if child is RigidBody2D:
			child.freeze = frozen


func _spawn_gravel(rng: RandomNumberGenerator) -> void:
	var span := _pit_end - _pit_start
	# Раскладываем по сетке с разбросом, а не наугад: при сотне камней
	# случайные позиции неизбежно рождают их друг в друге, и физика расталкивает
	# такую кучу взрывом. Сетка гарантирует зазор, а джиттер убирает регулярность —
	# осядут камни всё равно вразнобой.
	var cell := gravel_radius_range.y * gravel_packing
	var columns := maxi(int(span / cell), 1)
	# Число ярусов диктует ГЛУБИНА корыта, а не его длина. Считать камни
	# от длины нельзя: лишние уходят наверх, насыпь поднимается выше краёв
	# ямы и превращается из вязкой крошки в стену, в которую машина упирается.
	var rows := clampi(int(_pit_depth / cell), 1, gravel_max_rows)
	var count := mini(columns * rows, gravel_count_limit)
	for i in count:
		var radius := rng.randf_range(gravel_radius_range.x, gravel_radius_range.y)
		var column := i % columns
		var row := i / columns
		var jitter := cell * 0.25
		var stone := RigidBody2D.new()
		stone.position = Vector2(
			_pit_start + cell * (float(column) + 0.5) + rng.randf_range(-jitter, jitter),
			_pit_depth - cell * (float(row) + 0.6) + rng.randf_range(-jitter, jitter))
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
