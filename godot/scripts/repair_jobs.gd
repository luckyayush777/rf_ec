extends Node
## The shop's work: repair requests on the computer's job board, the bench queue, the delivery
## box, and payment when a card goes back to its owner. Every card's faults are rolled when the
## request is posted (fault_odds() sets how many); the customer only describes symptoms.
## A card goes back once it is reassembled and out of hand; the customer pays only if nothing
## is wrong with it any more.
signal changed
signal notice(text: String)

const RepairStatus = preload("res://scripts/repair_status.gd")
const Thermal = preload("res://scripts/gpu_thermal.gd")
## Accepted cards not yet returned. One bench for now, so one card.
const MAX_QUEUE := 1
const OFFER_COUNT := 3
const STARTING_BALANCE := 100
## Faults per card: P(k) = (1 - r) * r^(k - 1) / (1 - r^n) for k = 1..n, n = fault types. Each
## extra fault is r times as likely as one fewer, so adding fault types makes the worst cards
## rarer still. r = (1 + sqrt(37)) / 18 puts 3 of 3 faults at exactly 10%: 64.6% / 25.4% / 10%.
const FAULT_RATIO := 0.39348681
## Every job pays a diagnosis fee plus each fault's price.
const DIAGNOSIS_FEE := 20
const FAULTS := {
	"dust": {"pay": 40, "persists": "it still runs hot and the fan roars",
		"symptoms": ["It gets really hot and the fan roars as soon as a game starts.",
			"After ten minutes of gaming I get coloured sparkles and blocks all over the screen.",
			"The fan is loud under load and games start stuttering."]},
	"paste": {"pay": 60, "persists": "it still slows to a crawl once it warms up",
		"symptoms": ["Games run fine for a few minutes, then the frame rate falls off a cliff.",
			"It starts smooth but turns into a slideshow once it warms up.",
			"My benchmark score halves after the first run."]},
	"bearing": {"pay": 45, "persists": "the fan still grinds",
		"symptoms": ["There's a grinding, rattling noise coming from the fan.",
			"The fan makes a scraping sound like a coffee grinder, worse when it spins up.",
			"It started making a gritty buzzing noise last week."]}}
const CLOSERS := ["", " Can you take a look?", " It's my only card, please help.", " Would love it back by the weekend."]
const CUSTOMERS := ["Priya S.", "Marcus T.", "Elena V.", "Tomasz K.", "Aisha R.", "Jonah W.", "Mei L.",
	"Diego F.", "Sam O.", "Fatima N.", "Lukas B.", "Grace H."]
const MODEL := "710 2GB low-profile"

var bench: Node3D
var box: Node3D
var rng := RandomNumberGenerator.new()
var balance := STARTING_BALANCE
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

## Product play starts with an empty bench. Fixtures keep the original three-fault card on
## the bench as a walk-in job.
func configure(world: Node3D, delivery_box: Node3D, empty_bench: bool) -> void:
	bench = world
	box = delivery_box
	rng.randomize()
	for index in range(OFFER_COUNT): offers.append(make_job())
	if empty_bench:
		bench.gpu.visible = false
	else:
		var walk_in := make_job(FAULTS.keys())
		walk_in.customer = "Walk-in"
		walk_in.state = "bench"
		queue.append(walk_in)
	changed.emit()

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

func make_job(faults: Array = []) -> Dictionary:
	var kinds: Array[String] = []
	kinds.assign(faults if not faults.is_empty() else roll_faults())
	var pay := DIAGNOSIS_FEE
	var symptoms: Array[String] = []
	for kind in kinds:
		pay += FAULTS[kind].pay
		var lines: Array = FAULTS[kind].symptoms
		symptoms.append(lines[rng.randi_range(0, lines.size() - 1)])
	var job := {"id": next_id, "customer": CUSTOMERS[rng.randi_range(0, CUSTOMERS.size() - 1)], "model": MODEL,
		"faults": kinds, "pay": pay, "complaint": " ".join(symptoms) + CLOSERS[rng.randi_range(0, CLOSERS.size() - 1)],
		"state": "offer"}
	next_id += 1
	return job

