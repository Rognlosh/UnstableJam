## Стадия продажи: превращает итог заезда в деньги и закрывает день.
##
## Строка сводки — это МЕСТО, а не тип товара: каждая погруженная вещь
## получает свою полосу. Ваза, поехавшая целой, остаётся вазой, даже если
## приехала грудой черепков, а черепок со склада — отдельное место со своим
## потенциалом. Иначе обещание строки врёт: четыре черепка и одна ваза
## сулили бы 250 монет при физическом потолке в 90.
extends Control

@export var header_label: Label
@export var rows_container: VBoxContainer
@export var empty_label: Label
@export var gross_label: Label
@export var time_label: Label
@export var total_label: Label
@export var money_label: Label
@export var next_day_button: Button
## Сцена строки сводки. Через @export, а не preload: сцену видно
## в инспекторе и её можно подменить, не открывая скрипт.
@export var row_scene: PackedScene

## Сколько времени отводится на выкат всех строк разом. Интервал между
## строками — производная от него: три места выкатываются вальяжно,
## двадцать — сплошной волной, и в обоих случаях экран не задерживает
## игрока. Фиксированный интервал на длинном списке превратился бы
## в полминуты ожидания.
const ROWS_BUDGET: float = 1.2
## Потолок интервала: на коротком списке бюджет делить не на что,
## и без потолка две строки расползлись бы на полсекунды друг от друга.
const ROW_GAP_MAX: float = 0.3
const ROW_FADE: float = 0.12
const ROW_FILL: float = 0.35
const PAUSE: float = 0.3
const TOTAL_TIME: float = 0.4
const LATE_TIME: float = 0.5
const MONEY_TIME: float = 0.4
## Во сколько раз ускоряется показ при пропуске. Ускорение, а не остановка
## твина: все колбэки отработают в свой черёд, и конечное состояние
## сойдётся само — руками его расставлять не надо.
const SKIP_SPEED: float = 40.0

## Порядок товара в каталоге: id → номер. Нужен сортировке строк и строится
## один раз за показ экрана, чтобы не искать предмет в массиве на каждое
## сравнение — сортировка зовёт компаратор куда чаще, чем есть строк.
var _catalog_order: Dictionary = {}

var _rows: Array[SellRow] = []
var _tween: Tween = null


## Числа итогового блока держим отдельными свойствами: твин присваивает
## их напрямую, а сеттер сам перерисовывает подпись. Так набегающие цифры
## не требуют ни _process, ни ручного обновления.
var shown_gross: float = 0.0:
	set(value):
		shown_gross = value
		if gross_label != null:
			gross_label.text = tr("SELL_GROSS") % int(round(value))

var shown_total: float = 0.0:
	set(value):
		shown_total = value
		if total_label != null:
			total_label.text = tr("SELL_TOTAL") % int(round(value))

var shown_money: float = 0.0:
	set(value):
		shown_money = value
		if money_label != null:
			money_label.text = tr("SELL_MONEY") % [
				int(round(value)), GameState.cargo_actual.size(),
			]


func _ready() -> void:
	next_day_button.pressed.connect(_on_next_day_pressed)
	_sell_cargo()


## Выручка считается по долям доехавшей ценности, а не по числу ящиков:
## ваза без одного донца стоит дешевле целой, но дороже нуля. Поверх этого
## ложится коэффициент за скорость: за долгую доставку платят меньше.
func _sell_cargo() -> void:
	var gross := _build_rows(_collect_places())

	# Коэффициент применяется один раз к сумме, а не к каждой строке:
	# иначе строки не сходились бы в итог из-за округления, и игрок
	# ловил бы нас на арифметике.
	var payout: float = GameState.run_result.get("payout_factor", 1.0)
	var total := int(round(float(gross) * payout))

	# Деньги начисляются сразу, до всякой анимации. Анимация показывает
	# уже случившееся, а не выполняет его: оборвись твин — состояние игры
	# всё равно верное.
	var money_before := GameState.get_money()
	GameState.earn_money(total)

	header_label.text = tr("SELL_HEADER") % GameState.get_day()
	time_label.text = tr("SELL_TIME") % int(GameState.run_result.get("run_time", 0.0))
	shown_gross = 0.0
	shown_total = 0.0
	shown_money = float(money_before)
	# Кнопка проявляется в конце: пока числа бегут, ей нечего подтверждать,
	# а нажатая раньше времени она увела бы игрока с недосчитанного экрана.
	# Именно прозрачность, а не hide(): скрытый узел выпадает из раскладки,
	# и в конце весь итоговый блок дёрнулся бы вниз на высоту кнопки.
	next_day_button.modulate.a = 0.0
	next_day_button.disabled = true

	_play(gross, total, payout)


