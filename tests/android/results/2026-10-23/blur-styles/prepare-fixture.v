import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps/blur241')
	apk := os.abs_path('build/android-maps/blur241-apk')
	assert !os.exists(b) && !os.exists(apk)
	os.mkdir_all(b + '/source/startupfixture')!
	os.cp_all(os.abs_path('build/android-maps/dates240-apk'), apk, false)!
	mut hashes := map[string]string{}
	for path in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
		text := os.read_file(path)!
		name := os.base(path)
		os.write_file(b + '/source/startupfixture/' + name, text)!
		hashes[name] = sha256.sum(text.bytes()).hex()
	}
	os.write_file(b + '/fixture-source-sha256.json', json2.encode(hashes, prettify: true) + '\n')!
	for mode in ['baseline', 'fixed'] {
		dir := b + '/native-' + mode
		os.mkdir_all(dir)!
		for name in os.ls('build/android-maps/interpolators234/native-fixed235')! {
			if name == 'api-impl.jar' { continue }
			os.symlink(os.abs_path('build/android-maps/interpolators234/native-fixed235/' + name), dir + '/' + name)!
		}
		jar := if mode == 'baseline' { 'framework240-date-ranges' } else { 'framework241-blur-styles' }
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/dates240/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = apk + '/bootstrap.apk'
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(b + '/staged-hashes.v', os.read_file('build/android-maps/dates240/staged-hashes.v')!.replace('dates240', 'blur241'))!
	os.write_file('build/android-maps/build-blur241.v', os.read_file('build/android-maps/build-dates240.v')!.replace('dates240-apk', 'blur241-apk').replace('DATES240 APK', 'BLUR241 APK'))!
	os.write_file('build/android-maps/prepare-blur-proof241.v', os.read_file('build/android-maps/prepare-dates-proof240.v')!.replace('dates240', 'blur241').replace('framework239-insets', 'framework240-date-ranges').replace("else { 'framework240-date-ranges' }", "else { 'framework241-blur-styles' }").replace('Landroid/text/format/DateUtils;,Landroid/text/format/DateFormat;', 'Landroid/graphics/BlurMaskFilter;,Landroid/graphics/BlurMaskFilter$Blur;').replace('Lorg/vinix/bootstrap/DateRangesProbe;,Lorg/vinix/bootstrap/FailRangeAppendable;', 'Lorg/vinix/bootstrap/BlurStylesProbe;').replace('DATE-RANGES PROOF PREPARED actual signed APK and DateUtils DEX', 'BLUR-STYLES PROOF PREPARED actual signed APK and BlurMaskFilter DEX'))!
	println('BLUR241 PREPARED native235 unchanged, identical signed APK for baseline240/fixed241')
}
