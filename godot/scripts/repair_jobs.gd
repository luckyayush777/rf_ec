extends Node
## The shop's work: repair requests on the computer's job board, the bench queue, the delivery
## box, and payment when a card goes back to its owner. Every card's faults are rolled when the
## request is posted (fault_odds() sets how many).
## Two kinds of client send cards. A referring tech has already diagnosed it: they describe the
## symptoms, tag the box with the faults they found, and pay the posted price. Techs do not rate
## the shop yet. A customer is a household on the neighbourhood map (neighbourhood.gd) and only
## leaves a note ("fix it"); the shop diagnoses it and bills a diagnosis fee, labour at the
## shop's rate and the materials used. The customer's satisfaction (`rate`) is their price
## satisfaction plus their time satisfaction, and it colours their household on the map.
## A card goes back once it is reassembled and out of hand; nobody pays for a card that is
## still broken.
signal changed
signal notice(text: String)

const RepairStatus = preload("res://scripts/repair_status.gd")
const Thermal = preload("res://scripts/gpu_thermal.gd")
const GpuStyle = preload("res://scripts/gpu_style.gd")
const Materials = preload("res://scripts/bill_of_materials.gd")
const Neighbourhood = preload("res://scripts/neighbourhood.gd")
const AudioMix = preload("res://scripts/audio_mix.gd")
## A cash register rings up every paid return; a tip adds a short happy motif just after it.
const KACHING = preload("res://assets/sounds/payment_kaching.wav")
const TIP_SOUND = preload("res://assets/sounds/payment_tip.wav")
const KACHING_GAIN_DB := -6.0
const TIP_GAIN_DB := -8.0
const TIP_DELAY := 0.45
## Accepted cards not yet returned. One bench for now, so one card.
const MAX_QUEUE := 1
## Requests on the board with the first zone open; each further zone adds one.
const OFFER_COUNT := 3
const STARTING_BALANCE := 100
## Faults per card: P(k) = (1 - r) * r^(k - 1) / (1 - r^n) for k = 1..n, n = fault types. Each
## extra fault is r times as likely as one fewer, so adding fault types makes the worst cards
## rarer still. r = (1 + sqrt(37)) / 18 puts 3 of 3 faults at exactly 10%: 64.6% / 25.4% / 10%.
const FAULT_RATIO := 0.39348681
## A tech pays each diagnosed fault's price. A customer is billed this fee for diagnosis, plus
## labour and materials; the same fee plus the fault prices is their quote, what they expect
## to pay.
const DIAGNOSIS_FEE := 20
const FAULTS := {
	"dust": {"pay": 40, "label": "Dust", "persists": "it still runs hot and the fan roars",
		"symptoms": ["It gets really hot and the fan roars as soon as a game starts.",
			"After ten minutes of gaming I get coloured sparkles and blocks all over the screen.",
			"The fan is loud under load and games start stuttering."]},
	"paste": {"pay": 60, "label": "Dried paste", "persists": "it still slows to a crawl once it warms up",
		"symptoms": ["Games run fine for a few minutes, then the frame rate falls off a cliff.",
			"It starts smooth but turns into a slideshow once it warms up.",
			"My benchmark score halves after the first run."]},
	"bearing": {"pay": 45, "label": "Dry bearing", "persists": "the fan still grinds",
		"symptoms": ["There's a grinding, rattling noise coming from the fan.",
			"The fan makes a scraping sound like a coffee grinder, worse when it spins up.",
			"It started making a gritty buzzing noise last week."]}}
## Faults the board does not roll yet (no repair exists) but a customer would still notice.
const UNROLLED := {"connector": {"persists": "the screen still cuts out"}}
const MODEL := "710 2GB low-profile"
## Share of requests referred by techs. The opening board's first request is always one, so
## the first card arrives tagged with its faults: the soft tutorial.
const TECH_SHARE := 0.5
const TECHS := [["Ravi", "Volt & Solder"], ["Dana", "PixelFix Kiosk"], ["Kofi", "ByteBench"],
	["Ines", "Circuit Clinic"], ["Hal", "Retro Rescue"]]