## Показ итога. Порядок продуман: сначала строки с набегающим итогом
## за товар, потом выручка, и только потом — штраф за опоздание отдельным
## ударом. Покажи мы уменьшенную сумму сразу, штраф не ощущался бы вовсе;
## а когда деньги на глазах утекают, в следующий раз игрок поедет быстрее.
func _play(gross: int, total: int, payout: float) -> void:
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var gap: float = minf(ROW_GAP_MAX, ROWS_BUDGET / maxf(float(_rows.size()), 1.0))
	var rows_span: float = maxf(gap * float(_rows.size() - 1) + ROW_FILL, 0.001)
	# Пустой интервал держит длину блока строк: всё остальное в блоке
	# идёт параллельно ему, а следующий шаг ждёт самой поздней строки.
	_tween.tween_interval(rows_span)
	for i in _rows.size():
		var row := _rows[i]
		var delay := gap * float(i)
		_tween.parallel().tween_property(row, "modulate:a", 1.0, ROW_FADE) \
			.from(0.0).set_delay(delay)
		_tween.parallel().tween_property(row, "fill_ratio", row.target_ratio(),
			ROW_FILL).set_delay(delay)
		_tween.parallel().tween_property(row, "shown_revenue",
			float(row.revenue()), ROW_FILL).set_delay(delay)
	# Итог за товар растёт одной непрерывной линией через весь блок строк,
	# а не рывками по строке: рывки читались бы как сбой счётчика.
	_tween.parallel().tween_property(self, "shown_gross", float(gross), rows_span)

	_tween.tween_interval(PAUSE)
	_tween.tween_property(self, "shown_total", float(gross), TOTAL_TIME)

	if payout < 1.0:
		_tween.tween_interval(PAUSE)
		_tween.tween_callback(_show_late.bind(payout))
		_tween.tween_property(self, "shown_total", float(total), LATE_TIME)

	_tween.tween_callback(_bump_money)
	_tween.parallel().tween_property(self, "shown_money",
		float(GameState.get_money()), MONEY_TIME)
	_tween.tween_callback(_reveal_button)


func _reveal_button() -> void:
	next_day_button.disabled = false
	create_tween().tween_property(next_day_button, "modulate:a", 1.0, 0.2)


## Штраф за опоздание объявляется в тот же миг, когда сумма поехала вниз:
## без подписи игрок увидит только меньшее число и не поймёт, за что.
func _show_late(payout: float) -> void:
	time_label.text = tr("SELL_TIME_LATE") % [
		int(GameState.run_result.get("run_time", 0.0)),
		int(round(payout * 100.0)),
	]


## Подскок счётчика денег вместо летящих монет: монета — это спрайт,
## которого пока нет. Когда появится, полёт добавится в эту же точку.
func _bump_money() -> void:
	# Точка отсчёта масштаба — центр метки, иначе она растёт вправо-вниз
	# и уползает из строки. Размер известен только после раскладки,
	# поэтому берём его здесь, а не в _ready().
	money_label.pivot_offset = money_label.size * 0.5
	var bump := create_tween().set_trans(Tween.TRANS_SINE)
	bump.tween_property(money_label, "scale", Vector2(1.12, 1.12), 0.12)
	bump.tween_property(money_label, "scale", Vector2.ONE, 0.12)


