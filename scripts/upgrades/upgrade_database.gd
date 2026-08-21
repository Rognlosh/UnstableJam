class_name UpgradeDatabase
extends Resource

## Список всех прокачек игры. Ровно та же роль, что у ItemDatabase:
## добавить строку в лавку наставника должно быть можно, не открывая скриптов.
##
## Порядок в массиве — порядок строк на вкладке «Лавка».

@export var upgrades: Array[UpgradeData] = []
