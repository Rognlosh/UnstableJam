## Глобальное состояние игры. Живёт всё время работы приложения (autoload).
## Хранит только данные, которые должны пережить смену стадии:
## деньги, номер дня, купленный груз и результат последнего заезда.
##
## Здесь НЕТ игровой логики (физики, UI, спавна) — только состояние
## и минимальные операции над ним. Это осознанно: стадии приходят и уходят,
## а этот узел один на всю сессию, и захламлять его нельзя.
extends Node

## Сигналы. Испускаются при изменении соответствующих полей.
## UI подписывается на них и не опрашивает состояние каждый кадр.
signal money_changed(new_amount: int)
signal day_changed(new_day: int)

## Стартовые значения новой игры. Вынесены в константы,
## чтобы балансить в одном месте, а не искать по коду.
const STARTING_MONEY: int = 300
const STARTING_DAY: int = 1
## Разбег между днями в зерне генерации. Простое число, чтобы дни
## не скатывались в общий делитель.
const DAY_SEED_STEP: int = 7919

## Деньги игрока. Приватное поле + сеттер: любое изменение
## обязано пройти через set_money() и разослать сигнал.
var _money: int = STARTING_MONEY
## Номер текущего дня, начиная с 1.
var _day: int = STARTING_DAY

## Зерно партии. Задаётся один раз на новую игру, трасса каждого дня
## считается из него и номера дня — поэтому дни внутри партии разные,
## а партии не повторяют друг друга.
var run_seed: int = 0

## Склад: купленный товар, который ещё не продан. Хранятся идентификаторы
## предметов из каталога, а не отображаемые имена — по идентификатору стадия
## перевозки достаёт ItemData и строит настоящее тело. На этапе 3 каталог
## переедет в .tres, а здесь ничего не изменится.
##
## Погрузка ручная, поэтому склад и кузов — разные вещи: при старте заезда
## отсюда изымается только то, что игрок реально уложил, а остальное
## остаётся лежать и переходит на следующий день.
var cargo_actual: Array[Dictionary] = []

## Купленные прокачки: линия → номер купленной ступени. Словарь, а не список
## идентификаторов: у линии несколько ступеней, и хранить «борта уровня 3»
## отдельной записью каталога значило бы плодить их пятнадцать штук.
## Отсутствие ключа означает нулевой уровень — базу.
var upgrade_levels: Dictionary = {}


## Текущая ступень линии. Ноль — не куплено ничего.
func upgrade_level(id: StringName) -> int:
	return int(upgrade_levels.get(id, 0))


## Куплена ли прокачка хоть в каком-то виде. Остался ради лавки наставника:
## у неё одна ступень, и вопрос к ней действительно булев.
func has_upgrade(id: StringName) -> bool:
	return upgrade_level(id) > 0


## Единственная точка записи уровня. Отдельный метод, а не присваивание
## в словарь: вызывающей стороне не надо знать, чем хранилище окажется завтра.
func set_upgrade_level(id: StringName, level: int) -> void:
	upgrade_levels[id] = maxi(0, level)


## Запись склада. Метод не static намеренно: GameState — автозагрузка,
## то есть экземпляр, и статический метод, вызванный через него, даёт
## предупреждение на каждой перезагрузке скрипта.
##
## Ключ "piece" пуст у целой вещи и хранит идентификатор
## куска у осколка: без него черепки было бы не отличить от целого товара,
## и они либо пропадали бы при возврате на склад, либо размножались
## в полноценные предметы.
func cargo_entry(id: StringName, piece: StringName = &"") -> Dictionary:
	return {"id": id, "piece": piece}

## Результат последнего заезда, который заполняет стадия перевозки
## и читает стадия продажи. Ключи: "items" (список записей о каждом
## погруженном месте: "id", "ratio" — доехавшая доля цены, "start" — доля,
## с которой место тронулось, "state"), "delivered",
## "damaged", "lost", "total" (int) и "value_ratio" (float).
## Dictionary, а не отдельный класс — на каркасе структура ещё поплывёт.
var run_result: Dictionary = {}


## Готовим состояние к новой игре. Единственный вызов — кнопка «Новая игра».
func reset_new_game() -> void:
	# Старое сохранение стирается сразу, а не перезаписывается при первой
	# покупке: брось игрок новую партию на вступлении — и «Продолжить»
	# воскресило бы прошлую, которую он только что решил не продолжать.
	clear_save()
	set_money(STARTING_MONEY)
	set_day(STARTING_DAY)
	# Время в микросекундах вперемешку со случайным числом: одного времени
	# мало, два запуска подряд могут лечь слишком близко.
	run_seed = int(Time.get_ticks_usec()) ^ randi()
	cargo_actual.clear()
	upgrade_levels.clear()
	run_result.clear()


## --- Деньги ---

func get_money() -> int:
	return _money


## Единственная точка записи денег. Отсекаем уход в минус
## и уведомляем подписчиков.
func set_money(amount: int) -> void:
	var clamped: int = maxi(amount, 0)
	if clamped == _money:
		return  # ничего не изменилось — сигнал не шлём
	_money = clamped
	money_changed.emit(_money)


