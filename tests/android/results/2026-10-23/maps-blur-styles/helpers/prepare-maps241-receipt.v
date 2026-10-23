import os

fn once(source string, old string, new string) string {
	assert source.count(old) == 1, 'Expected one occurrence: ' + old
	return source.replace(old, new)
}

fn main() {
	prior := 'tests/android/results/2026-10-23/maps-date-ranges/'
	out := 'tests/android/results/2026-10-23/maps-blur-styles/'
	assert !os.exists(out + 'retain.v'), 'Do not overwrite a prepared receipt'
	os.mkdir_all(out)!
	mut retain := os.read_file(prior + 'retain.v')!
	retain = retain.replace('240', '241')
		.replace('framework241-date-ranges', 'framework241-blur-styles')
		.replace('maps-window-insets', 'maps-date-ranges')
		.replace('source-delta-from239', 'source-delta-from240')
		.replace('02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1', '60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04')
	retain = once(retain, 'framework_sources.len == 109 && previous_framework.len == 108',
		'framework_sources.len == 110 && previous_framework.len == 109')
	retain = once(retain, "'tests/native-android-tools/androidtools/framework_date_ranges.v']",
		"'tests/native-android-tools/androidtools/framework_blur_styles.v']")
	retain = once(retain, "'android/graphics/Insets.smali', 'android/text/format/DateUtils.smali']",
		"'android/graphics/Insets.smali', 'android/text/format/DateUtils.smali',\n\t\t'android/graphics/BlurMaskFilter.smali', 'android/graphics/BlurMaskFilter\$Blur.smali']")
	retain = once(retain, "'snapshot-framework241.v', 'prepare241.v', 'run241.v'",
		"'snapshot-framework241.v', 'prepare241.v', 'finish-prepare241.v', 'run241.v'")
	retain = once(retain, 'Maps241 changes only the DateUtils formatter-based date-range implementation and its hook relative to Maps239.',
		'Maps241 changes only the BlurMaskFilter style enum generator and its hook relative to Maps240.')
	os.write_file(out + 'retain.v', retain)!
	mut validate := os.read_file(prior + 'validate.v')!
	validate = validate.replace('240', '241')
		.replace('framework241-date-ranges', 'framework241-blur-styles')
		.replace('maps-window-insets', 'maps-date-ranges')
		.replace('source-delta-from239', 'source-delta-from240')
		.replace('02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1', '60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04')
	validate = once(validate, 'framework.len == 109 && previous_framework.len == 108',
		'framework.len == 110 && previous_framework.len == 109')
	validate = once(validate, "'tests/native-android-tools/androidtools/framework_date_ranges.v']",
		"'tests/native-android-tools/androidtools/framework_blur_styles.v']")
	validate = once(validate, 'assert smali.len == 21', 'assert smali.len == 23')
	validate = once(validate, "\tassert os.read_file(out + '/streaming/prototype.log')",
		"\tblur := smali['android/graphics/BlurMaskFilter\$Blur.smali']\n\tfor style in ['NORMAL', 'SOLID', 'OUTER', 'INNER'] {\n\t\tassert blur.contains('.field public static final enum ' + style + ':Landroid/graphics/BlurMaskFilter\$Blur;'), style\n\t}\n\tassert blur.contains('.field final native_int:I')\n\tassert os.read_file(out + '/streaming/prototype.log')")
	start := validate.index("\t\tassert result['outcome']!.str() == 'startup_failed'") or { panic('result start missing') }
	end := validate.index("\t\tassert os.exists(out + '/observations.json')") or { panic('result end missing') }
	validate = validate[..start] + "\t\tassert log.contains('APK-SUITE-EXIT id=google-maps'), 'Require completed run'\n" + validate[end..]
	start_images := validate.index("\t\tfor name in ['map-before-input.png'") or { panic('image start missing') }
	end_images := validate.index("\t\tprintln('MAPS241-INTEGRITY PASS") or { panic('image end missing') }
	validate = validate[..start_images] + validate[end_images..]
	os.write_file(out + 'validate.v', validate)!
	os.write_file(out + 'README.md', 'Maps241 evidence capture is in progress. Application behavior will be recorded after the root agent reviews screenshots and the completed raw result.\n\nFramework241 contains 110 exact V sources; native235 contains 83 unchanged sources. Relative to Maps240, only the BlurMaskFilter style enum generator and its framework hook change. The frozen suite239-stream binary and all APKs are unchanged. Pre-run identities were retained before image injection; staged identities identify the runtime module.\n')!
	println('MAPS241 receipt helpers prepared; result remains pending')
}
