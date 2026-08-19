class_name Palette
extends RefCounted

## Точка доступа к палитре. Отдельным классом, а не константой внутри
## самой WorldPalette: там получилась бы ссылка скрипта на ресурс,
## которому этот же скрипт и нужен.
##
## preload, а не поиск файла: при экспорте текстовые ресурсы становятся
## бинарными, и путь с расширением .tres движок подменяет сам.
const WORLD: WorldPalette = preload("res://assets/world/palette.tres")