## Хватает ли денег на покупку. Вызывать ПЕРЕД spend_money().
func can_afford(cost: int) -> bool:
	return _money >= cost


## Тратим деньги. Возвращает false, если не хватило —
## тогда состояние не меняется вовсе.
func spend_money(cost: int) -> bool:
	if not can_afford(cost):
		return false
	set_money(_money - cost)
	return true


## Начисляем выручку.
func earn_money(amount: int) -> void:
	set_money(_money + amount)


## --- Дни ---

func get_day() -> int:
	return _day


func set_day(value: int) -> void:
	if value == _day:
		return
	_day = value
	day_changed.emit(_day)


## Переход к следующему дню: чистим то, что относилось к прошлому дню.
## Склад не трогаем: непогруженный товар никуда не девается и ждёт
## следующего рейса.
func advance_day() -> void:
	set_day(_day + 1)
	run_result.clear()


## --- Сохранение ---
##
## Хранится ровно то, что нельзя вывести заново: день, деньги, склад,
## прокачки и зерно партии. Зерно — чтобы после загрузки дорога дня осталась
## той же самой: без него игрок, вышедший на трудной трассе, возвращался бы
## на другую, и переигрывать день можно было бы до тех пор, пока не выпадет
## лёгкая.
##
## Точка сохранения одна — закуп. Заезд не сохраняется намеренно: середина
## заезда это несколько десятков тел со скоростями, а выход посреди дороги
## возвращает игрока к началу того же дня, где товар ещё лежит на складе.

const SAVE_PATH: String = "user://save.cfg"
const SAVE_SECTION: String = "run"
## Версия формата. Ломается формат — старый файл выбрасывается, а не
## читается наполовину: половина загруженной партии хуже, чем новая.
const SAVE_VERSION: int = 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "version", SAVE_VERSION)
	cfg.set_value(SAVE_SECTION, "day", _day)
	cfg.set_value(SAVE_SECTION, "money", _money)
	cfg.set_value(SAVE_SECTION, "seed", run_seed)

	# StringName переводим в String руками, а не полагаемся на сериализацию
	# словаря: тип ключа при чтении обратно восстанавливается не всегда,
	# а промах в типе ключа — это молча пустой словарь прокачек.
	var upgrades: Dictionary = {}
	for id: StringName in upgrade_levels:
		upgrades[String(id)] = int(upgrade_levels[id])
	cfg.set_value(SAVE_SECTION, "upgrades", upgrades)

	var cargo: Array = []
	for entry: Dictionary in cargo_actual:
		cargo.append([String(entry.get("id", "")), String(entry.get("piece", ""))])
	cfg.set_value(SAVE_SECTION, "cargo", cargo)

	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("GameState: не удалось сохранить партию, код " + str(err))


## Загрузка. false означает «сохранения нет или оно негодное» — вызывающая
## сторона тогда начинает новую игру, а не показывает пустой экран.
func load_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	if int(cfg.get_value(SAVE_SECTION, "version", 0)) != SAVE_VERSION:
		clear_save()
		return false

	set_day(int(cfg.get_value(SAVE_SECTION, "day", STARTING_DAY)))
	set_money(int(cfg.get_value(SAVE_SECTION, "money", STARTING_MONEY)))
	run_seed = int(cfg.get_value(SAVE_SECTION, "seed", 0))

	upgrade_levels.clear()
	var upgrades: Dictionary = cfg.get_value(SAVE_SECTION, "upgrades", {})
	for id: String in upgrades:
		upgrade_levels[StringName(id)] = int(upgrades[id])

	cargo_actual.clear()
	var cargo: Array = cfg.get_value(SAVE_SECTION, "cargo", [])
	for entry: Variant in cargo:
		var pair: Array = entry
		if pair.size() < 2:
			continue
		cargo_actual.append(cargo_entry(StringName(pair[0]), StringName(pair[1])))

	# Результат прошлого заезда не сохраняется и сохраняться не должен:
	# загрузка всегда приходится на начало дня, когда возить ещё нечего.
	run_result.clear()
	return true


func clear_save() -> void:
	if not has_save():
		return
	# Путь отдаём как есть, без globalize_path(): DirAccess понимает user://
	# сам, а в веб-сборке настоящей файловой системы под ним нет — там
	# user:// это IndexedDB, и «абсолютный» путь указывает в никуда.
	var err: Error = DirAccess.remove_absolute(SAVE_PATH)
	if err != OK:
		push_warning("GameState: не удалось удалить сохранение, код " + str(err))


## --- Генерация ---

## Зерно трассы для дня. Умножение разводит соседние дни далеко друг
## от друга, XOR подмешивает партию: день 3 в двух партиях — разные трассы,
## но внутри одной партии он всегда один и тот же, и переигровка заезда
## лёгкой дороги не выдаёт.
func track_seed_for_day(day: int) -> int:
	return run_seed ^ (day * DAY_SEED_STEP)
