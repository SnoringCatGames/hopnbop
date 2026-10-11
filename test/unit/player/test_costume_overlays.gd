extends GutTest
## Costume overlays, including the crown, draw on top of the
## bunny's own body-type sheet, so they must contain only the
## costume. An overlay exported with a body layer visible paints
## that body over every bunny. The crown sheet did this, turning
## every crowned bunny brown.


## An overlay covering more than this fraction of a body's pixels
## is a full-body export. The crown sits on the head and covers
## about a quarter.
const _MAX_BODY_COVERAGE := 0.5


func test_crown_leaves_body_visible() -> void:
	assert_not_null(G.settings.crown_costume)
	_assert_overlay_leaves_bodies_visible(G.settings.crown_costume)


func test_costumes_leave_body_visible() -> void:
	var checked_count := 0
	for costume in G.settings.costumes:
		if is_instance_valid(costume.sprite_sheet):
			_assert_overlay_leaves_bodies_visible(costume)
			checked_count += 1
	if checked_count == 0:
		pass_test("No costume has an overlay sheet yet")


func _assert_overlay_leaves_bodies_visible(
	costume: CostumeConfig,
) -> void:
	var overlay_alpha := _get_opaque_mask(costume.sprite_sheet)
	assert_gt(
		overlay_alpha.size(),
		0,
		"%s sheet loaded" % costume.display_name,
	)
	for body_type in G.settings.body_types:
		var body_alpha := _get_opaque_mask(body_type.sprite_sheet)
		assert_eq(
			overlay_alpha.size(),
			body_alpha.size(),
			"%s and %s use the same sheet template" % [
				costume.display_name,
				body_type.display_name,
			],
		)
		if overlay_alpha.size() != body_alpha.size():
			continue

		var body_pixel_count := 0
		var covered_pixel_count := 0
		for i in body_alpha.size():
			if body_alpha[i] == 0:
				continue
			body_pixel_count += 1
			if overlay_alpha[i] != 0:
				covered_pixel_count += 1
		var coverage := (
			float(covered_pixel_count) / maxi(body_pixel_count, 1))
		assert_lt(
			coverage,
			_MAX_BODY_COVERAGE,
			"%s covers %d%% of %s, so it hides the body color" % [
				costume.display_name,
				roundi(coverage * 100.0),
				body_type.display_name,
			],
		)


## Returns one byte per pixel: 1 where the texture is opaque at
## all, 0 where it is fully transparent.
static func _get_opaque_mask(texture: Texture2D) -> PackedByteArray:
	var mask := PackedByteArray()
	var image := texture.get_image()
	if image == null:
		return mask
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	mask.resize(data.size() / 4)
	for i in mask.size():
		mask[i] = 1 if data[i * 4 + 3] > 0 else 0
	return mask
