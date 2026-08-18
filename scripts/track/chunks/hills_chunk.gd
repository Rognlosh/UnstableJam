@tool
class_name HillsChunk
extends TrackChunk

## Холмы в духе Hill Climb Racing: длинные валы, на которые грузовик
## въезжает целиком. Это третий тип волны в наборе, и от двух других
## он отличается масштабом относительно машины. Гребёнка мельче колеса
## и работает резонансом, кочка сопоставима с колесом и работает ударом,
## холм длиннее всего грузовика — он отбирает скорость на подъёме,
## возвращает на спуске и раскачивает корпус.
##
## Форма холма собирается из гармоник вида (1 - cos(2*PI*k*u)) / 2.
## У любой такой функции и значение, и наклон на обоих концах равны нулю,
## поэтому холм пришивается к ровному хвосту без излома при любом наборе
## коэффициентов — а разные наборы дают разные силуэты, от простого горба
## до вершины с провалом посередине.

## Палитра силуэтов. harmonics — веса гармоник, weight — частота выпадения.
const SHAPES: Array = [
	{"harmonics": [1.0, 0.0, 0.0], "weight": 4.0},   # простой холм
	{"harmonics": [1.0, 0.25, 0.0], "weight": 2.0},  # холм с широкой вершиной
	{"harmonics": [1.0, 0.8, 0.0], "weight": 2.0},   # два пика, впадина наверху
	{"harmonics": [0.5, 1.0, 0.0], "weight": 1.5},   # двугорбый
	{"harmonics": [1.0, 0.45, 0.35], "weight": 1.0}, # волнистый
]

