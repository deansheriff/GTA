class_name Abilities
extends Node
## Hero meters and abilities (docs/story/03-abilities-progression.md):
##   Tunde: Blood Pressure, Go-Slow Whisperer, Conductor Combo (calls via Sule)
##   Aunty Boss: Aura, The Stare, Ajo Network (free keke rides)
##   KC: Battery + Hype, Film, Go Live
## Rules live here; the game asks for effects (traffic_scale, ghost) and shows UI.

signal used(ability: String, detail: String)
signal message(text: String)
signal changed

const CALLS := {
	"change": "Enter with your change!",
	"hold": "Hold door!",
	"duck": "Duck!",
	"vip": "Owambe guests, VIP!",
	"last": "Last bus!",
}
const HERO_ABILITIES := {
	"tunde": ["whisperer", "conductor"],
	"ngozi": ["stare", "ajo"],
	"kc": ["film", "golive", "gist"],
}
const LABELS := { "whisperer": "Whisper", "conductor": "Sule", "stare": "Stare", "ajo": "Ajo keke", "film": "Film", "golive": "Go Live", "gist": "Gist" }
## Abilities taught in the Prologue are available from the start.
const BASE_TIER := { "conductor": 1, "stare": 1, "film": 1 }
const COOLDOWN := { "whisperer": 45.0, "conductor": 6.0, "stare": 20.0, "film": 0.3, "golive": 2.0, "ajo": 1.0, "gist": 5.0 }
const GISTS := ["KC: \"Gist: Barrister Ledger was seen buying a BIGGER briefcase.\"", "KC: \"Gist: Pepper and Salt had a jollof cook-off. Nobody won. Everybody ate.\"", "KC: \"Gist: the Chief's 'Light for All' billboard is lit by… a generator.\"", "KC: \"Gist: Teacher marked the Chief's manifesto. He got an F.\""]
const WAHALA := ["\"Oga, who taught you how to drive?! Come down! Come down let's settle it!\"", "\"You don't know who I am? I'M THE ROAD!\"", "\"My BP don reach heaven! Everybody hold body!\""]
const PROVERBS := ["Tunde: \"Go-slow is temporary. Lagos is permanent.\"", "Tunde: \"The road that has no potholes has no stories.\"", "Tunde: \"If you rush, you will reach the go-slow first.\""]

var cooldowns := {}
var whisper_t := 0.0
var wahala_t := 0.0
var filming := false
var live := false
var _smooth_t := 0.0
var _drive_t := 0.0
var _rally_t := 0.0
var _ajo_day := -1
var ajo_used := 0
var gist_used := 0


func tier(a: String) -> int:
	return maxi(Story.tier(a), int(BASE_TIER.get(a, 0)))


func available(a: String) -> bool:
	if tier(a) <= 0:
		return false
	if Life.hero == "kc" and a in ["film", "golive"] and float(Life.stats.get("battery", 0.0)) <= 0.0:
		return false
	return true


func cooldown(a: String) -> float:
	return float(cooldowns.get(a, 0.0))


func traffic_scale() -> float:
	return 0.35 if whisper_t > 0.0 else 1.0


## Ghosting through traffic while the Whisperer shows the gaps.
func ghost() -> bool:
	return whisper_t > 0.0


func in_wahala() -> bool:
	return wahala_t > 0.0


## ctx: {mode, stuck, moving, crashed, at_home, nepa_on}
func tick(dt: float, ctx: Dictionary) -> void:
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, float(cooldowns[k]) - dt)
	if whisper_t > 0.0:
		whisper_t -= dt
	if _rally_t > 0.0:
		_rally_t -= dt
	match Life.hero:
		"tunde":
			_tick_bp(dt, ctx)
		"kc":
			_tick_battery(dt, ctx)
	if _ajo_day != Clock.day():
		_ajo_day = Clock.day()
		ajo_used = 0
		gist_used = 0