func active() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}

func bench_full() -> bool:
	return queue.size() >= MAX_QUEUE

func accept(id: int) -> bool:
	if bench_full():
		notice.emit("The bench is full. Return the current card before taking another job.")
		return false
	for index in range(offers.size()):
		if offers[index].id != id: continue
		var job: Dictionary = offers[index]
		job.state = "boxed"
		queue.append(job)
		offers[index] = make_job()
		last_refusal = ""
		box.deliver("BENCHWORKS  INBOUND REPAIR\nJOB #%d  ·  %s\nFRAGILE  ·  ANTI-STATIC" % [job.id, job.model])
		notice.emit("Job #%d accepted. %s's card is boxed on the repair desk." % [job.id, job.customer])
		changed.emit()
		return true
	return false

## One click opens the box; the card lifts out into the holder carrying its rolled faults.
func unbox() -> void:
	var job := active()
	if busy or job.is_empty() or job.state != "boxed": return
	busy = true
	changed.emit()
	await box.open()
	apply_faults(job.faults)
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
	box.take_away()
	job.state = "bench"
	busy = false
	notice.emit("Card unboxed and in the holder. Customer says: \"%s\"" % job.complaint)
	changed.emit()

## Lays out the card's faults; everything not rolled starts healthy.
func apply_faults(faults: Array) -> void:
	bench.cleaning.reset_dust("dust" in faults)
	if "paste" in faults: bench.paste.reset_dried()
	else: bench.paste.set_fresh()
	if "bearing" in faults: bench.bearing.set_dry()
	else: bench.bearing.set_oiled()
	for reading in ["memory_c", "core_c", "cooler_c"]:
		bench.thermal.set(reading, Thermal.AMBIENT)

## What the customer would still find wrong, in FAULTS order.
func problems() -> Array[String]:
	var found: Array[String] = []
	if not bench.cleaning.celebrated: found.append("dust")
	var paste: Node = bench.paste
	if paste.dried or not paste.seated or paste.quality < RepairStatus.GOOD_CONTACT: found.append("paste")
	if bench.bearing.dry or not bench.bearing.opened.is_empty(): found.append("bearing")
	return found

## Empty when the card can go back; otherwise what still has to happen first.
func return_block() -> String:
	var job := active()
	if job.is_empty(): return "There is no card on the bench."
	if job.state != "bench": return "Unbox the card first."
	if busy: return "Wait for the card to settle."
	if bench.testing_station.installed or bench.testing_station.moving: return "Take the card off the test board first."
	var service: Node = bench.service
	if service.held_part != "" or not service.removed.is_empty() or not service.cable_connected:
		return "Reassemble the card and reconnect the fan cable first."
	if bench.inspection.held or bench.inspection.moving: return "Set the card down first."
	return ""

## The courier collects the card; the customer pays if it works.
func return_card() -> Dictionary:
	var reason := return_block()
	if reason != "":
		last_refusal = reason
		notice.emit(reason)
		changed.emit()
		return {}
	var job: Dictionary = queue.pop_front()
	var left := problems()
	var paid := left.is_empty()
	var amount: int = job.pay if paid else 0
	balance += amount
	var complaints: Array[String] = []
	for kind in left: complaints.append(FAULTS[kind].persists)
	var said := " and ".join(complaints)
	last_result = {"id": job.id, "customer": job.customer, "paid": paid, "amount": amount, "left": left, "faults": job.faults,
		"feedback": "Works perfectly, thanks!" if paid else said.left(1).to_upper() + said.substr(1) + "."}
	ledger.push_front(last_result)
	last_refusal = ""
	bench.cleaning.end()
	bench.gpu.visible = false
	notice.emit("Job #%d returned to %s. %s" % [job.id, job.customer,
		"Paid $%d." % amount if paid else "They say %s. No payment." % said])
	changed.emit()
	return last_result
