@tool
class_name WashboardChunk
extends TrackChunk

## Гребёнка — сплошная зона мелкой ряби. В отличие от кочек это не событие,
## а резонанс: подвеска не успевает отработать один горб до прихода следующего,
## и груз начинает подпрыгивать сам, без единого крупного удара.
##
## Профиль строится кодом: полторы сотни точек руками не расставить,
## да и разными от заезда к заезду они быть не смогут.

## Ровные площадки по краям — стыковочные хвосты, их геометрия священна.
@export var flat_margin: float = 40.0
## Амплитуда волны: (минимум, максимум). Считается от уровня дороги
## в обе стороны, то есть горб вверх и такая же ямка следом.
@export var amplitude_range: Vector2 = Vector2(5.0, 16.0)
## Длина одной волны: (минимум, максимум).
@export var step_range: Vector2 = Vector2(38.0, 92.0)
## Перекос жребия к мелким волнам. 1.0 — все размеры равновероятны,
## 2.2 — крупные выпадают заметно реже, 4.0 — почти никогда.
@export_range(1.0, 4.0, 0.1) var small_bias: float = 2.2
## Сколько точек на волну. Меньше восьми — синус превращается в пилу.
@export_range(4, 16) var samples_per_wave: int = 8
## Глубина юбки вниз, чтобы низ куска не попадал в кадр.
@export var skirt_depth: float = 1200.0


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		# Превью с постоянным зерном: в редакторе видно, что это гребёнка,
		# а сцена не меняется при каждом открытии и не просится сохраниться.
		apply_seed(0)


func apply_seed(value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	_generate(rng)


func _generate(rng: RandomNumberGenerator) -> void:
	if _outline == null:
		_collect_nodes()
	if _outline == null:
		return

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	points.append(Vector2(flat_margin, 0.0))

	var zone_end := length - flat_margin
	var x := flat_margin
	while x < zone_end - 0.5:
		# Один жребий на волну: степень прижимает распределение к мелким.
		var roll := pow(rng.randf(), small_bias)
		var step := lerpf(step_range.x, step_range.y, roll)
		var amplitude := lerpf(amplitude_range.x, amplitude_range.y, roll)
		var remaining := zone_end - x
		# Хвост короче полутора минимальных шагов доедаем текущей волной,
		# иначе в конце зоны останется огрызок в пару пикселей.
		if remaining < step_range.x * 1.5:
			step = remaining
		else:
			step = minf(step, remaining)
		for i in range(1, samples_per_wave + 1):
			var f := float(i) / float(samples_per_wave)
			points.append(Vector2(x + step * f, -amplitude * sin(f * TAU)))
		x += step

	points.append(Vector2(length, 0.0))
	points.append(Vector2(length, skirt_depth))
	points.append(Vector2(0.0, skirt_depth))

	_outline.polygon = points
	_sync_fill()
