extends Node
## The day. Autoloaded as `DayClock`.
##
## Everything that should care what time it is reads this: the colour of the
## sky, how much light the sun gives, and what is allowed to spawn. One day is
## twenty real minutes, split evenly between light and dark, which is long
## enough to get something done and short enough that night is not a wait.

signal day_broke(day: int)
signal night_fell(day: int)

const DAY_SECONDS := 1200.0

## Fractions of a day. 0.0 is midnight.
const DAWN := 0.25
const DUSK := 0.75
## How long sunrise and sunset take to happen, as a fraction of a day.
const TWILIGHT := 0.05

## Starts mid morning, so a new world gives you a working day before dark.
const START := 0.32

var time := START      ## 0.0 to 1.0 through the day
var day := 1
var paused := false

var _was_night := false


func _process(delta: float) -> void:
	if paused:
		return
	advance(delta)


## Separated from _process so tests can move time without waiting for it.
func advance(seconds: float) -> void:
	time += seconds / DAY_SECONDS
	while time >= 1.0:
		time -= 1.0
		day += 1
	_announce()


func set_time(fraction: float) -> void:
	time = fposmod(fraction, 1.0)
	_announce()


func _announce() -> void:
	var night := is_night()
	if night == _was_night:
		return
	_was_night = night
	if night:
		night_fell.emit(day)
	else:
		day_broke.emit(day)


func is_night() -> bool:
	return time < DAWN or time >= DUSK


## 0.0 in full dark, 1.0 in full daylight, sliding through twilight. This is
## what the sky and the sunlight are scaled by, so both change together.
func daylight() -> float:
	if time < DAWN - TWILIGHT or time >= DUSK + TWILIGHT:
		return 0.0
	if time < DAWN:
		return smoothstep(0.0, 1.0, (time - (DAWN - TWILIGHT)) / TWILIGHT)
	if time < DUSK:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (time - DUSK) / TWILIGHT)


## "07:30". The HUD and the debug overlay show this.
func clock_text() -> String:
	var minutes := int(time * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
