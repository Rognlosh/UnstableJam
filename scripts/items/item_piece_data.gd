class_name ItemPieceData
extends Resource

## Один заранее заданный кусок предмета.
## Полигон задан в локальных координатах ЦЕЛОГО предмета — именно это
## позволит потом собрать его обратно (реставрация).

@export var piece_id: StringName = &""
@export var polygon: PackedVector2Array = PackedVector2Array()
## Доля цены предмета, которую несёт кусок. Сумма долей всех кусков = 1.0.
@export_range(0.0, 1.0) var value_share: float = 0.25
