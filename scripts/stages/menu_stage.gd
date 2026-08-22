## Главное меню. Стадия как все остальные: грузится в StageContainer через
## StageManager, получает бесплатное затемнение перехода и не заводит второго
## механизма загрузки экранов.
##
## Язык и громкость живут в SettingsPanel — той же сцене, что вставлена
## в паузу. Отдельного экрана настроек нет намеренно: настроек четыре штуки,
## и прятать их за кнопкой значит добавить игроку клик ради пустого экрана.
extends Control

@export var continue_button: Button
@export var new_game_button: Button
@export var quit_button: Button

## Новая игра поверх сохранения подтверждается вторым нажатием той же кнопки —
## тот же приём, что у выхода в меню из паузы. Без него один промах мышью
## стирает партию, а восстановить её неоткуда.
var _new_game_armed: bool = false


func _ready() -> void:
	# В браузере окно закрыть нельзя: get_tree().quit() там не делает ничего,
	# и кнопка выглядела бы сломанной. Проверка по фиче, а не по OS.get_name():
	# имён у веб-платформы исторически было несколько.
	quit_button.visible = not OS.has_feature("web")
	continue_button.visible = GameState.has_save()

	continue_button.pressed.connect(_on_continue_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Фокус на том, что игрок нажмёт вероятнее всего: вернувшемуся нужна
	# его партия, а не новая. С клавиатуры меню должно проходиться без мыши,
	# а без явного фокуса первый Tab уходит непонятно куда.
	if continue_button.visible:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()


## Загрузка всегда приходится на начало дня — закуп. Заезд не сохраняется,
## поэтому выход посреди дороги возвращает игрока к утру того же дня,
## когда товар ещё лежал на складе.
func _on_continue_pressed() -> void:
	if not GameState.load_game():
		# Файл есть, но не читается. Молча начинать новую партию нельзя —
		# игрок решит, что игра съела его прогресс и не заметит подмены.
		continue_button.disabled = true
		continue_button.text = "MENU_CONTINUE_FAILED"
		return
	StageManager.instance.change_stage(StageManager.Stage.SHOP)


## Единственное место, где начинается новая партия. Раньше сброс висел
## в _ready() менеджера стадий — там он срабатывал на запуске приложения,
## то есть ровно один раз, и второй партии за сессию не существовало.
func _on_new_game_pressed() -> void:
	if GameState.has_save() and not _new_game_armed:
		_new_game_armed = true
		new_game_button.text = "MENU_NEW_GAME_CONFIRM"
		return
	GameState.reset_new_game()
	StageManager.instance.change_stage(StageManager.Stage.INTRO)


func _on_quit_pressed() -> void:
	get_tree().quit()