const NOTES := ["fix it", "pls fix", "It's broken. Fix it please!", "doesn't work right. fix?",
	"My son says it's the graphics card. Can you fix it?", "FIX ASAP!!", "Something is off with it. Thanks",
	"games are bad now. fix pls", "it's acting up, sort it out?"]
## Shop clock: play time runs at this many shop minutes per real second, from 09:00 on day 1,
## so the 09:00-21:00 working day takes 24 real minutes. Leaving through the front door skips
## to 09:00 on the next day (`start_next_day`); deadlines keep counting overnight.
const SHOP_MINUTES_PER_SECOND := 0.5
const OPENING_MINUTE := 9 * 60
const CLOSING_MINUTE := 21 * 60
## Labour is billed in started quarter hours at the shop's rate (set on the bench page). The
## default rate was rescaled with the clock (it used to run at 0.25), so a real minute of work
## bills the same as before.
const BILL_INCREMENT := 15
const DEFAULT_LABOR_RATE := 20
const LABOR_STEP := 5
const LABOR_RANGE := Vector2i(10, 150)
## Satisfaction is out of 5. Price: every full step of this fraction billed over the quote costs
## one. Time: a customer expects the card back within this many shop days of accepting it
## (by the end of the next day); each day later costs one.
const OVERCHARGE_STEP := 0.10
const EXPECTED_DAYS := 1
## A same-day return either earns a tip (this share of the bill, rolled in the range) or raises
## satisfaction by one or two, half the time each.
const SAME_DAY_TIP_CHANCE := 0.5
const TIP_SHARE := Vector2(0.1, 0.25)
const MIN_TIP := 2

var bench: Node3D
var box: Node3D
var rng := RandomNumberGenerator.new()
var balance := STARTING_BALANCE
## Shop minutes since midnight of day 1.
var shop_minutes := float(OPENING_MINUTE)
## Dollars per hour billed to customers.
var labor_rate := DEFAULT_LABOR_RATE
var offers: Array[Dictionary] = []
## Accepted jobs. state: "boxed" (delivery box on the desk) or "bench" (card unpacked).
var queue: Array[Dictionary] = []
## Returned jobs, newest first.
var ledger: Array[Dictionary] = []
var last_result: Dictionary = {}
## Why the last return attempt was refused, shown on the portal until the next change.
var last_refusal := ""
var next_id := 1041
var busy := false
var brand_bag: Array[String] = []
var last_brand := ""
## The households the shop works for and how far its influence reaches.
var neighbourhood := Neighbourhood.new()
## Megacorp cards arrive glued shut only in progression play; fixtures opt in per job.
var megacorp_glue := false
var kaching_audio: AudioStreamPlayer
var tip_audio: AudioStreamPlayer
var muted := false

## Product play starts with an empty bench. Fixtures keep the original three-fault card on
## the bench as a walk-in job.
func configure(world: Node3D, delivery_box: Node3D, empty_bench: bool) -> void:
	bench = world
	box = delivery_box
	rng.randomize()
	megacorp_glue = bench.progression_enabled
	kaching_audio = AudioStreamPlayer.new()
	kaching_audio.name = "PaymentSound"
	kaching_audio.stream = KACHING
	kaching_audio.volume_db = KACHING_GAIN_DB
	kaching_audio.bus = AudioMix.PAYMENT
	add_child(kaching_audio)
	tip_audio = AudioStreamPlayer.new()
	tip_audio.name = "TipSound"
	tip_audio.stream = TIP_SOUND
	tip_audio.volume_db = TIP_GAIN_DB
	tip_audio.bus = AudioMix.TIP
	add_child(tip_audio)
	if bench.progression_enabled:
		offers.append(make_exterior_job())
		offers.append(make_job(["paste"], "tech"))
		offers.append(make_job(["bearing"], "customer"))
	else:
		for index in range(OFFER_COUNT): offers.append(make_job([], "tech" if index == 0 else ""))
	if empty_bench:
		bench.gpu.visible = false
	else:
		var walk_in := make_job(FAULTS.keys(), "customer")
		walk_in.customer = "Walk-in"
		walk_in.home = ""
		walk_in.glued = []
		walk_in.state = "bench"
		walk_in.accepted_at = shop_minutes
		walk_in.unboxed_at = shop_minutes
		queue.append(walk_in)
		bench.gpu_style.apply_brand(walk_in.brand)
	bench.paste.consumed.connect(record_use)
	bench.bearing.consumed.connect(record_use)
	changed.emit()

