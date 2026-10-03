extends AudioStreamPlayer
## A supplied recording that loops while a tool works a surface: the spudger scrape, the IPA
## wipe (paste faces and the fan shaft) or the paste squeeze. The tool reports contact every frame it works (set_contact); loudness follows that
## report and fades out once the reports stop. Without the recording the player stays silent.
## Recordings are looped in code over their whole length, so trim them to a seamless loop.
## Reports older than this mean the tool has lifted off.
const HOLD := 0.08
const FADE := 12.0

var muted := false
var target := 0.0
var level := 0.0
var report_age := 1.0
var trim_db := 0.0

func _init(player_name: String, recording: String, channel: StringName, trim: float = 0.0) -> void:
	name = player_name
	bus = channel
	trim_db = trim
	volume_db = -80.0
	if ResourceLoader.exists(recording):
		var source := load(recording) as AudioStreamWAV
		if source != null:
			var looped := source.duplicate() as AudioStreamWAV
			looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
			looped.loop_begin = 0
			looped.loop_end = int(looped.get_length() * looped.mix_rate)
			stream = looped

## amount: 0-1 loudness from stroke speed and how much the tool is removing.
func set_contact(amount: float) -> void:
	target = clampf(amount, 0.0, 1.0)
	report_age = 0.0

func set_muted(value: bool) -> void:
	muted = value

func _process(delta: float) -> void:
	report_age += delta
	if report_age > HOLD: target = 0.0
	level = move_toward(level, target, delta * FADE * (1.0 if target > level else 0.5))
	if stream == null: return
	if level > 0.001 and not playing: play()
	elif level <= 0.001 and playing: stop()
	volume_db = -80.0 if muted else trim_db + linear_to_db(maxf(level, 0.0001))
