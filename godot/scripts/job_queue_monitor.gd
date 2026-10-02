extends Node3D
## The shop's job-queue display: every accepted card and where it is, readable from the bench.
## It only shows state; jobs are taken and returned on the shop computer.
const UI = preload("res://scripts/screen_ui.gd")
## Low resolution on a big panel: the text stays readable from across the bench.
const PAGE_SIZE := Vector2i(960, 540)
const BOXED := Color("#d98a1c")
const ON_BENCH := Color("#3b82e0")

@onready var screen: MeshInstance3D = $Screen
var viewport: SubViewport
var jobs: Node
var balance_label: Label
var slots: VBoxContainer
var footer: Label

func _ready() -> void:
	viewport = UI.attach_viewport(screen, PAGE_SIZE)
	var root := Panel.new()
	root.size = PAGE_SIZE
	root.add_theme_stylebox_override("panel", UI.flat(Color("#101820")))
	viewport.add_child(root)
	var margin := MarginContainer.new()
	margin.size = PAGE_SIZE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var title := UI.label("REPAIR QUEUE", 46, Color.WHITE, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	balance_label = UI.label("", 46, Color("#8ee0a8"), true)
	bar.add_child(balance_label)
	slots = VBoxContainer.new()
	slots.add_theme_constant_override("separation", 14)
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(slots)
	footer = UI.label("", 26, Color("#8b9aa8"))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size.x = PAGE_SIZE.x - 52
	column.add_child(footer)

func configure(repair_jobs: Node) -> void:
	jobs = repair_jobs
	jobs.changed.connect(refresh)
	refresh()

func refresh() -> void:
	balance_label.text = "$%d" % jobs.balance
	UI.clear(slots)
	for index in range(jobs.MAX_QUEUE):
		var panel := PanelContainer.new()
		var job: Dictionary = jobs.queue[index] if index < jobs.queue.size() else {}
		var accent: Color = Color("#3a4652") if job.is_empty() else BOXED if job.state == "boxed" else ON_BENCH
		panel.add_theme_stylebox_override("panel", UI.flat(Color("#1b2732"), 10, accent, 20))
		slots.add_child(panel)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 6)
		panel.add_child(inner)
		if job.is_empty():
			inner.add_child(UI.label("SLOT %d  ·  EMPTY" % (index + 1), 38, Color("#8b9aa8"), true))
			inner.add_child(UI.label("Accept a repair job on the shop computer.", 28, Color("#6d7c8a")))
			continue
		var head := HBoxContainer.new()
		inner.add_child(head)
		var name_label := UI.label("#%d  %s" % [job.id, job.customer], 40, Color.WHITE, true)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		head.add_child(UI.label("$%d" % job.pay, 40, Color("#8ee0a8"), true))
		inner.add_child(UI.label(job.model, 28, Color("#d5dde4")))
		inner.add_child(UI.label("IN BOX  ·  OPEN IT ON THE DESK" if job.state == "boxed" else "ON BENCH  ·  DIAGNOSING", 32, accent, true))
		var complaint := UI.label("\"%s\"" % job.complaint, 24, Color("#d5dde4"))
		complaint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		complaint.custom_minimum_size.x = PAGE_SIZE.x - 100
		inner.add_child(complaint)
	var result: Dictionary = jobs.last_result
	footer.text = "%d/%d slots in use" % [jobs.queue.size(), jobs.MAX_QUEUE] + ("" if result.is_empty() else
		"   ·   Last: #%d %s, %s" % [result.id, result.customer, "paid $%d" % result.amount if result.paid else "returned unfixed"])
