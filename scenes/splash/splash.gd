extends Control

@export_file var load_scene: String

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	ResourceLoader.load_threaded_request(load_scene)
	item_rect_changed.connect(_on_item_rect_changed)
	_on_item_rect_changed()


var _switching: bool = false


func _process(_delta: float) -> void:
	if _switching:
		return
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		load_scene
	)

	if status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
		_switching = true
		var scene: PackedScene = ResourceLoader.load_threaded_get(load_scene)
		_switch_to_scene(scene)
	elif status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_FAILED or status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_INVALID_RESOURCE:
		# the threaded load gave up: load it the plain way rather than stay on the dino forever
		_switching = true
		_switch_to_scene(load(load_scene))


## The blink is a nicety: if its end never comes, the editor opens anyway (russian-monologue —
## the splash once stayed up for good).
func _switch_to_scene(scene: PackedScene) -> void:
	sprite.play("blink")
	var done: Array = []
	sprite.animation_finished.connect(func() -> void: done.append(true), CONNECT_ONE_SHOT)
	var waited: float = 0.0
	while done.is_empty() and waited < 1.5:
		await get_tree().process_frame
		waited += get_process_delta_time()

	get_tree().change_scene_to_packed(scene)


func _on_item_rect_changed() -> void:
	var vp: Rect2 = get_viewport_rect()
	sprite.global_position = vp.size / 2