func _tick_bp(dt: float, ctx: Dictionary) -> void:
	var bp := float(Life.stats.get("bp", 20.0))
	var control := 1.0 - 0.1 * float(Story.flag("bp_control") if Story.flag("bp_control") != null else 0)
	if wahala_t > 0.0:
		wahala_t -= dt
		if wahala_t <= 0.0:
			bp = 55.0
			message.emit("Tunde: \"…Okay. I'm calm. I'm calm. Baba God dey.\"")
	elif ctx.get("mode") == "driving":
		_drive_t += dt
		if ctx.get("stuck", false):
			bp += 2.0 * dt * control
			_smooth_t = 0.0
		elif ctx.get("moving", false):
			_smooth_t += dt
			if _smooth_t >= 5.0:
				bp -= 1.0 * dt
		if ctx.get("crashed", false):
			bp += 4.0 * control
		if _drive_t >= 600.0:
			_drive_t = 0.0
			bp -= 10.0
			message.emit(PROVERBS[randi() % PROVERBS.size()])
		if bp >= 100.0:
			bp = 100.0
			wahala_t = 6.0
			message.emit("WAHALA MODE! " + WAHALA[randi() % WAHALA.size()])
	else:
		bp -= 0.5 * dt # walking it off
	Life.stats["bp"] = clampf(bp, 0.0, 100.0)


func _tick_battery(dt: float, ctx: Dictionary) -> void:
	var b := float(Life.stats.get("battery", 60.0))
	var drain := 1.0 / 20.0
	if Story.flag("live_mission"):
		drain = 1.0 / 6.0
	if filming:
		drain += 1.0 / 4.0
	if live:
		drain += 1.0 / 2.0
	b -= drain * dt
	if ctx.get("at_home", false) and ctx.get("nepa_on", true):
		b += 1.0 * dt
	if b <= 0.0 and (filming or live):
		filming = false
		live = false
		message.emit("KC: \"Guys… guys? Phone don die.\" (Find a socket, a generator or a power bank.)")
	Life.stats["battery"] = clampf(b, 0.0, 100.0)


## Use an ability. `detail` is the Conductor call or the stared-at NPC (filled in by the game).
func use(a: String, detail := "") -> bool:
	if not available(a):
		message.emit("%s is locked for now." % LABELS.get(a, a) if tier(a) <= 0 else "Battery is dead. Charge first.")
		return false
	if cooldown(a) > 0.0:
		message.emit("%s: wait %d s" % [LABELS.get(a, a), int(ceil(cooldown(a)))])
		return false
	match a:
		"whisperer":
			whisper_t = [0.0, 4.0, 6.0, 8.0][clampi(tier(a), 0, 3)]
			message.emit("Baba God dey! The gaps dey show!")
		"conductor":
			message.emit("Sule: \"%s\"" % CALLS.get(detail, detail))
			if detail == "change":
				Life.stats["bp"] = maxf(0.0, float(Life.stats.get("bp", 20.0)) - 3.0)
		"stare":
			Life.stats["aura"] = minf(100.0, float(Life.stats.get("aura", 40.0)) + 0.5)
		"film":
			filming = not filming
			detail = "on" if filming else "off"
			message.emit("Recording… 🔴" if filming else "Saved to drafts.")
		"golive":
			live = not live
			detail = "on" if live else "off"
			if live:
				_rally_t = 10.0
				Life.stats["hype"] = minf(1000.0, float(Life.stats.get("hype", 0.0)) + 15.0)
				message.emit("KC is LIVE! Crowd gathering…")
			else:
				message.emit("Stream ended. Hype +15.")
		"ajo":
			var charges := tier(a)
			if ajo_used >= charges:
				message.emit("Ajo Network: no more free rides today.")
				return false
		"gist":
			if gist_used >= 3:
				message.emit("KC has gisted enough for today. Even WhatsApp needs rest.")
				return false
			gist_used += 1
			Life.stats["hype"] = minf(1000.0, float(Life.stats.get("hype", 0.0)) + 5.0 * float(Story.trust) / 5.0)
			Life.restore("social", 5.0)
			message.emit(GISTS[randi() % GISTS.size()])
	cooldowns[a] = float(COOLDOWN.get(a, 1.0)) * (0.5 if a == "conductor" and tier(a) >= 2 else 1.0)
	used.emit(a, detail)
	changed.emit()
	return true


func stare_seconds() -> float:
	return 3.0 * (1.0 + float(Life.stats.get("aura", 40.0)) / 100.0)


func rallying() -> bool:
	return _rally_t > 0.0 and live


## Free keke ride from the Ajo Network (consumes a daily charge).
func spend_ajo() -> void:
	ajo_used += 1
	changed.emit()


func reset_for_hero() -> void:
	filming = false
	live = false
	whisper_t = 0.0
	wahala_t = 0.0
	changed.emit()
