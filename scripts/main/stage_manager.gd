## Менеджер стадий. Скрипт корня Main.tscn — сцены, которая живёт
## всё время игры и внутрь которой подгружаются стадии.
##
## Схема: Main никогда не выгружается, меняется только содержимое
## StageContainer. Благодаря этому переход можно затемнить, а общий HUD
## (этап 4) добавить в Main рядом с контейнером, не дублируя его в стадиях.
class_name StageManager
extends Node

## Перечисление стадий. INTRO и VICTORY — сюжетные: они лежат вне петли
## и проходятся по одному разу за партию, но грузятся тем же механизмом,
## поэтому особыми случаями внутри менеджера не становятся.
##
## MENU дописан в хвост, хотя по смыслу стоял бы первым: значения этого
## перечисления лежат в сценах (@export next_stage у сюжетных экранов),
## сохранены они числами, и вставка в начало сдвинула бы все остальные —
## «в закуп» молча превратилось бы «во вступление».
enum Stage {
	INTRO,    ## наставник ставит задачу — показывается один раз при старте
	SHOP,     ## закуп товара
	DRIVE,    ## перевозка — ядро игры
	SELL,     ## продажа и итог дня
	VICTORY,  ## лавка выкуплена — показывается один раз, петля продолжается
	MENU,     ## главное меню — стартовый экран и точка выхода из партии
}

## Сопоставление стадии и файла сцены.
## Ключ — Stage (под капотом int), значение — путь res://.
const STAGE_SCENES: Dictionary = {
	Stage.INTRO: "res://scenes/stages/IntroStage.tscn",
	Stage.SHOP: "res://scenes/stages/ShopStage.tscn",
	Stage.DRIVE: "res://scenes/stages/DriveStage.tscn",
	Stage.SELL: "res://scenes/stages/SellStage.tscn",
	Stage.VICTORY: "res://scenes/stages/VictoryStage.tscn",
	Stage.MENU: "res://scenes/stages/MenuStage.tscn",
}

## Длительность затемнения и прояснения (в секундах, каждая половина).
const FADE_DURATION: float = 0.25

## Статическая ссылка на единственный экземпляр.
## Аналог синглтона в C#. Нужна, чтобы стадии могли позвать
## StageManager.instance.change_stage(...), не выясняя своё место в дереве.
## Autoload'ом менеджер сделать нельзя: ему нужен контейнер из Main.tscn.
static var instance: StageManager = null

## Узел, внутрь которого кладётся сцена текущей стадии.
@onready var _stage_container: Node = $StageContainer
## Чёрный прямоугольник поверх всего — им и делаем затемнение.
@onready var _fade_rect: ColorRect = $FadeLayer/FadeRect

## Экземпляр текущей стадии. null, пока ничего не загружено.
var _current_stage_node: Node = null
## Какая стадия сейчас в контейнере. Нужна паузе: в главном меню
## останавливать нечего, и Esc там не должен ничего открывать.
var _current_stage: Stage = Stage.MENU
## Защита от повторного вызова смены стадии во время анимации перехода.
var _is_transitioning: bool = false


## _enter_tree() выполняется раньше _ready() и раньше, чем дети войдут
## в дерево. Ставим ссылку здесь, чтобы стадия при своём _ready()
## уже видела готовый instance.
func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	# Подчищаем за собой: иначе после смены сцены останется висеть
	# ссылка на освобождённый узел.
	if instance == self:
		instance = null


func _ready() -> void:
	# Экран стартует чёрным, чтобы первая стадия проявилась, а не моргнула.
	_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)

	# Состояние здесь не сбрасывается: этим занимается кнопка «Новая игра»
	# в меню. Сброс на старте приложения срабатывал ровно один раз за сессию,
	# и вторая партия начиналась бы с деньгами и прокачками первой.
	_load_stage(Stage.MENU)
	await _fade(0.0)


## Идёт ли сейчас переход. Пауза спрашивает: посреди перехода дерево
## в разобранном состоянии, и останавливать его нельзя.
func is_transitioning() -> bool:
	return _is_transitioning


func get_current_stage() -> Stage:
	return _current_stage


## Публичная точка входа: сменить стадию с затемнением.
## Вызов: StageManager.instance.change_stage(StageManager.Stage.DRIVE)
func change_stage(next_stage: Stage) -> void:
	if _is_transitioning:
		# Игрок успел кликнуть дважды — второй клик игнорируем,
		# иначе получим две загруженные стадии разом.
		return
	_is_transitioning = true

	await _fade(1.0)   # затемняем
	_unload_stage()
	_load_stage(next_stage)
	await _fade(0.0)   # проясняем

	_is_transitioning = false


## Загрузка сцены стадии в контейнер.
func _load_stage(stage: Stage) -> void:
	var scene_path: String = STAGE_SCENES[stage]
	# load() читает ресурс в рантайме. Для больших сцен на этапе 1
	# при необходимости перейдём на ResourceLoader.load_threaded_request().
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("StageManager: не удалось загрузить сцену " + scene_path)
		return

	_current_stage = stage
	_current_stage_node = packed.instantiate()
	_stage_container.add_child(_current_stage_node)


## Выгрузка текущей стадии.
func _unload_stage() -> void:
	if _current_stage_node == null:
		return
	# Сначала убираем из дерева, чтобы новая стадия не оказалась
	# в кадре рядом со старой, потом ставим в очередь на удаление.
	_stage_container.remove_child(_current_stage_node)
	_current_stage_node.queue_free()
	_current_stage_node = null


## Анимация прозрачности затемняющего прямоугольника.
## target_alpha: 1.0 — чёрный экран, 0.0 — полностью прозрачный.
func _fade(target_alpha: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", target_alpha, FADE_DURATION)
	# await ждёт сигнала finished — функция продолжится, когда твин доиграет.
	await tween.finished
