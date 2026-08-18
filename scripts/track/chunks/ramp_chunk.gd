@tool
class_name RampChunk
extends TrackChunk

## Трамплин со сбросом высоты: разгон, подъём на горб, за вершиной уступ вниз
## и длинная посадочная площадка. Пропасти здесь нет — риск в приземлении,
## а не в недолёте: грузовик прикладывается о землю всей массой, и груз
## в кузове этого может не пережить.
##
## Сброс бросается случайно, но сборщик читает exit_offset_y из сцены ещё
## до генерации, чтобы проверить коридор высот. Поэтому в сцене стоит номинал,
## а разброс держится вокруг него — коридор проверяется по номиналу
## с полуторакратным запасом и заведомо покрывает максимум.

## Ровные площадки по краям — стыковочные хвосты.
@export var flat_margin: float = 40.0
## Разгон перед трамплином. Короткий — не успеть набрать скорость.
@export var run_up_range: Vector2 = Vector2(220.0, 460.0)
## Высота горба над уровнем въезда.
@export var lip_height_range: Vector2 = Vector2(30.0, 70.0)
## Угол подъёма трамплина в градусах. Круче 30 — машина теряет ход,
## положе 18 — не отрывается вовсе.
@export var lip_angle_range: Vector2 = Vector2(18.0, 30.0)
## Сброс высоты за вершиной. Два колёсных радиуса — это около 56 px.
@export var drop_range: Vector2 = Vector2(40.0, 90.0)
## Посадочная площадка. Должна быть длиннее самого дальнего прыжка,
## иначе грузовик влетит в следующее препятствие прямо в воздухе.
@export var landing_range: Vector2 = Vector2(420.0, 700.0)
## Какая доля высоты падения уходит на скос за вершиной. 0 — отвесная
## стенка, 1 — уклон в 45 градусов. Скос нужен, чтобы медленная машина
## съезжала вниз, а не втыкалась носом.
@export_range(0.0, 1.0, 0.05) var cut_ratio: float = 0.35
@export var skirt_depth: float = 1400.0


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
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

	var run_up := rng.randf_range(run_up_range.x, run_up_range.y)
	var lip_height := rng.randf_range(lip_height_range.x, lip_height_range.y)
	var angle := deg_to_rad(rng.randf_range(lip_angle_range.x, lip_angle_range.y))
	var drop := rng.randf_range(drop_range.x, drop_range.y)
	var landing := rng.randf_range(landing_range.x, landing_range.y)

	# Подъём задан высотой и углом, длина из них выводится.
	var climb := lip_height / tan(angle)
	var fall := lip_height + drop
	var cut := fall * cut_ratio

	exit_offset_y = drop
	length = flat_margin * 2.0 + run_up + climb + cut + landing

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	var x := flat_margin + run_up
	points.append(Vector2(x, 0.0))
	x += climb
	points.append(Vector2(x, -lip_height))
	x += cut
	points.append(Vector2(x, drop))
	points.append(Vector2(length - flat_margin, drop))
	points.append(Vector2(length, drop))
	points.append(Vector2(length, drop + skirt_depth))
	points.append(Vector2(0.0, skirt_depth))

	_outline.polygon = points
	_sync_fill()
	update_configuration_warnings()
