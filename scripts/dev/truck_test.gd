extends Node2D

## Стенд настройки грузовика. В сборку не идёт.
## Дорога собирается узлом TrackBuilder из кусков-сцен,
## всё остальное — узлы, размещённые в редакторе.

const CARGO_COUNT: int = 5

@export_group("Сцена")
@export var truck: Truck
@export var camera: Camera2D
@export var cargo_root: Node2D
@export var track: TrackBuilder

@export_group("Интерфейс")
@export var info_label: Label
@export var stiffness_slider: HSlider
@export var damping_slider: HSlider
@export var rest_slider: HSlider
@export var travel_slider: HSlider
@export var motor_slider: HSlider
@export var lean_slider: HSlider
@export var wall_slider: HSlider
@export var spawn_button: Button
@export var clear_button: Button
@export var reset_button: Button
@export var rebuild_button: Button

var _start_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build_track(false)
	_init_sliders()
	spawn_button.pressed.connect(_on_spawn_cargo)
	clear_button.pressed.connect(_on_clear_cargo)
	reset_button.pressed.connect(_on_reset)
	rebuild_button.pressed.connect(_on_rebuild)
	truck.rebuild_suspension()


func _process(_delta: float) -> void:
	camera.global_position = truck.chassis.global_position
	var compression := truck.get_compression()
	# Пройденный путь считаем от точки старта, а не от нуля сцены:
	# так число на экране совпадает с прогрессом по трассе.
	var travelled := truck.chassis.global_position.x - _start_position.x
	info_label.text = (
		"Скорость: %d px/s\n"
		+ "Путь: %d / %d px\n"
		+ "Сжатие: зад %d px · перед %d px\n"
		+ "Жёсткость %d · демпфер %.1f\n"
		+ "Длина %d · ход %d\n"
		+ "Момент %d · наклон %d\n"
		+ "Борта %d\n"
		+ "Кусков: %d · зерно %d\n"
		+ "Тел: %d · FPS %d"
	) % [
		int(truck.get_speed()),
		int(travelled), int(track.get_total_length()),
		int(compression.x), int(compression.y),
		int(truck.suspension_stiffness), truck.suspension_damping,
		int(truck.suspension_rest_length), int(truck.suspension_travel),
		int(truck.motor_torque), int(truck.lean_torque),
		int(truck.bed_wall_height),
		track.get_chunk_count(), track.track_seed,
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
	_setup_slider(motor_slider, 50000.0, 2000000.0, 10000.0, truck.motor_torque,
		func(v: float) -> void: truck.motor_torque = v)
	_setup_slider(lean_slider, 100000.0, 4000000.0, 10000.0, truck.lean_torque,
		func(v: float) -> void: truck.lean_torque = v)
	_setup_slider(wall_slider, 24.0, 200.0, 4.0, truck.bed_wall_height,
		func(v: float) -> void: truck.bed_wall_height = v)


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


## new_seed = false пересобирает ту же самую трассу: настройки подвески
## сравнимы между запусками только на одинаковой геометрии.
func _build_track(new_seed: bool) -> void:
	track.randomize_seed_on_build = new_seed
	track.build()
	_start_position = track.get_start_position()
	_on_clear_cargo()
	truck.teleport_to(_start_position)


func _on_rebuild() -> void:
	_build_track(true)


func _on_spawn_cargo() -> void:
	var bounds := truck.get_bed_bounds()
	var span := bounds.y - bounds.x
	# Раскладываем груз равномерно по длине кузова, с отступом от стенок.
	var step := span / float(CARGO_COUNT + 1)
	for i in CARGO_COUNT:
		var local_x := bounds.x + step * (i + 1)
		var at := truck.chassis.to_global(Vector2(local_x, -54.0))
		Destruction.spawn_item(ItemCatalog.vase(), cargo_root, at)


func _on_clear_cargo() -> void:
	for child in cargo_root.get_children():
		child.queue_free()


func _on_reset() -> void:
	_on_clear_cargo()
	truck.teleport_to(_start_position)