func _process(delta: float) -> void:
	shop_minutes += delta * SHOP_MINUTES_PER_SECOND

## The shop closes for the night and opens again at the next 09:00. Cards, parcels and
## deadlines are left as they were.
func start_next_day() -> void:
	var opening := floorf(shop_minutes / 1440.0) * 1440.0 + OPENING_MINUTE
	if opening <= shop_minutes: opening += 1440.0
	shop_minutes = opening
	changed.emit()

## 1 on the first day.
func day() -> int:
	return floori(shop_minutes) / 1440 + 1

## Material a service controller used, charged to the card on the bench.
func record_use(item: String, quantity: float) -> void:
	var job := active()
	if job.is_empty() or job.state != "bench": return
	job.bom.add(item, quantity)

## P(k faults) for k = 1..n.
static func fault_odds(n: int) -> Array[float]:
	var odds: Array[float] = []
	var total := (1.0 - pow(FAULT_RATIO, n)) / (1.0 - FAULT_RATIO)
	for k in range(1, n + 1):
		odds.append(pow(FAULT_RATIO, k - 1) / total)
	return odds

func roll_faults() -> Array[String]:
	var kinds: Array = FAULTS.keys()
	var odds := fault_odds(kinds.size())
	var count := kinds.size()
	var roll := rng.randf()
	for k in range(odds.size()):
		roll -= odds[k]
		if roll < 0.0:
			count = k + 1
			break
	# Which faults is uniform: shuffle with the job RNG so a seed reproduces the board.
	var order := kinds.duplicate()
	for index in range(order.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap = order[index]
		order[index] = order[other]
		order[other] = swap
	var picked: Array[String] = []
	for kind in kinds:
		if order.find(kind) < count: picked.append(kind)
	return picked

func next_brand() -> String:
	if brand_bag.is_empty():
		brand_bag.assign(GpuStyle.BRANDS)
		for index in range(brand_bag.size() - 1, 0, -1):
			var other := rng.randi_range(0, index)
			var swap := brand_bag[index]
			brand_bag[index] = brand_bag[other]
			brand_bag[other] = swap
		if brand_bag.back() == last_brand:
			var swap := brand_bag[0]
			brand_bag[0] = brand_bag[-1]
			brand_bag[-1] = swap
	last_brand = brand_bag.pop_back()
	return last_brand

## A request. source: "tech" (diagnosed, tagged, fixed pay) or "customer" (a note, billed);
## empty rolls it with TECH_SHARE. `customer` is whoever the card goes back to. A customer card
## comes from a household in the shop's zone (`home`); a rolled customer becomes a tech
## referral when no household is free to call.
func make_job(faults: Array = [], source := "") -> Dictionary:
	var kinds: Array[String] = []
	kinds.assign(faults if not faults.is_empty() else roll_faults())
	var rolled := source == ""
	if rolled: source = "tech" if rng.randf() < TECH_SHARE else "customer"
	var household: Dictionary = {}
	if source == "customer":
		household = neighbourhood.pick(busy_homes(), rng, true)
		if household.is_empty() and rolled: source = "tech"
	var fault_pay := 0
	var symptoms: Array[String] = []
	for kind in kinds:
		fault_pay += FAULTS[kind].pay
		var lines: Array = FAULTS[kind].symptoms
		symptoms.append(lines[rng.randi_range(0, lines.size() - 1)])
	var brand := next_brand()
	var glued: Array = []
	if megacorp_glue and brand == Neighbourhood.MEGACORP:
		glued = neighbourhood.glue_roll(rng, bench.service.fan_screws, bench.service.cooler_screws)
	var job := {"id": next_id, "source": source, "brand": brand, "model": brand + " " + MODEL, "faults": kinds,
		"state": "offer", "bom": Materials.new(), "accepted_at": -1.0, "unboxed_at": -1.0, "glued": glued, "home": ""}
	if source == "tech":
		var tech: Array = TECHS[rng.randi_range(0, TECHS.size() - 1)]
		job.merge({"customer": "%s @ %s" % tech, "signature": tech[0], "pay": fault_pay, "complaint": " ".join(symptoms)})
	else:
		job.merge({"customer": household.get("resident", "Walk-in"), "home": household.get("id", ""), "pay": 0,
			"complaint": NOTES[rng.randi_range(0, NOTES.size() - 1)], "quote": DIAGNOSIS_FEE + fault_pay}, true)
	next_id += 1
	return job

## Households with a card on the board or the bench already.
func busy_homes() -> Array:
	var ids: Array = []
	for job in offers + queue:
		if job.get("home", "") != "": ids.append(job.home)
	return ids

## Requests the board shows: more as the shop's zone grows.
func offer_count() -> int:
	return OFFER_COUNT + neighbourhood.unlocked - 1

## Where a customer lives, for the board and bench pages; empty for techs and walk-ins.
func home_text(job: Dictionary) -> String:
	var household := neighbourhood.home(job.get("home", ""))
	return "" if household.is_empty() else neighbourhood.zone_name(household.zone)

func is_tech(job: Dictionary) -> bool:
	return job.get("source", "") == "tech"

## Fault names as a tech writes them on the tag.
static func fault_labels(faults: Array) -> Array[String]:
	var labels: Array[String] = []
	for kind in faults: labels.append(FAULTS[kind].label if FAULTS.has(kind) else String(kind).capitalize())
	return labels

func active() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}

