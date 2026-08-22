## Главное меню. Стадия как все остальные: грузится в StageContainer через
## StageManager, получает бесплатное затемнение перехода и не заводит второго
## механизма загрузки экранов.
##
## Язык и громкость живут в SettingsPanel — той же сцене, что вставлена
## в паузу. Отдельного экрана настроек нет намеренно: настроек четыре штуки,
## и прятать их за кнопкой значит добавить игроку клик ради пустого экрана.
extends Control

@export var new_game_button: Button
@export var quit_button: Button


func _ready() -> void:
	# В браузере окно закрыть нельзя: get_tree().quit() там не делает ничего,
	# и кнопка выглядела бы сломанной. Проверка по фиче, а не по OS.get_name():
	# имён у веб-платформы исторически было несколько.
	quit_button.visible = not OS.has_feature("web")

	new_game_button.pressed.connect(_on_new_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Фокус на первой кнопке: с клавиатуры меню должно проходиться без мыши,
	# а без явного фокуса первый Tab уходит непонятно куда.
	new_game_button.grab_focus()


## Единственное место, где начинается новая партия. Раньше сброс висел
## в _ready() менеджера стадий — там он срабатывал на запуске приложения,
## то есть ровно один раз, и второй партии за сессию не существовало.
func _on_new_game_pressed() -> void:
	GameState.reset_new_game()
	StageManager.instance.change_stage(StageManager.Stage.INTRO)


func _on_quit_pressed() -> void:
	get_tree().quit()
