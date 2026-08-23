## Автозагрузка Audio — единственная точка воспроизведения звука в игре.
##
## Эффекты идут через пул плееров на шине SFX, музыка — через пару плееров
## на шине Music с кроссфейдом между ними. Громкость обеих шин крутит
## автозагрузка Settings, здесь она не трогается вовсе.
##
## Файлы подключаются по контракту имён из SFX_LIBRARY и MUSIC_LIBRARY:
## положил файл с нужным именем — он зазвучал, править код не требуется.
## Отсутствующий файл — не ошибка: слот молчит, игра работает.
##
## Загрузка ленивая, а не через preload, вопреки общему правилу проекта:
## preload разрешается при разборе скрипта, и путь к ещё не положенному
## файлу уронил бы компиляцию — то есть игра не запускалась бы, пока
## не записан последний звук.
extends Node

const BUS_SFX: StringName = &"SFX"
const BUS_MUSIC: StringName = &"Music"

## Сколько эффектов может звучать одновременно. Двенадцать — это с запасом
## под разбитие нескольких вещей разом; больше сливается в кашу и клиппит.
const SFX_VOICES: int = 12
## Разброс высоты тона на каждое срабатывание, доля. Без него четыре удара
## подряд слышны как один семпл, проигранный четырежды, — а это и есть
## главный признак дешёвого звука.
const PITCH_SPREAD: float = 0.08
## Пауза между двумя срабатываниями одного ключа. Один контакт физики длится
## несколько кадров, и без окна получилась бы очередь.
const DEFAULT_COOLDOWN: float = 0.04
## Длительность кроссфейда музыки.
const MUSIC_FADE: float = 1.2
## Уровень «выключено» для музыкального плеера.
const SILENT_DB: float = -60.0

## Каталог эффектов: ключ → варианты. Вариант выбирается случайно.
## Массив из одного элемента — нормально, разброс тона всё равно работает.
const SFX_LIBRARY: Dictionary = {
	&"break_glass": [
		"res://assets/audio/sfx/break_glass_1.wav",
		"res://assets/audio/sfx/break_glass_2.wav",
		"res://assets/audio/sfx/break_glass_3.wav",
	],
	&"break_clay": [
		"res://assets/audio/sfx/break_clay_1.wav",
		"res://assets/audio/sfx/break_clay_2.wav",
		"res://assets/audio/sfx/break_clay_3.wav",
	],
	&"cargo_hit": [
		"res://assets/audio/sfx/cargo_hit_1.wav",
		"res://assets/audio/sfx/cargo_hit_2.wav",
		"res://assets/audio/sfx/cargo_hit_3.wav",
		"res://assets/audio/sfx/cargo_hit_4.wav",
	],
	&"dust": ["res://assets/audio/sfx/dust_1.wav"],
	&"explosion": [
		"res://assets/audio/sfx/explosion_1.wav",
		"res://assets/audio/sfx/explosion_2.wav",
	],
	&"pickup": ["res://assets/audio/sfx/pickup_1.wav"],
	&"place": ["res://assets/audio/sfx/place_1.wav"],
	&"coin": [
		"res://assets/audio/sfx/coin_1.wav",
		"res://assets/audio/sfx/coin_2.wav",
	],
	&"ui_click": ["res://assets/audio/sfx/ui_click_1.wav"],
	&"ui_denied": ["res://assets/audio/sfx/ui_denied_1.wav"],
	&"finish": ["res://assets/audio/sfx/finish_1.wav"],
	&"penalty": ["res://assets/audio/sfx/penalty_1.wav"],
}

## Отдельные окна для тех ключей, которым мало умолчания.
const SFX_COOLDOWN: Dictionary = {
	&"cargo_hit": 0.06,
}

## Каталог музыки. Один файл на ключ: вариантов у трека не бывает.
const MUSIC_LIBRARY: Dictionary = {
	&"road": "res://assets/audio/music/road.ogg",
	&"shop": "res://assets/audio/music/shop.ogg",
}

var _voices: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_slot: int = 0
var _music_key: StringName = &""
var _music_tween: Tween

## Путь → поток. null означает «файла нет», и это тоже результат:
## без него каждый удар груза дёргал бы файловую систему заново.
var _cache: Dictionary = {}
## Ключ → время последнего срабатывания, в секундах от старта игры.
var _last_played: Dictionary = {}


func _ready() -> void:
	# Музыка обязана доигрывать на паузе, а кроссфейд — двигаться:
	# твин принадлежит этому узлу и встал бы вместе с деревом.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i: int in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS_SFX
		add_child(voice)
		_voices.append(voice)

	for i: int in 2:
		var track := AudioStreamPlayer.new()
		track.bus = BUS_MUSIC
		track.volume_db = SILENT_DB
		add_child(track)
		_music.append(track)


## --- Эффекты ---

## Проиграть эффект по ключу. volume_db — поправка на силу события
## (удар груза тем громче, чем сильнее), 0.0 означает «как записано».
## Возвращает занятый плеер или null, если играть было нечего.
func play(key: StringName, volume_db: float = 0.0) -> AudioStreamPlayer:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var window: float = float(SFX_COOLDOWN.get(key, DEFAULT_COOLDOWN))
	if now - float(_last_played.get(key, -999.0)) < window:
		return null

	var stream: AudioStream = _pick(key)
	if stream == null:
		return null

	var voice: AudioStreamPlayer = _free_voice()
	if voice == null:
		# Все голоса заняты. Молча пропускаем: отобрать чужой звук —
		# значит услышать обрыв, а он заметнее пропажи.
		return null

	_last_played[key] = now
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	voice.play()
	return voice


## Оборвать все эффекты. Зовётся при смене стадии: иначе хвост разбития
## тянется в экран продажи, где ему делать нечего.
func stop_sfx() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()


func _pick(key: StringName) -> AudioStream:
	var paths: Array = SFX_LIBRARY.get(key, [])
	if paths.is_empty():
		return null
	# Промахи (файла нет) остаются в кэше как null, поэтому перебор дешёвый.
	var found: Array[AudioStream] = []
	for path: String in paths:
		var stream: AudioStream = _stream(path)
		if stream != null:
			found.append(stream)
	if found.is_empty():
		return null
	return found[randi() % found.size()]


func _stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	_cache[path] = stream
	return stream


func _free_voice() -> AudioStreamPlayer:
	for voice: AudioStreamPlayer in _voices:
		if not voice.playing:
			return voice
	return null


## --- Музыка ---

## Включить трек по ключу с кроссфейдом. Повторный вызов с тем же ключом
## ничего не делает: возврат в закуп не должен отматывать музыку на начало.
func play_music(key: StringName) -> void:
	if key == _music_key:
		return
	var path: String = String(MUSIC_LIBRARY.get(key, ""))
	var stream: AudioStream = _stream(path) if not path.is_empty() else null
	_music_key = key if stream != null else &""

	var outgoing: AudioStreamPlayer = _music[_music_slot]
	_music_slot = 1 - _music_slot
	var incoming: AudioStreamPlayer = _music[_music_slot]

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)

	if stream != null:
		incoming.stream = stream
		incoming.volume_db = SILENT_DB
		incoming.play()
		_music_tween.tween_property(incoming, "volume_db", 0.0, MUSIC_FADE)

	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, MUSIC_FADE)
		# Останавливаем после затухания, иначе плеер тратит голос впустую.
		_music_tween.chain().tween_callback(outgoing.stop)


func stop_music() -> void:
	play_music(&"")
