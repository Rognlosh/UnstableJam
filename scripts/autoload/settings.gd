## Настройки игрока: язык и громкость. Автозагрузка — живёт всю сессию,
## переживает смену стадий и не зависит от того, какое меню сейчас открыто.
##
## Файл лежит в user://settings.cfg. В вебе user:// — это IndexedDB браузера,
## поэтому настройки переживают перезагрузку вкладки и не требуют ничего
## настраивать на стороне itch.io.
##
## Здесь только состояние и его применение. UI (слайдеры, переключатель языка)
## живёт в сценах и обращается сюда — обратной зависимости нет.
extends Node

## Испускается при любом изменении. Меню подписывается, чтобы пауза и главное
## меню показывали одно и то же, если игрок покрутил ползунок в одном из них.
signal changed

## Путь к файлу настроек. user:// — папка данных приложения; res:// в собранной
## игре доступен только для чтения, писать туда нельзя.
const CONFIG_PATH: String = "user://settings.cfg"
## Секция внутри ini-файла. Одна: настроек мало, дробить нечего.
const SECTION: String = "settings"

## Имена шин из панели «Аудио». StringName, а не String: сравнение идёт
## по указателю, и в вызовах AudioServer это бесплатно.
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_MASTER: StringName = &"Master"

## Ниже этого порога ползунок считается нулём. Нужен, потому что
## linear_to_db(0.0) даёт -inf: сервер такое переваривает, а вот в ini-файл
## писать бесконечность не хочется. Вместо этого шина глушится целиком.
const SILENCE_THRESHOLD: float = 0.001

## Громкость 0..1 линейно — как её видит игрок на ползунке.
## В децибелы переводим только в момент применения.
var music_volume: float = 0.8: set = set_music_volume
var sfx_volume: float = 0.8: set = set_sfx_volume
## Общий выключатель звука. Глушит Master, поэтому позиции ползунков
## сохраняются: включил обратно — вернулось как было.
var muted: bool = false: set = set_muted

## Язык, выбранный игроком вручную. Пустая строка означает «не выбирал» —
## тогда язык остаётся тот, что движок определил по локали браузера.
## Отличать одно от другого обязательно: запиши мы сюда определённый язык
## при первом запуске, игрок навсегда получил бы язык той машины,
## на которой открыл игру впервые.
var locale_override: String = ""


func _ready() -> void:
	load_settings()


## --- Громкость ---

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus(BUS_MUSIC, music_volume)
	changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus(BUS_SFX, sfx_volume)
	changed.emit()


func set_muted(value: bool) -> void:
	muted = value
	var idx: int = AudioServer.get_bus_index(BUS_MASTER)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)
	changed.emit()


## Перевод ползунка в громкость шины. Слух логарифмический, поэтому
## линейная доля идёт через linear_to_db: без него верхняя половина
## ползунка почти не слышна, а вся разница набивается в первые проценты.
func _apply_bus(bus_name: StringName, volume: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("Settings: не найдена аудиошина " + String(bus_name))
		return
	AudioServer.set_bus_mute(idx, volume <= SILENCE_THRESHOLD)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, SILENCE_THRESHOLD)))


## Применить всё разом — после загрузки файла и на первом запуске.
func _apply_audio() -> void:
	_apply_bus(BUS_MUSIC, music_volume)
	_apply_bus(BUS_SFX, sfx_volume)
	var idx: int = AudioServer.get_bus_index(BUS_MASTER)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


## --- Язык ---

## Сейчас показывается русский? Проверка по префиксу, а не по равенству:
## локаль может прийти как "ru_RU", и точное сравнение с "ru" её потеряет.
func is_russian() -> bool:
	return TranslationServer.get_locale().begins_with("ru")


## Переключатель одной кнопкой. Языка два, промежуточных состояний нет.
func toggle_locale() -> void:
	set_locale("en" if is_russian() else "ru")


func set_locale(code: String) -> void:
	locale_override = code
	TranslationServer.set_locale(code)
	changed.emit()
	save_settings()


## --- Файл ---

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		# Файла нет — первый запуск (или веб-хранилище почистили).
		# Язык не трогаем вовсе: движок уже выбрал его по локали браузера,
		# а чего нет в переводах — уйдёт в резервный английский.
		_apply_audio()
		return

	music_volume = float(cfg.get_value(SECTION, "music", music_volume))
	sfx_volume = float(cfg.get_value(SECTION, "sfx", sfx_volume))
	muted = bool(cfg.get_value(SECTION, "muted", muted))
	locale_override = String(cfg.get_value(SECTION, "locale", ""))

	if not locale_override.is_empty():
		TranslationServer.set_locale(locale_override)
	_apply_audio()


## Запись на диск. Зовётся не из сеттеров, а руками — из UI, когда игрок
## отпустил ползунок. Иначе перетаскивание мыши писало бы файл каждый кадр.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "music", music_volume)
	cfg.set_value(SECTION, "sfx", sfx_volume)
	cfg.set_value(SECTION, "muted", muted)
	cfg.set_value(SECTION, "locale", locale_override)
	var err: Error = cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("Settings: не удалось сохранить настройки, код " + str(err))
