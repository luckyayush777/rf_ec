extends RefCounted
## Helpers for native Control pages drawn onto in-world screens (the shop computer and the
## job-queue display). Each page lives in its own SubViewport whose texture lights a PlaneMesh.

const INK := Color("#1d2630")
const MUTED := Color("#5d6b78")
const PAID := Color("#2f9e5b")
const WARN := Color("#c4462f")

## Renders a page of `size` pixels onto the screen mesh, unshaded so it reads as a lit panel.
## A shader (the shop computer's CRT) receives the page as its `page` uniform instead.
static func attach_viewport(screen: MeshInstance3D, size: Vector2i, shader: Shader = null) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Page"
	viewport.size = size
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.add_child(viewport)
	if shader != null:
		var tube := ShaderMaterial.new()
		tube.shader = shader
		tube.set_shader_parameter("page", viewport.get_texture())
		tube.set_shader_parameter("page_size", Vector2(size))
		screen.material_override = tube
		return viewport
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material
	return viewport

## Terminal type for retro pages; falls back to the default font where none is installed.
static func mono_font(bold: bool = false) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	font.font_weight = 700 if bold else 400
	return font

static func flat(color: Color, radius: int = 0, border: Color = Color.TRANSPARENT, padding: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(2)
	box.set_content_margin_all(padding)
	return box

static func label(text: String, size: int, color: Color = INK, bold: bool = false) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	if bold: item.add_theme_font_override("font", bold_font())
	return item

static func bold_font() -> Font:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.9
	return font

static func button(text: String, size: int, accent: Color) -> Button:
	var item := Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_NONE
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_font_override("font", bold_font())
	item.add_theme_stylebox_override("normal", flat(accent, 6, Color.TRANSPARENT, 14))
	item.add_theme_stylebox_override("hover", flat(accent.lightened(0.15), 6, Color.TRANSPARENT, 14))
	item.add_theme_stylebox_override("pressed", flat(accent.darkened(0.2), 6, Color.TRANSPARENT, 14))
	item.add_theme_stylebox_override("disabled", flat(Color("#c3cad1"), 6, Color.TRANSPARENT, 14))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		item.add_theme_color_override(state, Color.WHITE)
	item.add_theme_color_override("font_disabled_color", Color("#7a858f"))
	return item

static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
