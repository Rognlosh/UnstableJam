## Блок настроек: переключатель языка, две громкости и общий выключатель звука.
##
## Отдельной сценой, потому что нужен дважды — в главном меню и в паузе.
## Копия вместо переиспользования разошлась бы на первой же правке, причём
## молча: обе копии продолжали бы работать, просто по-разному.
extends VBoxContainer

@export var language_button: Button
@export var music_slider: HSlider
@export var sfx_slider: HSlider
@export var sound_check: CheckButton


func _ready() -> void:
	_setup_slider(music_slider)
	_setup_slider(sfx_slider)

	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	music_slider.drag_ended.connect(_on_drag_ended)
	sfx_slider.drag_ended.connect(_on_drag_ended)
	sound_check.toggled.connect(_on_sound_toggled)
	language_button.pressed.connect(_on_language_pressed)

	refresh()


func _exit_tree() -> void:
	# Страховка на случай, когда ползунок крутили стрелками с клавиатуры:
	# drag_ended при этом не приходит вовсе, и настройки уехали бы без записи.
	Settings.save_settings()


## Подтянуть значения из Settings. Публично, потому что панель в паузе живёт
## в дереве всё время и её _ready() случается один раз за игру — а настройки
## за это время могли поменяться в другой копии панели.
func refresh() -> void:
	# Без сигнала: иначе выставление значения полетело бы обратно в Settings
	# и разослало changed на пустом месте.
	music_slider.set_value_no_signal(Settings.music_volume)
	sfx_slider.set_value_no_signal(Settings.sfx_volume)
	# Галка означает «звук включён», а не «выключен»: отрицание в подписи
	# читается вдвое дольше, а ошибиться в нём можно с первого взгляда.
	sound_check.set_pressed_no_signal(not Settings.muted)
	_refresh_language_button()


func _setup_slider(slider: HSlider) -> void:
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01


## Кнопка языка подписана тем языком, на который переключит, и подписана
## на нём же: «English» одинаково понятно в обеих локалях, а «Английский»
## англичанину — нет.
func _refresh_language_button() -> void:
	language_button.text = tr("MENU_LANG_EN") if Settings.is_russian() else tr("MENU_LANG_RU")


func _on_music_changed(value: float) -> void:
	Settings.music_volume = value


func _on_sfx_changed(value: float) -> void:
	Settings.sfx_volume = value


## drag_ended отдаёт признак «значение изменилось», он не нужен:
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