## Ровные площадки по краям — стыковочные хвосты.
@export var flat_margin: float = 40.0
## Сколько холмов в куске: (минимум, максимум). Длина куска отсюда и берётся.
@export var hill_count_range: Vector2i = Vector2i(1, 3)
## Ширина одного холма: (минимум, максимум).
@export var hill_width_range: Vector2 = Vector2(520.0, 1400.0)
## Крутизна как предельный уклон профиля: (пологий, крутой).
## 0.30 — это около 17 градусов, 0.62 — около 32.
@export var slope_range: Vector2 = Vector2(0.30, 0.62)
## Перекос жребия к пологим. 1.0 — все крутизны равновероятны,
## 2.0 — крутые заметно реже, 4.0 — почти никогда.
@export_range(1.0, 4.0, 0.1) var gentle_bias: float = 2.0
## Вероятность, что холм построится вниз и станет котловиной. Тот же силуэт
## с обратным знаком: машина в него проваливается и выкарабкивается.
@export_range(0.0, 1.0, 0.05) var dip_chance: float = 0.35
## Запас на растяжку сборщиком: к финишу профиль умножается, и холм,
## впритык проезжаемый в середине трассы, иначе встал бы стеной.
@export var height_scale_headroom: float = 1.5
## Точек на холм. Меньше двадцати — гладкая волна становится гранёной.
@export_range(12, 80) var samples_per_hill: int = 40
## Глубина юбки вниз, чтобы низ куска не попадал в кадр.
@export var skirt_depth: float = 1200.0


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		# Превью с постоянным зерном: в редакторе видно, что это холмы,
		# а сцена не меняется при каждом открытии.
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

	# 1. Бросаем состав куска: сколько холмов, какой ширины и силуэта.
	var count := rng.randi_range(hill_count_range.x, maxi(hill_count_range.x, hill_count_range.y))
	var widths: Array[float] = []
	var shapes: Array = []
	var slopes: Array[float] = []
	for i in count:
		widths.append(rng.randf_range(hill_width_range.x, hill_width_range.y))
		shapes.append(_pick_shape(rng))
		# Степень прижимает распределение к нулю: крутые выпадают редко.
		var roll := pow(rng.randf(), gentle_bias)
		slopes.append(lerpf(slope_range.x, slope_range.y, roll))

	var zone_length := 0.0
	for w in widths:
		zone_length += w
	# Длина куска — производная от состава, а не наоборот. Сборщик
	# двигает курсор по фактической точке выхода, поэтому переменная
	# длина ему безразлична.
	length = flat_margin * 2.0 + zone_length

	# 2. Считаем амплитуду каждого холма из его предельного уклона.
	# Разные силуэты при равной амплитуде круты по-разному (двугорбый
	# почти вдвое круче простого), поэтому меряем численно.
	var amplitudes: Array[float] = []
	for i in count:
		var unit_slope := _max_unit_slope(shapes[i])
		var allowed := slopes[i] / maxf(height_scale_headroom, 1.0)
		var amplitude := widths[i] * allowed / unit_slope
		# Отрицательная амплитуда разворачивает силуэт вниз — получается
		# котловина. Уклон при этом тот же, так что проезжаемость сохраняется.
		if rng.randf() < dip_chance:
			amplitude = -amplitude
		amplitudes.append(amplitude)

	# 3. Собираем точки.
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	points.append(Vector2(flat_margin, 0.0))

	var x := flat_margin
	var travelled := 0.0
	for i in count:
		var width: float = widths[i]
		var harmonics: Array = shapes[i]
		var amplitude: float = amplitudes[i]
		for s in range(1, samples_per_hill + 1):
			var u := float(s) / float(samples_per_hill)
			var local_x := x + width * u
			# Базовая линия ведёт кусок к точке выхода. smoothstep взят
			# нарочно: у него нулевой наклон на концах, поэтому подъём
			# всего куска не портит ровность хвостов.
			var base := exit_offset_y * smoothstep(0.0, 1.0, (travelled + width * u) / zone_length)
			points.append(Vector2(local_x, base - amplitude * _shape_value(harmonics, u)))
		x += width
		travelled += width

	points.append(Vector2(length - flat_margin, exit_offset_y))
	points.append(Vector2(length, exit_offset_y))

	# Дно куска обязано быть ниже дна самой глубокой котловины,
	# иначе полигон вывернется наизнанку.
	var deepest := 0.0
	for point in points:
		deepest = maxf(deepest, point.y)
	var bottom := maxf(skirt_depth, deepest + 400.0)
	points.append(Vector2(length, bottom))
	points.append(Vector2(0.0, bottom))

	_outline.polygon = points
	_sync_fill()
	update_configuration_warnings()


func _pick_shape(rng: RandomNumberGenerator) -> Array:
	var total := 0.0
	for shape in SHAPES:
		total += float(shape["weight"])
	var roll := rng.randf() * total
	for shape in SHAPES:
		roll -= float(shape["weight"])
		if roll <= 0.0:
			return shape["harmonics"]
	return SHAPES[0]["harmonics"]


## Значение силуэта в точке u из отрезка [0, 1], нормированное на единицу.
func _shape_value(harmonics: Array, u: float) -> float:
	var value := 0.0
	for k in harmonics.size():
		value += float(harmonics[k]) * (1.0 - cos(TAU * float(k + 1) * u)) * 0.5
	return value / _shape_peak(harmonics)


func _shape_peak(harmonics: Array) -> float:
	var peak := 0.0
	for s in 200:
		var u := float(s) / 199.0
		var value := 0.0
		for k in harmonics.size():
			value += float(harmonics[k]) * (1.0 - cos(TAU * float(k + 1) * u)) * 0.5
		peak = maxf(peak, value)
	return maxf(peak, 0.001)


## Максимальный наклон нормированного силуэта при амплитуде 1 и ширине 1.
func _max_unit_slope(harmonics: Array) -> float:
	var steepest := 0.0
	var previous := _shape_value(harmonics, 0.0)
	var steps := 200
	for s in range(1, steps + 1):
		var u := float(s) / float(steps)
		var value := _shape_value(harmonics, u)
		steepest = maxf(steepest, absf(value - previous) * float(steps))
		previous = value
	return maxf(steepest, 0.001)
