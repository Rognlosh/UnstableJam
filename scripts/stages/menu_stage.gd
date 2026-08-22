## Главное меню. Стадия как все остальные: грузится в StageContainer через
## StageManager, получает бесплатное затемнение перехода и не заводит второго
## механизма загрузки экранов.
##
## Здесь же живут настройки — отдельного экрана под них нет намеренно.
## Настроек четыре штуки, и прятать их за кнопкой значит добавить игроку
## лишний клик ради пустого экрана с двумя ползунками.
extends Control

@export var new_game_button: Button
@export var language_button: Button
@export var music_slider: HSlider
@export var sfx_slider: HSlider
@export var sound_check: CheckButton
@export var quit_button: Button


func _ready() -> void:
	# В браузере окно закрыть нельзя: get_tree().quit() там не делает ничего,
	# и кнопка выглядела бы сломанной. Проверка по фиче, а не по OS.get_name():
	# имён у веб-платформы исторически было несколько.
	quit_button.visible = not OS.has_feature("web")

	_setup_slider(music_slider, Settings.music_volume)
	_setup_slider(sfx_slider, Settings.sfx_volume)
	# Галка означает «звук включён», а не «выключен»: отрицание в подписи
	# читается вдвое дольше, а ошибиться в нём можно с первого взгляда.
	sound_check.button_pressed = not Settings.muted

	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	music_slider.drag_ended.connect(_on_drag_ended)
	sfx_slider.drag_ended.connect(_on_drag_ended)
	sound_check.toggled.connect(_on_sound_toggled)
	new_game_button.pressed.connect(_on_new_game_pressed)
	language_button.pressed.connect(_on_language_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	_refresh_language_button()
	# Фокус на первой кнопке: с клавиатуры меню должно проходиться без мыши,
	# а без явного фокуса первый Tab уходит непонятно куда.
	new_game_button.grab_focus()


func _exit_tree() -> void:
	# Страховка на случай, когда ползунок крутили стрелками: drag_ended
	# при этом не приходит вовсе, и настройки уехали бы без записи.
	Settings.save_settings()


func _setup_slider(slider: HSlider, value: float) -> void:
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	# Без сигнала: иначе выставление стартового значения тут же полетело бы
	# обратно в Settings и разослало changed на пустом месте.
	slider.set_value_no_signal(value)


## Кнопка языка подписана тем языком, на который переключит, и подписана
## на нём же: «English» одинаково понятно в обеих локалях, а «Английский»
## англичанину — нет.
func _refresh_language_button() -> void:
	language_button.text = tr("MENU_LANG_EN") if Settings.is_russian() else tr("MENU_LANG_RU")


func _on_music_changed(value: float) -> void:
	Settings.music_volume = value


func _on_sfx_changed(value: float) -> void:
	Settings.sfx_volume = value


## drag_ended отдаёт признак «значение изменилось», он нам не нужен:
## пишем в любом случае, файл крошечный.
func _on_drag_ended(_value_changed: bool) -> void:
	Settings.save_settings()


func _on_sound_toggled(pressed: bool) -> void:
	Settings.muted = not pressed
	Settings.save_settings()


func _on_language_pressed() -> void:
	# set_locale внутри сам пишет файл. Метки с ключами в свойстве text
	# движок перевыведет сам, а вот текст кнопки поставлен кодом — его руками.
	Settings.toggle_locale()
	_refresh_language_button()


## Единственное место, где начинается новая партия. Раньше сброс висел
## в _ready() менеджера стадий — там он срабатывал на запуске приложения,
## то есть ровно один раз, и второй партии за сессию не существовало.
func _on_new_game_pressed() -> void:
	GameState.reset_new_game()
	StageManager.instance.change_stage(StageManager.Stage.INTRO)


func _on_quit_pressed() -> void:
	get_tree().quit()
