extends Node2D

## Стенд настройки грузовика. В сборку не идёт.
## Дорога строится кодом (сотни точек профиля руками не расставить),
## всё остальное — узлы, размещённые в редакторе.

const ROAD_BASE_Y: float = 320.0
const ROAD_LENGTH: float = 5200.0
const ROAD_STEP: float = 20.0
const ROAD_DEPTH: float = 400.0
const START_POSITION: Vector2 = Vector2(260.0, 200.0)
const CARGO_COUNT: int = 5

@export_group("Сцена")
@export var truck: Truck
@export var camera: Camera2D
@export var cargo_root: Node2D

@export_group("Интерфейс")
@export var info_label: Label
@export var stiffness_slider: HSlider
@export var damping_slider: HSlider
@export var rest_slider: HSlider
@export var travel_slider: HSlider
@export var motor_slider: HSlider
@export var lean_slider: HSlider
@export var spawn_button: Button
@export var clear_button: Button
@export var reset_button: Button


func _ready() -> void:
	_build_road()
	_init_sliders()
	spawn_button.pressed.connect(_on_spawn_cargo)
	clear_button.pressed.connect(_on_clear_cargo)
	reset_button.pressed.connect(_on_reset)
	truck.rebuild_suspension()


func _process(_delta: float) -> void:
	camera.global_position = truck.chassis.global_position
	var compression := truck.get_compression()
	info_label.text = (
		"Скорость: %d px/s\n"
		+ "Сжатие: зад %d px · перед %d px\n"
		+ "Жёсткость %d · демпфер %.1f\n"
		+ "Длина %d · ход %d\n"
		+ "Момент %d · наклон %d\n"
		+ "Тел: %d · FPS %d"
	) % [
		int(truck.get_speed()),
		int(compression.x), int(compression.y),
		int(truck.suspension_stiffness), truck.suspension_damping,
		int(truck.suspension_rest_length), int(truck.suspension_travel),
		int(truck.motor_torque), int(truck.lean_torque),
		get_tree().get_nodes_in_group(&"cargo").size(),
		Engine.get_frames_per_second(),
	]


func _init_sliders() -> void:
	_setup_slider(stiffness_slider, 400.0, 8000.0, 50.0, truck.suspension_stiffness,
		func(v: float) -> void: truck.suspension_stiffness = v)
	_setup_slider(damping_slider, 0.0, 8.0, 0.1, truck.suspension_damping,
		func(v: float) -> void: truck.suspension_damping = v)
	_setup_slider(rest_slider, 28.0, 72.0, 1.0, truck.suspension_rest_length,
		func(v: float) -> void:
			truck.suspension_rest_length = v
			truck.rebuild_suspension())
	_setup_slider(travel_slider, 10.0, 56.0, 1.0, truck.suspension_travel,
		func(v: float) -> void:
			truck.suspension_travel = v
			truck.rebuild_suspension())
	_setup_slider(motor_slider, 50000.0, 1500000.0, 10000.0, truck.motor_torque,
		func(v: float) -> void: truck.motor_torque = v)
	_setup_slider(lean_slider, 100000.0, 3000000.0, 10000.0, truck.lean_torque,
		func(v: float) -> void: truck.lean_torque = v)


## Callable — это «ссылка на функцию», аналог делегата в C#.
## Лямбда через func(...) -> ... : ... позволяет не плодить шесть обработчиков.
func _setup_slider(
	slider: HSlider, low: float, high: float, step: float,
	value: float, handler: Callable
) -> void:
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.value_changed.connect(handler)


func _on_spawn_cargo() -> void:
	for i in CARGO_COUNT:
		var local_x := -92.0 + i * 46.0
		var at := truck.chassis.to_global(Vector2(local_x, -56.0))
		Destruction.spawn_item(ItemCatalog.vase(), cargo_root, at)


func _on_clear_cargo() -> void:
	for child in cargo_root.get_children():
		child.queue_free()


func _on_reset() -> void:
	_on_clear_cargo()
	truck.teleport_to(START_POSITION)


## Профиль дороги: 0 — уровень ROAD_BASE_Y, отрицательные значения — вверх.
func _road_height(x: float) -> float:
	if x < 620.0:
		return 0.0
	if x < 1500.0:
		# Кочки: только верхние полуволны, между ними ровно.
		return -30.0 * maxf(0.0, sin((x - 620.0) / 260.0 * TAU))
	if x < 1800.0:
		return 0.0
	if x < 2500.0:
		return -9.0 * sin((x - 1800.0) / 58.0 * TAU)  # гребёнка
	if x < 2800.0:
		return 0.0
	if x < 3400.0:
		# «Галька»: сумма несоизмеримых синусов — выглядит случайно,
		# но повторяется от запуска к запуску, значит настройку можно сравнивать.
		return -5.0 * (sin(x * 0.21) + sin(x * 0.37) + sin(x * 0.53))
	if x < 3700.0:
		return 0.0
	if x < 4100.0:
		return -(x - 3700.0) * 0.3  # рампа вверх
	if x < 4200.0:
		return -120.0               # площадка, дальше обрыв
	return 0.0


func _build_road() -> void:
	var profile := PackedVector2Array()
	var x := 0.0
	while x <= ROAD_LENGTH:
		profile.append(Vector2(x, ROAD_BASE_Y + _road_height(x)))
		x += ROAD_STEP

	# Замыкаем контур вниз, чтобы получился цельный полигон.
	var outline := profile.duplicate()
	outline.append(Vector2(ROAD_LENGTH, ROAD_BASE_Y + ROAD_DEPTH))
	outline.append(Vector2(0.0, ROAD_BASE_Y + ROAD_DEPTH))

	var ground := StaticBody2D.new()
	ground.name = "Ground"
	var material := PhysicsMaterial.new()
	material.friction = 1.0
	material.bounce = 0.0
	ground.physics_material_override = material

	# BUILD_SEGMENTS собирает из контура одну вогнутую форму-цепочку.
	# Один узел вместо двухсот отдельных прямоугольников.
	var shape := CollisionPolygon2D.new()
	shape.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	shape.polygon = outline
	ground.add_child(shape)

	var visual := Polygon2D.new()
	visual.polygon = outline
	visual.color = Color(0.27, 0.24, 0.21)
	ground.add_child(visual)

	add_child(ground)
	move_child(ground, 0)
