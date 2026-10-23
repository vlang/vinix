import os

fn once(source string, old string, new string) string {
	assert source.count(old) == 1, 'Expected one occurrence: ' + old
	return source.replace(old, new)
}

fn main() {
	prior := 'tests/android/results/2026-10-23/maps-canvas-save/'
	out := 'tests/android/results/2026-10-23/maps-popup-menus/'
	assert !os.exists(out + 'retain.v'), 'Do not overwrite a prepared receipt'
	os.mkdir_all(out)!
	mut retain := os.read_file(prior + 'retain.v')!
	retain = retain.replace('242', '243').replace('native235', 'native236')
		.replace('framework243-canvas-save', 'framework243-popup-menus')
		.replace('maps-blur-styles', 'maps-canvas-save')
		.replace('source-delta-from241', 'source-delta-from242')
		.replace('8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74', '0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc')
		.replace('0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9', '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d')
	retain = once(retain, 'framework_sources.len == 111 && previous_framework.len == 110',
		'framework_sources.len == 112 && previous_framework.len == 111')
	retain = once(retain, 'assert delta.len == 2', 'assert delta.len == 3')
	retain = once(retain, "['tests/native-android-tools/androidtools/framework_startup.v',\n\t\t'tests/native-android-tools/androidtools/framework_canvas_save_flags.v']",
		"['tests/native-android-tools/androidtools/framework_classes.v',\n\t\t'tests/native-android-tools/androidtools/framework_popup_menus.v',\n\t\t'build-support/android/atlframework/menus.v']")
	retain = once(retain, "\tpre := json2.decode[map[string]string]",
		r'\tprevious_native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + "/../maps-canvas-save/native/exact-sources.json.gz")!)!.bytestr())!
\tassert previous_native.len == native_sources.len
\tmut native_delta := map[string]map[string]string{}
\tfor name, source in native_sources {
\t\tassert name in previous_native, name
\t\tif source != previous_native[name] {
\t\t\tnative_delta[name] = {"previous_sha256": sha256.sum(previous_native[name].bytes()).hex(), "current_sha256": sha256.sum(source.bytes()).hex()}
\t\t}
\t}
\tassert native_delta.len == 1 && "menus.v" in native_delta
\tos.mkdir_all(out + "/native")!
\tos.write_file(out + "/native/source-delta-from235.json", json2.encode(native_delta, prettify: true) + "\n")!
\tpre := json2.decode[map[string]string]'.replace('"', "'").replace('\\t', '\t'))
	retain = once(retain, "\t\t'native236-reviewed-overlays.json':        'native/reviewed-overlays.json'\n", '')
	retain = once(retain, "'native236-source-delta.json':             'native/source-delta-from233.json'",
		"'native236-source-delta.json':             'native/builder-source-delta-from235.json'")
	retain = once(retain, "'android/graphics/Canvas.smali', 'android/atl/GskCanvas.smali']",
		"'android/graphics/Canvas.smali', 'android/atl/GskCanvas.smali',\n\t\t'android/widget/PopupMenu.smali', 'android/widget/VinixPopupMenuClick.smali',\n\t\t'android/widget/VinixPopupMenuDismiss.smali', 'android/view/VinixMenu.smali',\n\t\t'android/view/VinixMenuItem.smali']")
	retain = once(retain, "\t\t'native236-build.log':     'native236-build.log'\n\t\tframework + 'build.log':   'framework243-build.log'\n\t\tframework + 'compile.log': 'framework243-compile.log'",
		"\t\t'build-native236.log': 'native236-build.log'\n\t\t'build-framework243.log': 'framework243-build.log'\n\t\t'build-framework243-compile.log': 'framework243-compile.log'")
	retain = once(retain, 'Maps243 changes only the Canvas saveLayer flags overload generator and its hook relative to Maps241. Native235 path precision and the independently tested frozen suite239-stream staging helper are unchanged.',
		'Maps243 replaces the PopupMenu GTK presentation with a real Dialog and VinixMenu model relative to Maps242. The 112-source framework changes framework_classes.v, framework_popup_menus.v, and its recorded atlframework/menus.v input. Native236 changes only menus.v relative to native235 to resolve menu resources through Context, propagate submenu context, and guard Activity-only action expansion. Native path precision and the independently tested frozen suite239-stream staging helper are unchanged.')
	os.write_file(out + 'retain.v', retain)!
	mut validate := os.read_file(prior + 'validate.v')!
	validate = validate.replace('242', '243').replace('native235', 'native236')
		.replace('framework243-canvas-save', 'framework243-popup-menus')
		.replace('maps-blur-styles', 'maps-canvas-save')
		.replace('source-delta-from241', 'source-delta-from242')
		.replace('8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74', '0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc')
		.replace('0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9', '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d')
	validate = once(validate, 'framework.len == 111 && previous_framework.len == 110', 'framework.len == 112 && previous_framework.len == 111')
	validate = once(validate, "['tests/native-android-tools/androidtools/framework_startup.v',\n\t\t\t'tests/native-android-tools/androidtools/framework_canvas_save_flags.v']",
		"['tests/native-android-tools/androidtools/framework_classes.v',\n\t\t\t'tests/native-android-tools/androidtools/framework_popup_menus.v',\n\t\t\t'build-support/android/atlframework/menus.v']")
	validate = once(validate, 'changed == 2 && delta.len == 2', 'changed == 3 && delta.len == 3')
	validate = once(validate, "out + '/../interpolators/fixed-native-sources.json.gz'", "out + '/../maps-canvas-save/native/exact-sources.json.gz'")
	validate = once(validate, "\tassert native == prior_native, 'Maps243 must reuse the exact native236 sources'",
		r'\tassert prior_native.len == native.len
\tnative_delta := json2.decode[map[string]map[string]string](os.read_file(out + "/native/source-delta-from235.json")!)!
\tmut native_changed := 0
\tfor path, source in native {
\t\tassert path in prior_native, path
\t\tif source == prior_native[path] { continue }
\t\tassert path == "menus.v"
\t\tassert native_delta[path]["previous_sha256"] == sha256.sum(prior_native[path].bytes()).hex()
\t\tassert native_delta[path]["current_sha256"] == sha256.sum(source.bytes()).hex()
\t\tnative_changed++
\t}
\tassert native_changed == 1 && native_delta.len == 1'.replace('"', "'").replace('\\t', '\t'))
	validate = once(validate, "for path in ['libnative236.so', 'GoogleMaps.apk'", "for path in ['GoogleMaps.apk'")
	validate = once(validate, "if path.ends_with('/api-impl.jar') { continue }",
		"if path.ends_with('/api-impl.jar') || path.ends_with('/libvinix-android-native.so') { continue }")
	validate = once(validate, 'assert smali.len == 25', 'assert smali.len == 30')
	validate = once(validate, "\tassert os.read_file(out + '/streaming/prototype.log')",
		r'\tpopup := smali["android/widget/PopupMenu.smali"]
\tassert popup.contains("vinixDialog:Landroid/app/Dialog;")
\tassert popup.contains("Landroid/app/Dialog;->show()V")
\tassert popup.contains("Landroid/view/VinixMenu;-><init>(Landroid/content/Context;)V")
\tassert !popup.contains(" native ") && !popup.contains("MenuImpl;")
\tassert smali["android/widget/VinixPopupMenuClick.smali"].contains("vinixActivate(Landroid/view/MenuItem;Landroid/app/Dialog;)V")
\tassert smali["android/widget/VinixPopupMenuDismiss.smali"].contains("notified:Z")
\tassert smali["android/view/VinixMenu.smali"].contains(".field private vinixContext:Landroid/content/Context;")
\tassert smali["android/view/VinixMenuItem.smali"].contains("vinixInvokeClick()Z")
\tassert os.read_file(out + "/streaming/prototype.log")'.replace('"', "'").replace('\\t', '\t'))
	start := validate.index("\t\tassert result['outcome']!.str() == 'startup_failed'") or { panic('result start missing') }
	end := validate.index("\t\tassert os.exists(out + '/observations.json')") or { panic('result end missing') }
	validate = validate[..start] + "\t\tassert log.contains('APK-SUITE-EXIT id=google-maps'), 'Require completed run'\n" + validate[end..]
	start_images := validate.index("\t\tfor name in ['map-before-input.png'") or { panic('image start missing') }
	end_images := validate.index("\t\tprintln('MAPS243-INTEGRITY PASS") or { panic('image end missing') }
	validate = validate[..start_images] + validate[end_images..]
	os.write_file(out + 'validate.v', validate)!
	os.write_file(out + 'README.md', 'Maps243 evidence capture is in progress. Actual behavior will be recorded after root reviews the completed raw result and screenshots.\n\nFramework243 retains112 exact V sources with PopupMenu generator, framework_classes hook, and menus.v input delta relative to Maps242. Native236 retains83 sources with menus.v as its only delta from native235. The APKs, suite239-stream and launcher are unchanged. Pre-run identities were retained before image injection; staged identities will identify the actual runtime module.\n')!
	println('MAPS243 receipt helpers prepared; result remains pending')
}