## Пропуск: экран продажи игрок увидит десяток раз за сессию, и на третий
## раз анимация из награды превращается в задержку.
func _unhandled_input(event: InputEvent) -> void:
	if _tween == null or not _tween.is_running():
		return
	var skip := event.is_action_pressed(&"ui_accept")
	if not skip:
		# Через приведение, а не через "is ... and event.pressed": у базового
		# InputEvent поля pressed нет, обращение к нему читается как Variant,
		# и всё выражение теряет тип.
		var click := event as InputEventMouseButton
		skip = click != null and click.pressed
	if skip:
		_tween.set_speed_scale(SKIP_SPEED)
		get_viewport().set_input_as_handled()


## Записи заезда → список мест, готовых к показу. Монеты считаем здесь,
## один раз на место: сортировка идёт уже по готовым числам, и округление
## не зависит от того, в каком порядке строки встали.
func _collect_places() -> Array[Dictionary]:
	# get() со значением по умолчанию — на случай, если стадию открыли
	# в обход перевозки (например, запустив сцену напрямую из редактора).
	var entries: Array = GameState.run_result.get("items", [])
	var places: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var data := ItemCatalog.get_by_id(entry.get("id", &""))
		if data == null:
			continue
		var start: float = entry.get("start", 1.0)
		var price := float(data.base_price)
		places.append({
			"data": data,
			# Стартовая доля меньше единицы бывает только у черепка:
			# целую вещь грузят целиком или не грузят вовсе.
			"pieces": not is_equal_approx(start, 1.0),
			"revenue": int(round(price * float(entry.get("ratio", 0.0)))),
			"potential": int(round(price * start)),
			"order": int(_order_of(data.id)),
		})
	places.sort_custom(_compare_places)
	return places


## Строки в порядке: товар по каталогу → целые перед осколками → дороже
## перед дешевле. Так уцелевшее собирается сверху, а потери сползают вниз
## и читаются одной группой, а не вперемешку.
static func _compare_places(a: Dictionary, b: Dictionary) -> bool:
	if a["order"] != b["order"]:
		return a["order"] < b["order"]
	if a["pieces"] != b["pieces"]:
		return not bool(a["pieces"])
	return int(a["revenue"]) > int(b["revenue"])


## Возвращает выручку до коэффициента за время.
func _build_rows(places: Array[Dictionary]) -> int:
	if row_scene == null:
		push_error("SellStage: не назначена сцена строки сводки")
		return 0
	var gross := 0
	for place: Dictionary in places:
		gross += int(place["revenue"])
		var row := row_scene.instantiate() as SellRow
		if row == null:
			push_error("SellStage: сцена строки сводки — не SellRow")
			return gross
		# Сначала в дерево, потом настройка: узлы строки приходят
		# из @export и резолвятся только при входе в дерево.
		rows_container.add_child(row)
		row.setup(place["data"], place["revenue"], place["potential"],
			place["pieces"])
		# setup() показывает готовый итог — это верно для экрана без
		# анимации. Раз анимация есть, отматываем строку в начало.
		row.rewind()
		row.modulate.a = 0.0
		_rows.append(row)
	# Пустая сводка бывает не только при проигрыше: стадию можно открыть
	# напрямую из редактора, и тогда пустой экран без подписи читается
	# как поломка.
	empty_label.visible = places.is_empty()
	return gross


## Номер товара в каталоге. Индекс строится лениво: экран открывается раз
## в день, и платить за него при загрузке сцены незачем.
func _order_of(id: StringName) -> int:
	if _catalog_order.is_empty():
		var index := 0
		for data: ItemData in ItemCatalog.all_items():
			_catalog_order[data.id] = index
			index += 1
	return int(_catalog_order.get(id, _catalog_order.size()))


func _on_next_day_pressed() -> void:
	GameState.advance_day()
	StageManager.instance.change_stage(StageManager.Stage.SHOP)
