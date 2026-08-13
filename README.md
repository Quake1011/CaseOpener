# CaseOpener

Плагин кейсов для CS:GO на SourceMod. Поддерживает старую команду из
`Opener.ini` и новые ежедневные, еженедельные и пользовательские типы кейсов.

## Совместимость

- SourceMod 1.10, 1.11, 1.12 и 1.13.
- SourcePawn-код использует API, доступные начиная с SM 1.10.
- Требуется Shop-Core.
- VIP Core, Levels Ranks и FirePlayersStats подключаются опционально.
- Нельзя одновременно компилировать с `lvl_ranks.inc` и `FirePlayersStats.inc`.
- База данных: MySQL или SQLite.

Плагин проверен локально компиляторами SM 1.10 и 1.11 в вариантах без
опциональных модулей, с VIP Core, с Levels Ranks, с FirePlayersStats и с VIP
Core + одним из статистических модулей. Релизы SM 1.12/1.13 сохраняют этот
совместимый API; для финальной сборки используйте `spcomp` той версии, которая
установлена на сервере.

## Установка

1. Скопируйте содержимое `addons/` в каталог игры.
2. Добавьте секцию `case_opener` в `addons/sourcemod/configs/databases.cfg`:

```text
"case_opener"
{
    "driver"   "sqlite"
    "database" "case_opener"
}
```

3. Для MySQL замените параметры `driver`, `host`, `database`, `user` и `pass`.
4. Установите `CaseOpener.smx` в `addons/sourcemod/plugins/`.
5. Проверьте `cfg/sourcemod/CaseOpener.cfg`, который создаётся автоматически.

Если база временно недоступна, плагин не выгружается: функции, требующие
сохранения прогресса, сообщают об ошибке и записывают причину в лог.

## Типы кейсов и награды

Настройки находятся в `addons/sourcemod/configs/CaseOpenerCases.ini`.

- `daily` — ежедневный кейс с cooldown 86400 секунд.
- `weekly` — еженедельный кейс с cooldown 604800 секунд.
- Можно добавить до 8 типов с собственным `name`, `model` и cooldown.
- `*_chance` — относительные веса выпадения наград.
- `streak_required` и `streak_bonus_percent` задают бонус серии.
- `shop_category`/`shop_item` выдают предмет Shop-Core.
- `vip_group`/`vip_time` выдают временный VIP.
- `xp_multiplier` увеличивает XP-награду при выпадении соответствующего типа.
- `extra_cases` добавляет дополнительные открытия без изменения основного cooldown.

Старая конфигурация VIP и алиасы команд остаются в `Opener.ini`.

## Команды игроков

- `!dailycase` — открыть ежедневный кейс.
- `!weeklycase` — открыть еженедельный кейс.
- `!case_open <id>` — открыть тип из `CaseOpenerCases.ini`.
- `!case_menu` или `!case_info` — меню кейсов, cooldown, шансы и награды.
- Старые команды `!case`, `!drop`, `!reward` и команды из `Opener.ini` сохраняются.

## Команды администратора

Требуется `ADMFLAG_ROOT`:

- `sm_case_give <target> <case> [count]` — выдать дополнительные открытия.
- `sm_case_take <target> <case> [count]` — отозвать дополнительные открытия.
- `sm_case_stats [target]` — показать streak, cooldown, дополнительные кейсы и число открытий.
- `sm_case_export <json|csv>` — экспортировать статистику в `addons/sourcemod/data/CaseOpener/`.

Экспортный JSON/CSV можно использовать внешней панелью без прямого доступа к
базе данных.

## Эксплуатация

Основные ConVar:

- `sm_opener_sounds` — звуки.
- `sm_opener_effects` — визуальные эффекты и beam.
- `sm_opener_notifications` — сообщения чата и hint.
- `sm_opener_log` — логирование выпадений и отказов.

Имя игрока обновляется в базе при каждом подключении. Переводы находятся в
`addons/sourcemod/translations/CaseOpener.phrases.txt` и включают RU/EN для
новых уведомлений.
