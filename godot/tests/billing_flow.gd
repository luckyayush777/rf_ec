extends SceneTree
## Tech referrals and customer jobs: box paperwork (fault tags and notes), the bill of
## materials, customer bills at the shop's labour rate, ratings and the portal pages.
var failures: Array[String] = []
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")
func capturing() -> bool:
	return "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
func capture(name: String) -> void:
	if not capturing(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")
## The portal page itself, at its native resolution.
func capture_page(bench: Node3D, name: String) -> void:
	bench.computer.refresh()
	await process_frame
	await process_frame
	if not capturing(): return
	await RenderingServer.frame_post_draw
	bench.computer.viewport.get_texture().get_image().save_png("res://build/" + name + ".png")
func look_at_lid(bench: Node3D) -> void:
	var player = bench.camera_rig
	var lid: Vector3 = bench.delivery_box.global_position + Vector3(0, bench.delivery_box.box_size.y, 0)
	player.body.global_position = Vector3(lid.x - 0.4, -4.43, lid.z + 3.2)
	player.update_camera()
	player.camera.look_at(lid + Vector3(0.1, 0, 0.25))
	player.look_pitch = player.camera.rotation.x
	player.look_yaw = player.camera.rotation.y
	player.update_camera()
	await physics_frame
	await process_frame
## A close look straight down at the lid paperwork, from a test camera with the HUD hidden.
func capture_close(bench: Node3D, name: String) -> void:
	if not capturing(): return
	var paper: Node3D = bench.delivery_box.paper
	var eye := Camera3D.new()
	bench.add_child(eye)
	eye.global_position = paper.global_position + Vector3(0, 1.3, 0.55)
	eye.look_at(paper.global_position)
	eye.make_current()
	bench.hud.visible = false
	await process_frame
	await capture(name)
	bench.hud.visible = true
	bench.camera_rig.camera.make_current()
	eye.queue_free()
func texts(box: Node3D) -> Array:
	return box.handwriting.map(func(label: Label3D): return label.text)
func settle(bench: Node3D) -> void:
	for step in range(80):
		await create_timer(0.05).timeout
		if not bench.jobs.busy and not bench.inspection.moving: return

func run() -> void:
	var Jobs = preload("res://scripts/repair_jobs.gd")
	var Materials = preload("res://scripts/bill_of_materials.gd")
	var Box = preload("res://scripts/delivery_box.gd")
	# Pure rules first.
	expect(Box.tag_color(1) == "green" and Box.tag_color(2) == "yellow" and Box.tag_color(3) == "red" and Box.tag_color(4) == "red",
		"Tag colours did not follow the fault count")
	expect(Jobs.billed_minutes(0.0) == 15 and Jobs.billed_minutes(15.0) == 15 and Jobs.billed_minutes(15.5) == 30 and Jobs.billed_minutes(61.0) == 75,
		"Labour was not billed in started quarter hours")
	expect(Jobs.rate(true, 60, 65, 90.0, 120).stars == 5, "An on-time, fair job did not get five stars")
	expect(Jobs.rate(true, 60, 65, 170.0, 120).stars == 4, "A job up to 1.5x late did not lose one star")
	expect(Jobs.rate(true, 120, 65, 90.0, 120).stars == 3, "A bill up to 2x fair did not lose two stars")
	expect(Jobs.rate(true, 400, 65, 600.0, 120).stars == 1, "Ratings fell below one star")
	expect(Jobs.rate(false, 60, 65, 10.0, 120).stars == 1, "An unfixed card was rated above one star")
	expect("Cheap" in " ".join(Jobs.rate(true, 40, 65, 10.0, 120).remarks), "A cheap bill was not remarked on")
	var materials = Materials.new()
	materials.add("thermal-paste", 0.3)
	materials.add("ipa-pad", 1.0)
	materials.add("ipa-pad", 1.0)
	materials.add("bearing-oil", 2.0)
	var lines: Array[Dictionary] = materials.lines()
	expect(lines.size() == 3 and lines[0].item == "thermal-paste" and lines[0].cents == 45 and lines[1].cents == 30 and lines[2].cents == 10,
		"Bill of materials lines were %s" % [lines])
	expect(materials.total_cents() == 85 and materials.total_cents("consumable") == 85 and materials.total_cents("part") == 0,
		"Bill of materials totals were wrong")
	expect(Materials.amount_text(lines[0]) == "0.3 g" and Materials.amount_text(lines[1]) == "2 pads" and Materials.money(85) == "$0.85",
		"Bill of materials amounts printed as %s / %s" % [Materials.amount_text(lines[0]), Materials.amount_text(lines[1])])
	expect(Jobs.clock_text(9 * 60 + 45.5) == "DAY 1  09:45" and Jobs.clock_text(1440 + 60) == "DAY 2  01:00", "Shop clock text was wrong")
	expect(Jobs.duration_text(45) == "45m" and Jobs.duration_text(75) == "1h 15m", "Duration text was wrong")

	var bench = load("res://scenes/workbench.tscn").instantiate()
	bench.job_flow = true
	root.add_child(bench)
	await process_frame
	var jobs: Node = bench.jobs
	var box: Node3D = bench.delivery_box
	jobs.rng.seed = 4242
	expect(jobs.is_tech(jobs.offers[0]), "The opening board did not start with a tech referral")
	var sources := {}
	for index in range(400):
		var source: String = jobs.make_job().source
		sources[source] = sources.get(source, 0) + 1
	expect(sources.size() == 2 and absf(sources.tech / 400.0 - jobs.TECH_SHARE) < 0.08, "Request sources were %s" % [sources])
	for offer in jobs.offers:
		if jobs.is_tech(offer):
			var fault_pay := 0
			for kind in offer.faults: fault_pay += jobs.FAULTS[kind].pay
			expect(offer.pay == fault_pay and offer.complaint != "" and not offer.has("due"), "A tech's offer was not priced by its diagnosed faults")
		else:
			expect(offer.pay == 0 and offer.complaint in jobs.NOTES and offer.due >= jobs.DUE_BASE, "A customer's offer had a price or symptoms")
	await capture_page(bench, "billing-portal-board")

	# A tech's card arrives tagged: green for one fault, yellow for two, a red card for three.
	jobs.offers[0] = jobs.make_job(["dust"], "tech")
	var tech_job: Dictionary = jobs.offers[0]
	expect(jobs.accept(tech_job.id), "The tech job could not be accepted")
	await create_timer(0.6).timeout
	expect(box.paperwork == "green" and texts(box) == ["Dust", "- " + tech_job.signature], "A one-fault tag read %s (%s)" % [texts(box), box.paperwork])
	var hands := ["PermanentMarker-Regular.ttf", "Caveat-Variable.ttf"]
	expect(box.handwriting.all(func(label: Label3D): return label.font != null and label.font.resource_path.get_file() in hands), "Paperwork was not handwritten")
	expect(is_equal_approx(box.paper_material.albedo_color.g, Box.TAG_COLORS.green.g), "The one-fault tag was not green")
	await look_at_lid(bench)
	await capture("billing-tag-green")
	await capture_close(bench, "billing-tag-green-close")
	box.set_paperwork(jobs.fault_labels(["paste", "bearing"]), "", "Kofi")
	await process_frame
	expect(box.paperwork == "yellow" and texts(box) == ["Dried paste", "Dry bearing", "- Kofi"], "A two-fault tag read %s" % [texts(box)])
	await capture_close(bench, "billing-tag-yellow-close")
	box.set_paperwork(jobs.fault_labels(["dust", "paste", "bearing"]), "", "Ines")
	await process_frame
	expect(box.paperwork == "red" and texts(box).size() == 4, "A three-fault card read %s" % [texts(box)])
	await capture_close(bench, "billing-tag-red-close")
	box.set_paperwork([], "My son says it's the graphics card. Can you fix it?")
	await process_frame
	expect(box.paperwork == "note" and texts(box).size() >= 3 and " ".join(texts(box)) == "My son says it's the graphics card. Can you fix it?",
		"The customer note read %s" % [texts(box)])
	await capture_close(bench, "billing-note-close")
	await capture("billing-note")
	# A tech pays the posted price and leaves no rating.
	box.set_paperwork(jobs.fault_labels(tech_job.faults), "", tech_job.signature)
	await jobs.unbox()
	await settle(bench)
	bench.debug_clean_gpu()
	var before: int = jobs.balance
	var tech_result: Dictionary = jobs.return_card()
	expect(tech_result.paid and tech_result.amount == tech_job.pay and jobs.balance == before + tech_job.pay and tech_result.stars == 0,
		"The tech job paid %s with stars %s" % [tech_result.get("amount"), tech_result.get("stars")])
	expect(jobs.shop_rating().y == 0, "A tech rated the shop")

	# A customer's card: a note, no tag; the shop bills diagnosis, labour and materials.
	jobs.offers[0] = jobs.make_job(["bearing"], "customer")
	var job: Dictionary = jobs.offers[0]
	expect(jobs.accept(job.id), "The customer job could not be accepted")
	await create_timer(0.6).timeout
	expect(box.paperwork == "note" and " ".join(texts(box)) == job.complaint, "The customer's box did not carry their note")
	await jobs.unbox()
	await settle(bench)
	# Material reported while the card is on the bench lands on its bill of materials.
	bench.bearing.drip(1.0)
	bench.paste.squeeze("die", Vector2(14, 14), 0.05)
	bench.paste.consumed.emit("ipa-pad", 1.0)
	expect(job.bom.quantity("bearing-oil") == 1.0 and job.bom.quantity("thermal-paste") > 0.0 and job.bom.quantity("ipa-pad") == 1.0,
		"Used material was not recorded: %s" % [job.bom.used])
	bench.debug_clean_gpu()
	bench.paste.debug_repaste()
	bench.bearing.debug_oil()
	jobs.shop_minutes = job.unboxed_at + 50.0
	var invoice: Dictionary = jobs.bill(job)
	expect(invoice.lines.size() == 2 + job.bom.lines().size() and invoice.lines[0].cents == jobs.DIAGNOSIS_FEE * 100 and
		invoice.lines[1].cents == 60 * jobs.labor_rate * 100 / 60 and "1h 00m" in invoice.lines[1].label,
		"The bill was %s" % [invoice.lines])
	expect(invoice.cents == jobs.DIAGNOSIS_FEE * 100 + jobs.labor_rate * 100 + job.bom.total_cents(), "Bill lines did not add up")
	bench.computer.tab = "bench"
	await capture_page(bench, "billing-portal-bench-bill")
	var rate_up: Button = bench.computer.viewport.find_child("RateUp", true, false)
	expect(rate_up != null, "The bench page had no labour rate control for a customer job")
	if rate_up != null: rate_up.pressed.emit()
	expect(jobs.labor_rate == jobs.DEFAULT_LABOR_RATE + jobs.LABOR_STEP, "The rate control did not raise the labour rate")
	jobs.set_labor_rate(jobs.DEFAULT_LABOR_RATE)
	before = jobs.balance
	var expected: int = jobs.bill(job).dollars
	var result: Dictionary = jobs.return_card()
	expect(result.paid and result.amount == expected and jobs.balance == before + expected, "The customer paid %s, not the bill %d" % [result.get("amount"), expected])
	expect(result.stars == 5 and "on time" in result.feedback, "A quick, fairly priced repair rated %s: %s" % [result.stars, result.feedback])
	expect(result.materials.size() == 3 and not result.bill.is_empty(), "The ledger entry lost its bill or materials")
	# Slow and expensive: the customer marks the shop down.
	jobs.offers[0] = jobs.make_job(["dust"], "customer")
	var slow: Dictionary = jobs.offers[0]
	jobs.accept(slow.id)
	await jobs.unbox()
	await settle(bench)
	bench.debug_clean_gpu()
	jobs.set_labor_rate(150)
	jobs.shop_minutes += slow.due * 2.5
	var slow_result: Dictionary = jobs.return_card()
	expect(slow_result.paid and slow_result.stars == 1 and ("expensive" in slow_result.feedback.to_lower() or "robbery" in slow_result.feedback.to_lower()),
		"A late, overpriced repair rated %s: %s" % [slow_result.stars, slow_result.feedback])
	expect(is_equal_approx(jobs.shop_rating().x, 3.0) and jobs.shop_rating().y == 2, "Shop rating was %s" % [jobs.shop_rating()])
	# Unfixed: no payment, one star.
	jobs.offers[0] = jobs.make_job(["dust"], "customer")
	jobs.accept(jobs.offers[0].id)
	await jobs.unbox()
	await settle(bench)
	before = jobs.balance
	var unfixed: Dictionary = jobs.return_card()
	expect(not unfixed.paid and jobs.balance == before and unfixed.stars == 1, "An unfixed customer card paid or rated above one star")
	# Nothing is recorded with no card on the bench.
	bench.bearing.consumed.emit("bearing-oil", 1.0)
	expect(jobs.active().is_empty(), "A card stayed on the bench")
	bench.computer.tab = "ledger"
	await capture_page(bench, "billing-portal-ledger")
	bench.queue_free()
	# The audio server drops a sound still playing at free only a few frames later; quitting
	# sooner reports its stream as leaked at exit.
	for frame in range(10): await process_frame
	print("PASS: tech tags (green/yellow/red) and customer notes in handwriting, bill of materials, customer bills at the labour rate, ratings and portal pages" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
