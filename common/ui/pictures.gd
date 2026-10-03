## Small pictures beside names (russian-monologue): a character's default portrait, an item's
## icon. Shown on graph cards, in pickers and in collection lists, so the eye finds a face before
## it reads a name. Kept small and quiet — a rounded thumbnail, never a frame — and switched off
## as a whole in Preferences → Interface → Show pictures.
class_name Pictures

const SETTING: String = "show_pictures"
## Thumbnails are cut at twice the size they are drawn, so they stay sharp on a retina screen.
const SHARPNESS: int = 2

static var _thumbs: Dictionary = {}


static func enabled() -> bool:
	return bool(ConfigManager.get_config(SETTING, true))


## The picture for [param target_id] in [param scope] ("characters" or "items"), or null.
static func of(project: MonologueProject, scope: String, target_id: String, size: int = 20) -> Texture2D:
	if not enabled() or project == null or target_id.is_empty():
		return null
	var collection: CollectionDocument = project.get_collection(scope)
	if collection == null:
		return null
	for record: Variant in collection.get_value():
		if record is Dictionary and str(record.get("id", "")) == target_id:
			return thumb(project, _path_of(record), size, scope == "characters")
	return null


## The image a stored character or item record shows: an item's icon, a character's default
## portrait (or its first one with an image).
static func _path_of(record: Dictionary) -> String:
	if str(record.get("icon", "")) != "":
		return str(record["icon"])
	var portraits: Variant = record.get("portraits", [])
	if portraits is Array:
		var first: String = ""
		for portrait: Variant in portraits:
			if portrait is not Dictionary or str(portrait.get("image", "")) == "":
				continue
			if portrait.get("is_default", false) == true:
				return str(portrait["image"])
			if first.is_empty():
				first = str(portrait["image"])
		return first
	return ""


## [param path] as a thumbnail [param size] points across, centre-cropped and cut to shape
## (a circle for a face, a soft square for a thing) in the image itself; cached.
static func thumb(project: MonologueProject, path: String, size: int, round: bool = true) -> Texture2D:
	if path.is_empty():
		return null
	var absolute: String = path
	if path.is_relative_path() and not path.begins_with("res://") and project and not project.project_path.is_empty():
		absolute = project.project_path.get_base_dir().path_join(path).simplify_path()
	var key: String = "%s@%d%s" % [absolute, size, "o" if round else "q"]
	if _thumbs.has(key):
		return _thumbs[key]
	var texture: Texture2D = null
	var image: Image = Image.load_from_file(absolute) if FileAccess.file_exists(absolute) else null
	if image != null and not image.is_empty():
		var side: int = mini(image.get_width(), image.get_height())
		image = image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
		var pixels: int = size * SHARPNESS
		image.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGBA8)
		_cut(image, pixels / 2.0 if round else maxf(4.0, pixels / 5.0))
		texture = ImageTexture.create_from_image(image)
	_thumbs[key] = texture
	return texture


## Clears the corners outside a rounded square of corner [param radius] (half the side makes a
## circle), with a one-pixel soft edge; everything a touch quieter than the text beside it.
static func _cut(image: Image, radius: float) -> void:
	var n: int = image.get_width()
	for y: int in n:
		for x: int in n:
			# distance outside the rounded square, measured from the nearest corner's centre
			var cx: float = clampf(x + 0.5, radius, n - radius)
			var cy: float = clampf(y + 0.5, radius, n - radius)
			var outside: float = Vector2(x + 0.5 - cx, y + 0.5 - cy).length() - radius
			var c: Color = image.get_pixel(x, y)
			c.a *= clampf(0.5 - outside, 0.0, 1.0) * 0.92
			image.set_pixel(x, y, c)


## A rounded picture to sit before a name: a circle for a character, a soft square for an item.
## Null when there is nothing to show, so callers simply skip it.
static func badge(project: MonologueProject, scope: String, target_id: String, size: int = 20) -> Control:
	return _rect(of(project, scope, target_id, size), size)


## The same, for a record itself (a row of the character, item or portrait list).
static func badge_for(project: MonologueProject, record: Dictionary, size: int = 20) -> Control:
	if not enabled():
		return null
	var path: String = str(record.get("image", "")) if record.get("$type", "") == "portrait" else _path_of(record)
	return _rect(thumb(project, path, size, record.get("$type", "") != "item"), size)


static func _rect(texture: Texture2D, size: int) -> Control:
	if texture == null:
		return null
	var picture: TextureRect = TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = Vector2(size, size)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


## Forgets every thumbnail, after a picture changed on disk or the setting was flipped.
static func clear() -> void:
	_thumbs.clear()
