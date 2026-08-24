# Аудио-ассеты

`sfx/` — короткие эффекты, **WAV 44.1 кГц / 16 бит / моно**.
`music/` — треки, **OGG Vorbis 96–112 kbps**, зацикленные.

Имена файлов — контракт: они перечислены в `SFX_LIBRARY` и `MUSIC_LIBRARY`
в `res://scripts/autoload/audio.gd`. Положил файл с нужным именем — он зазвучал,
править код не требуется. Отсутствующий файл не ошибка: слот молчит.

**При импорте:** у музыки включить «Цикл» (Loop) на вкладке «Импорт»,
у коротких эффектов — наоборот, выключить, иначе удар звенит вечно.

**MP3 не использовать:** паразитная тишина в начале файла рвёт петлю.

## Источники и лицензии

Заполнять по мере добавления файлов — список нужен на страницу itch.

| Файл | Источник | Лицензия |
|---|---|---|
| `sfx/cargo_hit_wood_1.ogg` | freesound 569495, blazewasbored — «punch wood table» | **уточнить на странице** |
| `sfx/cargo_hit_wood_2.ogg` | Kenney, Impact Sounds (`impactWood_heavy_004`) | CC0 |
| `sfx/cargo_hit_clay_1.wav` | freesound 865052, imataco — «hollow hit» | **уточнить на странице** |
| `sfx/break_clay_1..4.wav` | freesound 399080, kinoton — «clay pottery drop n break»; четыре дубля из одной записи, нарезаны и выровнены по уровню | **уточнить на странице** |
| `sfx/break_wood_1.wav` | freesound 667655, deltacode — «wooden crate impact 1» | **уточнить на странице** |
| `sfx/break_glass_1.ogg` | Kenney (`glass_004`) | CC0 |
| `music/road.ogg` | Сергей, написано в FL Studio для этой игры | собственное |
| `music/shop.ogg` | Сергей, написано в FL Studio для этой игры | собственное |
| `sfx/coin_1.wav` | freesound 343462, rocotilos — «real coin drop» | **уточнить на странице** |
| `sfx/ui_click_1.ogg` | Kenney, Interface Sounds (`click4`) | CC0 |
| `sfx/place_1.ogg` | Kenney, Interface Sounds (`switch3`) | CC0 |
| `sfx/cargo_hit_glass_1.wav` | freesound 672671, janzigdoplin — «bottle 7» | **уточнить на странице** |
| `sfx/engine_loop.wav` | freesound 370888, mrlindstrom — «engine foley 3 idle»; точки петли вписаны в сам файл | **уточнить на странице** |
| `sfx/engine_start_1.wav` | freesound 436786, roboroo — «diesel engine startup» | **уточнить на странице** |
| `sfx/finish_1.ogg` | Kenney, Jingles (`jingles_SAX10`) | CC0 |

Файлы с freesound требуют проверки: там встречается и CC0, и CC BY —
у второго нужна строка с автором на странице itch. Лицензия смотрится
на странице самого звука, номер в имени файла — его идентификатор.
