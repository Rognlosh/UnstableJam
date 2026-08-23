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

## Расширения, которые пробуются по очереди. Пути в каталогах — без расширения:
## звук может прийти из библиотеки хоть в ogg, хоть в wav, и переписывать
## из-за этого код бессмысленно.
const AUDIO_EXTENSIONS: PackedStringArray = [".wav", ".ogg"]

## Каталог эффектов: ключ → варианты. Вариант выбирается случайно.
## Массив из одного элемента — нормально, разброс тона всё равно работает.
const SFX_LIBRARY: Dictionary = {
	&"break_glass": [
		"res://assets/audio/sfx/break_glass_1",
		"res://assets/audio/sfx/break_glass_2",
		"res://assets/audio/sfx/break_glass_3",
	],
	&"break_clay": [
		"res://assets/audio/sfx/break_clay_1",
		"res://assets/audio/sfx/break_clay_2",
		"res://assets/audio/sfx/break_clay_3",
	],
	&"break_wood": [
		"res://assets/audio/sfx/break_wood_1",
		"res://assets/audio/sfx/break_wood_2",
	],
	# Общий стук: он же звук удара о доски кузова, он же запасной вариант
	# для материалов, которым своего набора не записали.
	&"cargo_hit": [
		"res://assets/audio/sfx/cargo_hit_1",
		"res://assets/audio/sfx/cargo_hit_2",
	],
	&"cargo_hit_wood": [],  # дерево — это и есть кузов, свои файлы не нужны
	&"cargo_hit_clay": ["res://assets/audio/sfx/cargo_hit_clay_1"],
	&"cargo_hit_glass": ["res://assets/audio/sfx/cargo_hit_glass_1"],
	&"dust": ["res://assets/audio/sfx/dust_1"],
	&"explosion": [
		"res://assets/audio/sfx/explosion_1",
		"res://assets/audio/sfx/explosion_2",
	],
	&"pickup": ["res://assets/audio/sfx/pickup_1"],
	&"place": ["res://assets/audio/sfx/place_1"],
	&"coin": [
		"res://assets/audio/sfx/coin_1",
		"res://assets/audio/sfx/coin_2",
	],
	&"ui_click": ["res://assets/audio/sfx/ui_click_1"],
	&"ui_denied": ["res://assets/audio/sfx/ui_denied_1"],
	&"finish": ["res://assets/audio/sfx/finish_1"],
	&"penalty": ["res://assets/audio/sfx/penalty_1"],
}

## Куда падать, если для ключа не нашлось ни одного файла. Цепочка
## разрешается по шагам, так что стекло через глину дотягивается до общего
## стука. Благодаря этому материал заводится в предметах раньше, чем найден
## звук: пока файла нет, вещь звучит ближайшим родственником.
##
## Порядок родства выбран по слуху, а не по физике: звонкое ближе к звонкому,
## глухое к глухому. Стекло падает в глину, а не в дерево, потому что
## черепок и осколок звучат похоже, а доска — нет.
const SFX_FALLBACK: Dictionary = {
	&"cargo_hit_wood": &"cargo_hit",
	&"cargo_hit_clay": &"cargo_hit",
	&"cargo_hit_glass": &"cargo_hit_clay",
	&"break_wood": &"break_clay",
	&"break_clay": &"break_glass",
}

## Группа ограничителя частоты. Отдельно от запасного варианта: там речь
## о том, какой файл взять, здесь — о том, кто с кем делит окно. Все стуки
## груза считаются одним потоком, иначе глина, дерево и стекло получили бы
## по своему окну и вместе застучали бы втрое чаще.
const SFX_GROUP: Dictionary = {
	&"cargo_hit_wood": &"cargo_hit",
	&"cargo_hit_clay": &"cargo_hit",
	&"cargo_hit_glass": &"cargo_hit",
}

## Отдельные окна для тех ключей, которым мало умолчания.
## Ключ здесь — группа, а не отдельный звук.
const SFX_COOLDOWN: Dictionary = {
	&"cargo_hit": 0.06,
}

## Каталог зацикленных эффектов. Отдельно от SFX_LIBRARY: петля живёт
## на своём плеере у того, кто её завёл (мотор — у грузовика), а не в общем
## пуле, где её в любой момент вытеснил бы очередной звяк.
const LOOP_LIBRARY: Dictionary = {
	&"engine": ["res://assets/audio/sfx/engine_loop"],
}

## Каталог музыки. Один файл на ключ: вариантов у трека не бывает.
const MUSIC_LIBRARY: Dictionary = {
	&"road": "res://assets/audio/music/road",
	&"shop": "res://assets/audio/music/shop",
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
	var group: StringName = SFX_GROUP.get(key, key)
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var window: float = float(SFX_COOLDOWN.get(group, DEFAULT_COOLDOWN))
	if now - float(_last_played.get(group, -999.0)) < window:
		return null

	var stream: AudioStream = _pick_with_fallback(key)
	if stream == null:
		return null

	var voice: AudioStreamPlayer = _free_voice()
	if voice == null:
		# Все голоса заняты. Молча пропускаем: отобрать чужой звук —
		# значит услышать обрыв, а он заметнее пропажи.
		return null

	_last_played[group] = now
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


## Идёт по цепочке родства, пока не найдёт хоть один существующий файл.
## Счётчик шагов — страховка от кольца в SFX_FALLBACK: опечатка там иначе
## подвесила бы игру намертво.
func _pick_with_fallback(key: StringName) -> AudioStream:
	var current: StringName = key
	for _step: int in 4:
		var stream: AudioStream = _pick(current)
		if stream != null:
			return stream
		if not SFX_FALLBACK.has(current):
			return null
		current = SFX_FALLBACK[current]
	return null


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


## Грузит поток по пути без расширения, перебирая AUDIO_EXTENSIONS.
## Промах кэшируется как null — иначе каждый удар груза дёргал бы
## файловую систему заново.
func _stream(base_path: String) -> AudioStream:
	if _cache.has(base_path):
		return _cache[base_path]
	var stream: AudioStream = null
	for ext: String in AUDIO_EXTENSIONS:
		var path: String = base_path + ext
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			break
	_cache[base_path] = stream
	return stream


func _free_voice() -> AudioStreamPlayer:
	for voice: AudioStreamPlayer in _voices:
		if not voice.playing:
			return voice
	return null


## Поток для зацикленного эффекта или null, если файла нет. Плеер под него
## заводит вызывающий: петле нужна своя жизнь, привязанная к объекту, который
## её издаёт.
##
## Зацикливание задаётся при импорте файла, а не здесь: включать его кодом
## значит править общий ресурс, а он один на всех, кто его загрузил.
func loop_stream(key: StringName) -> AudioStream:
	for path: String in LOOP_LIBRARY.get(key, []):
		var stream: AudioStream = _stream(path)
		if stream != null:
			return stream
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
