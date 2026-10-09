// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_bitmap_snapshots_codecs_and_nested_contexts_release_all_objects() {
	objc_start()
	defer { objc_stop() }
	for _ in 0 .. 100 {
		pool := objc_pool_push()
		ui_begin_image_options(ObjSize{8, 4}, false, 2)
		context := ui_current_context()
		assert cg_bitmap_width(context) == 16 && cg_bitmap_height(context) == 8
		assert cg_bitmap_info(context) == 0x2002
		cg_rgb_fill(context, 1, 0, 0, 0.5)
		cg_fill_rect(context, ObjRect{0, 0, 8, 4})
		assert bitmap_pixel(context, 0, 0) == [u32(128), 0, 0, 128]!
		image := ui_image_snapshot()
		ui_begin_image(ObjSize{2, 2})
		assert ui_current_context() != context
		ui_end_image()
		assert ui_current_context() == context
		cg_clear_rect(context, ObjRect{0, 0, 8, 4})
		ui_end_image()
		assert ui_current_context() == 0
		original := obj_header(image).fields[0]
		assert bitmap_pixel(original, 0, 0) == [u32(128), 0, 0, 128]!
		png := ui_png(image)
		decoded := ui_image_decode(png)
		assert decoded != 0 && bitmap_pixel(decoded, 0, 0) == bitmap_pixel(original, 0, 0)
		provider := cg_image_provider(decoded)
		bytes := cg_provider_data(provider)
		assert data_length(bytes) == i64(cg_bitmap_stride(decoded) * cg_bitmap_height(decoded))
		objc_release(bytes)
		objc_release(decoded)
		jpeg := ui_jpeg(image, 1)
		lossy := ui_image_decode(jpeg)
		assert lossy != 0
		pixel := bitmap_pixel(lossy, 0, 0)
		assert pixel[0] >= 253 && pixel[1] >= 125 && pixel[1] <= 129 && pixel[3] == 255
		objc_release(lossy)
		objc_pool_pop(pool)
		assert ios_runtime.live == 0
	}
}
