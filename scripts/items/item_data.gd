class_name ItemData
extends Resource

## Описание предмета: как выглядит, сколько весит, когда бьётся, на что.

@export var id: StringName = &""
@export var display_name: String = ""
@export var base_price: int = 10
@export var mass: float = 1.0

## Порог разрушения: насколько сильно должна измениться скорость тела
## за один физ-кадр (px/s), чтобы предмет разбился.
@export var break_speed: float = 420.0
## Во сколько раз осколок прочнее целого предмета.
@export var piece_toughness: float = 1.6

@export var whole_polygon: PackedVector2Array = PackedVector2Array()
@export var pieces: Array[ItemPieceData] = []

@export var color: Color = Color(0.72, 0.66, 0.5)
@export var physics_material: PhysicsMaterial
