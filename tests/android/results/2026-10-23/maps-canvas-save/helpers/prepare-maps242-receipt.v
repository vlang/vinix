import os

fn once(source string, old string, new string) string {
	assert source.count(old) == 1, 'Expected one occurrence: ' + old
	return source.replace(old, new)
}

fn main() {
	prior := 'tests/android/results/2026-10-23/maps-blur-styles/'
	out := 'tests/android/results/2026-10-23/maps-canvas-save/'
	assert !os.exists(out + 'retain.v'), 'Do not overwrite a prepared receipt'
	os.mkdir_all(out)!
	mut retain := os.read_file(prior + 'retain.v')!
	retain = retain.replace('241', '242')
		.replace('framework242-blur-styles', 'framework242-canvas-save')
		.replace('maps-date-ranges', 'maps-blur-styles')
		.replace('source-delta-from240', 'source-delta-from241')
		.replace('60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04', '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74')
	retain = once(retain, 'framework_sources.len == 110 && previous_framework.len == 109',
		'framework_sources.len == 111 && previous_framework.len == 110')
	retain = once(retain, "'tests/native-android-tools/androidtools/framework_blur_styles.v']",
		"'tests/native-android-tools/androidtools/framework_canvas_save_flags.v']")
	retain = once(retain, "'android/graphics/BlurMaskFilter.smali', 'android/graphics/BlurMaskFilter\$Blur.smali']",
		"'android/graphics/BlurMaskFilter.smali', 'android/graphics/BlurMaskFilter\$Blur.smali',\n\t\t'android/graphics/Canvas.smali', 'android/atl/GskCanvas.smali']")
	retain = once(retain, 'Maps242 changes only the BlurMaskFilter style enum generator and its hook relative to Maps240.',
		'Maps242 changes only the Canvas saveLayer flags overload generator and its hook relative to Maps241.')
	os.write_file(out + 'retain.v', retain)!
	mut validate := os.read_file(prior + 'validate.v')!
	validate = validate.replace('241', '242')
		.replace('framework242-blur-styles', 'framework242-canvas-save')
		.replace('maps-date-ranges', 'maps-blur-styles')
		.replace('source-delta-from240', 'source-delta-from241')
		.replace('60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04', '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74')
	validate = once(validate, 'framework.len == 110 && previous_framework.len == 109',
		'framework.len == 111 && previous_framework.len == 110')
	validate = once(validate, "'tests/native-android-tools/androidtools/framework_blur_styles.v']",
		"'tests/native-android-tools/androidtools/framework_canvas_save_flags.v']")
	validate = once(validate, 'assert smali.len == 23', 'assert smali.len == 25')
	validate = once(validate, "\tassert os.read_file(out + '/streaming/prototype.log')",
		"\tcanvas := smali['android/graphics/Canvas.smali']\n\tassert canvas.contains('.method public saveLayer(FFFFLandroid/graphics/Paint;I)I')\n\tassert canvas.contains('invoke-virtual/range {p0 .. p5}, Landroid/graphics/Canvas;->saveLayer(FFFFLandroid/graphics/Paint;)I')\n\tassert smali['android/atl/GskCanvas.smali'].contains('.method public save()I')\n\tassert os.read_file(out + '/streaming/prototype.log')")
	start := validate.index("\t\tassert result['outcome']!.str() == 'startup_failed'") or { panic('result start missing') }
	end := validate.index("\t\tassert os.exists(out + '/observations.json')") or { panic('result end missing') }
	validate = validate[..start] + "\t\tassert log.contains('APK-SUITE-EXIT id=google-maps'), 'Require completed run'\n" + validate[end..]
	start_images := validate.index("\t\tfor name in ['map-before-input.png'") or { panic('image start missing') }
	end_images := validate.index("\t\tprintln('MAPS242-INTEGRITY PASS") or { panic('image end missing') }
	validate = validate[..start_images] + validate[end_images..]
	os.write_file(out + 'validate.v', validate)!
	os.write_file(out + 'README.md', 'Maps242 evidence capture is in progress. Application behavior will be recorded after the root agent reviews screenshots and the completed raw result.\n\nFramework242 contains 111 exact V sources; native235 contains 83 unchanged sources. Relative to Maps241, only the Canvas saveLayer flags overload generator and its framework hook change. The frozen suite239-stream binary and all APKs are unchanged. Pre-run identities were retained before image injection; staged identities identify the runtime module.\n')!
	println('MAPS242 receipt helpers prepared; result remains pending')
}
