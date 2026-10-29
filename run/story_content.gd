class_name StoryContent
extends RefCounted
## Loader for the story beats under res://data/story/. Beats are indexed in
## train order; RunState's STORY stops refer to them by index.

const BEAT_PATHS: Array[String] = [
	"res://data/story/boarding.tres",
	"res://data/story/conductor.tres",
	"res://data/story/empty_platform.tres",
	"res://data/story/last_light.tres",
]


static func beat_count() -> int:
	return BEAT_PATHS.size()


## Returns null (after logging an error) if the index is out of range or the
## resource is missing or not a StoryBeat.
static func beat(index: int) -> StoryBeat:
	if index < 0 or index >= BEAT_PATHS.size():
		push_error("StoryContent.beat: no beat at index %d" % index)
		return null
	var path := BEAT_PATHS[index]
	var loaded: StoryBeat = null
	if ResourceLoader.exists(path):
		loaded = load(path) as StoryBeat
	if loaded == null:
		push_error("StoryContent: missing or non-StoryBeat resource: %s" % path)
	return loaded