func bench_full() -> bool:
	return queue.size() >= MAX_QUEUE

## A steady source of work that needs only the starter blower. Internal surfaces are clean.
func make_exterior_job() -> Dictionary:
	var job := make_job(["dust"], "tech")
	job.exterior_clean = true
	# Nothing is opened, so a glued card would make no difference.
	job.glued = []
	job.pay = 25
	job.complaint = "Exterior fan clean only. Internals checked: no disassembly needed. Blow the dust off the fan and return it."
	return job

func missing_equipment(job: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	if bench.shop != null: missing.assign(bench.shop.missing_for(job))
	return missing

func accept(id: int) -> bool:
	if bench_full():
		notice.emit("The bench is full. Return the current card before taking another job.")
		return false
	for index in range(offers.size()):
		if offers[index].id != id: continue
		var job: Dictionary = offers[index]
		var missing := missing_equipment(job)
		if not missing.is_empty():
			notice.emit("Job locked. Required: %s. Visit the PC shop." % ", ".join(missing))
			return false
		job.state = "boxed"
		job.accepted_at = shop_minutes
		queue.append(job)
		offers[index] = make_exterior_job() if job.get("exterior_clean", false) else make_job()
		last_refusal = ""
		var tech := is_tech(job)
		box.deliver("JOB #%d  /  %s\n710  /  2GB DDR3\nANTI-STATIC PACKED" % [job.id, job.customer], job.brand,
			fault_labels(job.faults) if tech else [], "" if tech else job.complaint, job.get("signature", ""))
		# First-person play receives it through the window hatch; legacy fixtures keep the desk drop.
		var hatch: Node3D = bench.get("delivery_window")
		if hatch != null: hatch.receive()
		notice.emit("Job #%d accepted. %s's card is on its way to the delivery hatch under the window." % [job.id, job.customer]
			if hatch != null else "Job #%d accepted. %s's card is boxed on the repair desk." % [job.id, job.customer])
		changed.emit()
		return true
	return false

## One click opens the box; the card lifts out into the holder carrying its rolled faults.
func unbox() -> void:
	var job := active()
	if busy or job.is_empty() or job.state != "boxed" or box.location != "desk" or box.moving: return
	busy = true
	changed.emit()
	await box.open()
	bench.gpu_style.apply_brand(job.brand)
	apply_faults(job.faults, job.get("exterior_clean", false), job.get("glued", []))
	var gpu: Node3D = bench.gpu
	var home: Transform3D = gpu.get_parent().global_transform * bench.inspection.home
	var bounds: AABB = home * preload("res://scripts/asset_contract.gd").bounds_in(gpu)
	var cradle: Vector3 = box.cradle_point()
	var offset := cradle - bounds.get_center()
	offset.y = cradle.y - bounds.position.y
	var start := Transform3D(home.basis, home.origin + offset)
	gpu.global_transform = start
	gpu.visible = true
	var motion := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(gpu, "global_transform", Transform3D(home.basis, start.origin + Vector3(0, box.box_size.y + 0.5, 0)), 0.35)
	motion.tween_property(gpu, "global_transform", home, 0.5)
	await motion.finished
	gpu.global_transform = home
	bench.inspection.play_set_down()
	await bench.park_delivery_box()
	job.state = "bench"
	job.unboxed_at = shop_minutes
	busy = false
	notice.emit("Card unboxed and in the holder. " + ("%s found: %s. \"%s\"" % [job.customer, ", ".join(fault_labels(job.faults)), job.complaint]
		if is_tech(job) else "%s's note says: \"%s\"" % [job.customer, job.complaint]))
	changed.emit()

## Lays out the card's faults; everything not rolled starts healthy. `glued` lists the screws a
## megacorp sealed under glue.
func apply_faults(faults: Array, exterior_only := false, glued: Array = []) -> void:
	bench.glue.set_sealed(glued)
	bench.cleaning.reset_dust("dust" in faults, exterior_only)
	if "paste" in faults: bench.paste.reset_dried()
	else: bench.paste.set_fresh()
	if "bearing" in faults: bench.bearing.set_dry()
	else: bench.bearing.set_oiled()
	bench.connector.set_state("ok")
	for reading in ["memory_c", "core_c", "cooler_c"]:
		bench.thermal.set(reading, Thermal.AMBIENT)

## What the customer would still find wrong, in FAULTS order.
func problems() -> Array[String]:
	var found: Array[String] = []
	if not bench.cleaning.celebrated: found.append("dust")
	var paste: Node = bench.paste
	if paste.dried or not paste.seated or paste.quality < RepairStatus.GOOD_CONTACT: found.append("paste")
	if bench.bearing.dry or not bench.bearing.opened.is_empty(): found.append("bearing")
	if bench.connector.state != "ok": found.append("connector")
	return found

## Empty when the card can go back; otherwise what still has to happen first.
func return_block() -> String:
	var job := active()
	if job.is_empty(): return "There is no card on the bench."
	if job.state != "bench": return "Unbox the card first."
	if busy: return "Wait for the card to settle."
	if bench.testing_station.installed or bench.testing_station.moving: return "Take the card off the test board first."
	var service: Node = bench.service
	if service.busy or not service.turns.is_empty(): return "Finish tightening every screw before returning the card."
	if service.held_part != "" or not service.removed.is_empty() or not service.cable_connected:
		return "Reassemble the card and reconnect the fan cable first."
	if bench.inspection.held or bench.inspection.moving: return "Set the card down first."
	return ""

## The courier collects the card. A tech pays the posted price and a customer pays the bill,
## each only if it works; the customer then rates the shop.
func return_card() -> Dictionary:
	var reason := return_block()
	if reason != "":
		last_refusal = reason
		notice.emit(reason)
		changed.emit()
		return {}
	var labor := labor_minutes(active())
	var turnaround := delivery_minutes(active())
	var days := days_taken(active())
	var invoice := {} if is_tech(active()) else bill(active())
	var job: Dictionary = queue.pop_front()
	var left := problems()
	var paid := left.is_empty()
	var amount: int = (job.pay if is_tech(job) else invoice.dollars) if paid else 0
	var complaints: Array[String] = []
	for kind in left: complaints.append((FAULTS[kind] if FAULTS.has(kind) else UNROLLED[kind]).persists)
	var said := " and ".join(complaints)
	var feedback: String = "Works perfectly, thanks!" if paid else said.left(1).to_upper() + said.substr(1) + "."
	# Techs do not rate the shop (stars 0).
	var stars := 0
	var tip := 0
	var opened: Array[String] = []
	if not is_tech(job):
		var rating := rate(paid, invoice.dollars, job.quote, days, rng)
		stars = rating.stars
		tip = rating.tip
		if paid: feedback = "Works perfectly! " + " ".join(rating.remarks)
		if job.home != "": opened = neighbourhood.record(job.home, stars)
	amount += tip
	balance += amount
	if amount > 0: play_payment(tip > 0)
	last_result = {"id": job.id, "source": job.source, "customer": job.customer, "brand": job.brand, "model": job.model,
		"paid": paid, "amount": amount, "tip": tip, "left": left, "faults": job.faults, "feedback": feedback, "stars": stars,
		"bill": invoice, "materials": job.bom.lines(), "labor_minutes": labor, "turnaround": turnaround, "days": days,
		"home": job.get("home", "")}
	ledger.push_front(last_result)
	last_refusal = ""
	bench.cleaning.end()
	bench.gpu.visible = false
	box.take_away()
	var message := "Job #%d returned to %s. %s%s%s" % [job.id, job.customer,
		"Paid $%d." % amount if paid else "They say %s. No payment." % said,
		" Tipped $%d." % tip if tip > 0 else "", "" if stars == 0 else " Satisfaction %d/5." % stars]
	for zone in opened:
		message += " Word gets around: %s now trusts your bench, and its households will call. %s is not pleased." % [zone, Neighbourhood.MEGACORP]
		while offers.size() < offer_count(): offers.append(make_job())
	last_result.opened = opened
	# After the refresh, so the room's status line keeps this news rather than its idle hint.
	changed.emit()
	notice.emit(message)
	return last_result

## Ka-ching for the money; with a tip, the little motif follows as the register rings out.
func play_payment(tipped: bool) -> void:
	if muted: return
	kaching_audio.play()
	if tipped: get_tree().create_timer(TIP_DELAY).timeout.connect(func(): if not muted: tip_audio.play())

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		kaching_audio.stop()
		tip_audio.stop()

# --- Time, bills and ratings -----------------------------------------------------------------

## Shop minutes the card has been on the bench (what labour bills for).
func labor_minutes(job: Dictionary) -> float:
	return 0.0 if job.is_empty() or job.unboxed_at < 0.0 else shop_minutes - job.unboxed_at

## Shop minutes since the job was accepted (what the customer waits).
func delivery_minutes(job: Dictionary) -> float:
	return 0.0 if job.is_empty() or job.accepted_at < 0.0 else shop_minutes - job.accepted_at

static func billed_minutes(minutes: float) -> int:
	return maxi(1, ceili(minutes / BILL_INCREMENT - 0.0001)) * BILL_INCREMENT

## A customer's itemised bill so far: diagnosis, labour at the current rate and the bill of
## materials. Lines and totals in cents; the customer pays whole dollars.
func bill(job: Dictionary) -> Dictionary:
	var lines: Array[Dictionary] = [{"label": "Diagnosis", "cents": DIAGNOSIS_FEE * 100}]
	var minutes := billed_minutes(labor_minutes(job))
	lines.append({"label": "Labour %s @ $%d/h" % [duration_text(minutes), labor_rate], "cents": minutes * labor_rate * 100 / 60})
	for line in job.bom.lines():
		lines.append({"label": "%s, %s" % [line.name, Materials.amount_text(line)], "cents": line.cents})
	var total := 0
	for line in lines: total += line.cents
	return {"lines": lines, "cents": total, "dollars": roundi(total / 100.0)}

## Shop days from accepting the job to now: 0 for a same-day return.
func days_taken(job: Dictionary) -> int:
	if job.is_empty() or job.accepted_at < 0.0: return 0
	return day() - (floori(job.accepted_at) / 1440 + 1)

## How many satisfaction points a bill over the quote costs: one per full OVERCHARGE_STEP.
static func price_penalty(bill_dollars: int, quote: int) -> int:
	if bill_dollars <= quote: return 0
	return floori((bill_dollars - quote) / maxf(quote, 1.0) / OVERCHARGE_STEP + 0.0001)

## A customer's satisfaction out of 5: their price satisfaction plus their time satisfaction.
## Each full 10% billed over the quote costs one; each shop day past EXPECTED_DAYS costs one.
## A same-day return either earns a tip or raises satisfaction by one or two (rolled with
## `luck`). A card that is still broken gets one and no tip.
static func rate(fixed: bool, bill_dollars: int, quote: int, days: int, luck: RandomNumberGenerator) -> Dictionary:
	if not fixed: return {"stars": 1, "tip": 0, "bonus": 0, "price_penalty": 0, "late_days": 0, "remarks": []}
	var pricey := price_penalty(bill_dollars, quote)
	var late := maxi(0, days - EXPECTED_DAYS)
	var tip := 0
	var bonus := 0
	if days <= 0:
		if luck.randf() < SAME_DAY_TIP_CHANCE: tip = maxi(MIN_TIP, roundi(bill_dollars * luck.randf_range(TIP_SHARE.x, TIP_SHARE.y)))
		else: bonus = luck.randi_range(1, 2)
	var remarks: Array[String] = []
	remarks.append("Same day! Here's a little extra." if tip > 0 else "Same day! Brilliant." if days <= 0 else
		"Back on time." if late == 0 else "A day late." if late == 1 else "%d days late." % late)
	if pricey == 0: remarks.append("Under the quote, too!" if bill_dollars < quote else "Right on the quote.")
	else: remarks.append(["Bit over the quote.", "Well over the quote.", "Way over the quote."][pricey - 1] if pricey <= 3 else "Daylight robbery.")
	return {"stars": clampi(5 - pricey - late + bonus, 1, 5), "tip": tip, "bonus": bonus, "price_penalty": pricey,
		"late_days": late, "remarks": remarks}

## Average customer stars and how many ratings it is from; 0.0 before the first.
func shop_rating() -> Vector2:
	var total := 0
	var count := 0
	for entry in ledger:
		if entry.get("stars", 0) > 0:
			total += entry.stars
			count += 1
	return Vector2(total / float(count) if count > 0 else 0.0, count)

## What the job is worth right now: the tech's posted price, or the customer's bill so far.
func value_text(job: Dictionary) -> String:
	return "$%d" % job.pay if is_tech(job) else "$%d billed" % bill(job).dollars if job.state == "bench" else "billed"

## The shop day by which the customer expects their card back.
func due_day(job: Dictionary) -> int:
	var accepted: float = job.accepted_at if job.get("accepted_at", -1.0) >= 0.0 else shop_minutes
	return floori(accepted) / 1440 + 1 + EXPECTED_DAYS

## When the customer expects the card back, from now; empty for techs.
func due_text(job: Dictionary) -> String:
	if is_tech(job): return ""
	var left := due_day(job) - day()
	if left < 0: return "%d day%s late" % [-left, "" if left == -1 else "s"]
	if left == 0: return "by end of today"
	if left == 1: return "by end of tomorrow"
	return "by end of day %d" % due_day(job)

func set_labor_rate(rate_per_hour: int) -> void:
	labor_rate = clampi(rate_per_hour, LABOR_RANGE.x, LABOR_RANGE.y)
	changed.emit()

## "45m", "1h 15m".
static func duration_text(minutes: float) -> String:
	var whole := roundi(minutes)
	return "%dm" % whole if whole < 60 else "%dh %02dm" % [whole / 60, whole % 60]

## "DAY 1  09:45".
static func clock_text(minutes: float) -> String:
	var whole := floori(minutes)
	return "DAY %d  %02d:%02d" % [whole / 1440 + 1, whole % 1440 / 60, whole % 60]

## "****-" for four of five stars, in plain characters for the mono terminal font.
static func stars_text(stars: int) -> String:
	return "*".repeat(stars) + "-".repeat(5 - stars)
