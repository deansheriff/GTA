extends Node
## Autoload "Clock": in-game time. Default pace: 1 real second = 1 game minute (a day is 24 min).
## Drives day/night, shop hours, job windows and the NEPA schedule.

signal minute_passed(total_minutes: int)
signal hour_changed(hour: int)
signal day_changed(day: int)

const DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

var minutes := 7 * 60 # total game minutes since the start (day 1, 07:00)
var pace := 1.0 # game minutes per real second
var paused := false
var _acc := 0.0


func _process(delta: float) -> void:
	if paused:
		return
	_acc += delta * pace
	while _acc >= 1.0:
		_acc -= 1.0
		_tick()


func _tick() -> void:
	var old_hour := hour()
	var old_day := day()
	minutes += 1
	minute_passed.emit(minutes)
	if hour() != old_hour:
		hour_changed.emit(hour())
	if day() != old_day:
		day_changed.emit(day())


## Jump forward (sleeping, cutscenes). Emits hour/day changes once at the end.
func advance(game_minutes: int) -> void:
	var old_day := day()
	minutes += game_minutes
	hour_changed.emit(hour())
	if day() != old_day:
		day_changed.emit(day())


func day() -> int:
	return minutes / 1440 + 1


func hour() -> int:
	return (minutes % 1440) / 60


func minute() -> int:
	return minutes % 60


func weekday() -> String:
	return DAYS[day() % 7] # day 1 is a Monday


func is_night() -> bool:
	return hour() >= 19 or hour() < 6


## 0 = full day, 1 = full night; smooth through dusk (18–19:30) and dawn (5–6:30).
func darkness() -> float:
	var h := float(minutes % 1440) / 60.0
	if h >= 19.5 or h < 5.0:
		return 1.0
	if h >= 18.0:
		return (h - 18.0) / 1.5
	if h < 6.5:
		return 1.0 - (h - 5.0) / 1.5
	return 0.0


func label() -> String:
	return "%s %02d:%02d · Day %d" % [weekday().left(3), hour(), minute(), day()]


func to_dict() -> Dictionary:
	return { "minutes": minutes }


func from_dict(d: Dictionary) -> void:
	minutes = int(d.get("minutes", minutes))
