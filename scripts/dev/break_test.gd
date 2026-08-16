extends Node2D

## Испытательный стенд для системы разрушения. В сборку не попадает —
## нужен, чтобы калибровать пороги без готового грузовика.

const FLOOR_Y: float = 280.0
const HALF_WIDTH: float = 620.0
const GRAVITY: float = 980.0

var _items: Node2D
var _ground: AnimatableBody2D
var _height_slider: HSlider
var _info: Label

var _ground_base_y: float = 0.0
var _shake_left: float = 0.0


func _ready() -> void:
	_items = Node2D.new()
	_items.name = "Items"
	add_child(_items)
	_build_arena()
	_build_ui()


func _physics_process(delta: float) -> void:
	if _shake_left > 0.0:
		_shake_left -= delta
		_ground.position.y = _ground_base_y + sin(_shake_left * TAU * 9.0) * 16.0
	elif not is_equal_approx(_ground.position.y, _ground_base_y):
		_ground.position.y = _ground_base_y


func _process(_delta: float) -> void:
	var height: float = _height_slider.value
	var speed := sqrt(2.0 * GRAVITY * height)
	_info.text = "Тел: %d   осколков: %d   FPS: %d\nСкорость касания ≈ %d px/s" % [
		get_tree().get_nodes_in_group(&"cargo").size(),
		Destruction.live_fragment_count(),
		Engine.get_frames_per_second(),
		int(speed),
	]


func _build_arena() -> void:
	# Пол — AnimatableBody2D, а не StaticBody2D: его можно двигать, и он
	# честно толкает лежащие сверху тела. Это и есть имитация кочки.
	_ground = AnimatableBody2D.new()
	_ground.sync_to_physics = true
	_ground.position = Vector2(0.0, FLOOR_Y)
	_ground_base_y = _ground.position.y
	_ground.add_child(_make_box_shape(Vector2(HALF_WIDTH * 2.0, 40.0)))
	_ground.add_child(_make_box_visual(Vector2(HALF_WIDTH * 2.0, 40.0), Color(0.25, 0.24, 0.22)))
	add_child(_ground)
	

	for side in [-1.0, 1.0]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(HALF_WIDTH * side, FLOOR_Y - 200.0)
		wall.add_child(_make_box_shape(Vector2(40.0, 400.0)))
		wall.add_child(_make_box_visual(Vector2(40.0, 400.0), Color(0.22, 0.21, 0.2)))
		add_child(wall)
		
	# Без камеры точка (0, 0) — угол экрана, и арена уезжает влево.
	var camera := Camera2D.new()
	camera.position = Vector2(0.0, 40.0)
	add_child(camera)
	camera.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var box := VBoxContainer.new()
	box.position = Vector2(16.0, 16.0)
	box.custom_minimum_size = Vector2(260.0, 0.0)
	layer.add_child(box)

	_info = Label.new()
	box.add_child(_info)

	var height_label := Label.new()
	height_label.text = "Высота падения"
	box.add_child(height_label)

	_height_slider = HSlider.new()
	_height_slider.min_value = 20.0
	_height_slider.max_value = 900.0
	_height_slider.step = 10.0
	_height_slider.value = 200.0
	box.add_child(_height_slider)

	_add_button(box, "Уронить вазу", _on_drop_one)
	_add_button(box, "Уронить пять", _on_drop_many)
	_add_button(box, "Тряхнуть пол", _on_shake)
	_add_button(box, "Очистить", _on_clear)


func _add_button(parent: Node, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)


func _on_drop_one() -> void:
	_drop(randf_range(-40.0, 40.0))


func _on_drop_many() -> void:
	for i in 5:
		_drop(randf_range(-160.0, 160.0))


func _on_shake() -> void:
	_shake_left = 1.4


func _on_clear() -> void:
	for child in _items.get_children():
		child.queue_free()


func _drop(offset_x: float) -> void:
	var spawn_y := FLOOR_Y - 20.0 - _height_slider.value
	Destruction.spawn_item(ItemCatalog.vase(), _items, Vector2(offset_x, spawn_y))


func _make_box_shape(size: Vector2) -> CollisionShape2D:
	var node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	node.shape = rect
	return node


func _make_box_visual(size: Vector2, color: Color) -> Polygon2D:
	var node := Polygon2D.new()
	var half := size * 0.5
	node.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	node.color = color
	return node
