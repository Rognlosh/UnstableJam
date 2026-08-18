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
const STARTING_MONEY: int = 100
const STARTING_DAY: int = 1

## Деньги игрока. Приватное поле + сеттер: любое изменение
## обязано пройти через set_money() и разослать сигнал.
var _money: int = STARTING_MONEY
## Номер текущего дня, начиная с 1.
var _day: int = STARTING_DAY

## Груз, который игрок реально везёт (купленный и ещё не проданный).
## Хранятся идентификаторы предметов из каталога, а не отображаемые имена:
## по идентификатору стадия перевозки достаёт ItemData и строит настоящее
## тело. На этапе 3 каталог переедет в .tres, а здесь ничего не изменится.
var cargo_actual: Array[StringName] = []

## Результат последнего заезда, который заполняет стадия перевозки
## и читает стадия продажи. Ключи: "delivered", "broken", "lost" (int).
## Dictionary, а не отдельный класс — на каркасе структура ещё поплывёт.
var run_result: Dictionary = {}


## Готовим состояние к новой игре. Вызывается из главного меню (этап 4),
## пока — при старте, чтобы гарантировать чистый старт при перезапуске сцены.
func reset_new_game() -> void:
	set_money(STARTING_MONEY)
	set_day(STARTING_DAY)
	cargo_actual.clear()
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
func advance_day() -> void:
	set_day(_day + 1)
	cargo_actual.clear()
	run_result.clear()
