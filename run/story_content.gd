class_name StoryContent
extends RefCounted
## Loader for the story beats under res://data/story/. Beats are indexed in
## train order; RunState's STORY stops refer to them by index. Characters can
## override a beat (see beat()); the neutral files are the fallback.

const BEAT_PATHS: Array[String] = [
	"res://data/story/boarding.tres",
	"res://data/story/conductor.tres",
	"res://data/story/empty_platform.tres",
	"res://data/story/last_light.tres",
]


static func beat_count() -> int:
	return BEAT_PATHS.size()


## Returns null (after logging an error) if the index is out of range or the
## resource is missing or not a StoryBeat. A character's own version of the beat
## (same file name under res://data/story/<character id>/) wins when it exists.
static func beat(index: int, character_id: StringName = &"") -> StoryBeat:
	if index < 0 or index >= BEAT_PATHS.size():
		push_error("StoryContent.beat: no beat at index %d" % index)
		return null
	var path := BEAT_PATHS[index]
	if character_id != &"":
		var own_path := "res://data/story/%s/%s" % [character_id, path.get_file()]
		if ResourceLoader.exists(own_path):
			path = own_path
	var loaded: StoryBeat = null
	if ResourceLoader.exists(path):
		loaded = load(path) as StoryBeat
	if loaded == null:
		push_error("StoryContent: missing or non-StoryBeat resource: %s" % path)
	return loaded
