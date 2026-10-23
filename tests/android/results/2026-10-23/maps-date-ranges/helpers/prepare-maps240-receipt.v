import os

fn replace_once(source string, old string, new string) string {
	assert source.count(old) == 1, 'Expected one occurrence: ' + old
	return source.replace(old, new)
}

fn main() {
	prior := 'tests/android/results/2026-10-23/maps-window-insets/'
	out := 'tests/android/results/2026-10-23/maps-date-ranges/'
	assert !os.exists(out + 'retain.v'), 'Do not overwrite a prepared receipt'
	os.mkdir_all(out)!
	mut retain := os.read_file(prior + 'retain.v')!
	retain = retain.replace('framework239-insets', 'framework240-date-ranges')
		.replace('68ad3466f9a8c84770fa0e40e39d1a3b0b6666f2b6d7ca67aeab53e6785e3aae', '02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1')
		.replace('maps-texture-transform', 'maps-window-insets')
		.replace('source-delta-from236', 'source-delta-from239')
		.replace('identity239', 'identity240').replace('attempt239', 'attempt240')
		.replace('framework239', 'framework240').replace('prepare239', 'prepare240')
		.replace('run239', 'run240').replace('interact239', 'interact240')
		.replace('manual239', 'manual240').replace('verify-maps239', 'verify-maps240')
		.replace('prepare-maps239', 'prepare-maps240').replace('pan239', 'pan240')
		.replace('map-wait239', 'map-wait240').replace('wait-map239', 'wait-map240')
		.replace('MAPS239', 'MAPS240')
	retain = replace_once(retain, 'framework_sources.len == 108 && previous_framework.len == 106',
		'framework_sources.len == 109 && previous_framework.len == 108')
	retain = replace_once(retain, 'assert delta.len == 3', 'assert delta.len == 2')
	retain = replace_once(retain, "\t\t'tests/native-android-tools/androidtools/framework_insets.v',\n\t\t'tests/native-android-tools/androidtools/framework_lookup_trace.v']", "\t\t'tests/native-android-tools/androidtools/framework_date_ranges.v']")
	retain = replace_once(retain, "'android/graphics/Insets.smali']", "'android/graphics/Insets.smali', 'android/text/format/DateUtils.smali']")
	start := retain.index("\tfor name in ['results.json', 'run.log'] {") or { panic('start missing') }
	end := retain.index("\tfor path in os.walk_ext(base + 'interpolator-resources234', '') {") or { panic('end missing') }
	retain = retain[..start] + retain[end..]
	retain = replace_once(retain, 'Maps239 uses native235 path precision, framework240 WindowInsets value/Builder APIs, the framework237 opt-in view-lookup diagnostics, and the independently tested streaming module staging helper.',
		'Maps240 changes only the DateUtils formatter-based date-range implementation and its hook relative to Maps239. Native235 path precision and the independently tested frozen suite239-stream staging helper are unchanged.')
	os.write_file(out + 'retain.v', retain)!
	mut validate := os.read_file(prior + 'validate.v')!
	validate = validate.replace('framework239-insets', 'framework240-date-ranges')
		.replace('68ad3466f9a8c84770fa0e40e39d1a3b0b6666f2b6d7ca67aeab53e6785e3aae', '02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1')
		.replace('maps-texture-transform', 'maps-window-insets')
		.replace('source-delta-from236', 'source-delta-from239').replace('Maps239', 'Maps240')
		.replace('MAPS239', 'MAPS240')
	validate = replace_once(validate, 'framework.len == 108 && previous_framework.len == 106',
		'framework.len == 109 && previous_framework.len == 108')
	validate = replace_once(validate, "\t\t\t'tests/native-android-tools/androidtools/framework_insets.v',\n\t\t\t'tests/native-android-tools/androidtools/framework_lookup_trace.v']", "\t\t\t'tests/native-android-tools/androidtools/framework_date_ranges.v']")
	validate = replace_once(validate, 'changed == 3 && delta.len == 3', 'changed == 2 && delta.len == 2')
	start_pre := validate.index("\tprelaunch := json2.decode[[]json2.Any]") or { panic('prestart missing') }
	end_pre := validate.index("\tassert os.read_file(out + '/maps-resources/apk-sha256.txt')") or { panic('preend missing') }
	validate = validate[..start_pre] + validate[end_pre..]
	validate = replace_once(validate, 'assert smali.len == 20', 'assert smali.len == 21')
	validate = replace_once(validate, "\tassert os.read_file(out + '/streaming/prototype.log')", "\tdate_utils := smali['android/text/format/DateUtils.smali']\n\tassert date_utils.contains('formatDateRange(Landroid/content/Context;Ljava/util/Formatter;JJILjava/lang/String;)Ljava/util/Formatter;')\n\tassert date_utils.contains('Llibcore/icu/DateIntervalFormat;->formatDateRange(JJILjava/lang/String;)Ljava/lang/String;')\n\tassert os.read_file(out + '/streaming/prototype.log')")
	start_result := validate.index("\t\tassert result['outcome']!.str() == 'startup_failed'") or { panic('resultstart missing') }
	end_result := validate.index("\t\tassert os.exists(out + '/observations.json')") or { panic('resultend missing') }
	validate = validate[..start_result] + "\t\tlog := serial.bytestr()\n\t\tassert log.contains('APK-SUITE-EXIT id=google-maps'), 'Require completed app run'\n\t\tassert !log.contains('NoSuchMethodError: No static method formatDateRange(Landroid/content/Context;Ljava/util/Formatter;JJILjava/lang/String;)Ljava/util/Formatter;'), 'Prior DateUtils blocker must be reported if it recurs'\n" + validate[end_result..]
	validate = replace_once(validate, "\t\tassert observations['directions']!.str().len > 0", "\t\tassert observations['directions']!.str().len > 0\n\t\tassert observations['raw_outcome']!.str().starts_with(result['outcome']!.str()), 'Preserve raw classifier'\n\t\tassert observations['qualification']!.str().len > 0")
	os.write_file(out + 'validate.v', validate)!
	os.write_file(out + 'README.md', 'Maps240 evidence capture is in progress. Application behavior will be recorded after the root agent reviews actual screenshots and the completed raw result.\n\nThis run uses framework240 (109 exact V sources), unchanged native235 (83 sources), and the unchanged frozen suite239-stream binary. Relative to Maps239, only the DateUtils date-range generator and its framework hook change. Staged runtime identities and the seven pre-run kernel/image/EFI/QEMU/suite hashes are retained separately.\n')!
	println('MAPS240 RECEIPT HELPERS PREPARED')
}
