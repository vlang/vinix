import os
import json2
import crypto.sha256

fn main() {
	b := os.abs_path('build/android-maps/canvas242')
	apk := os.abs_path('build/android-maps/canvas242-apk')
	assert !os.exists(b) && !os.exists(apk)
	os.mkdir_all(b + '/source/startupfixture')!
	os.cp_all(os.abs_path('build/android-maps/blur241-apk'), apk, false)!
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
		jar := if mode == 'baseline' { 'framework241-blur-styles' } else { 'framework242-canvas-save' }
		os.symlink(os.abs_path('build/android-maps/' + jar + '/api-impl.jar'), dir + '/api-impl.jar')!
		mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/blur241/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map()
		app['apk'] = apk + '/bootstrap.apk'
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['native_dir'] = dir
		config['output'] = b + '/run-' + mode
		os.write_file(b + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
	}
	os.write_file(b + '/staged-hashes.v', os.read_file('build/android-maps/blur241/staged-hashes.v')!.replace('blur241', 'canvas242'))!
	os.write_file('build/android-maps/build-canvas242.v', os.read_file('build/android-maps/build-blur241.v')!.replace('blur241-apk', 'canvas242-apk').replace('BLUR241 APK', 'CANVAS242 APK'))!
	os.write_file('build/android-maps/prepare-canvas-proof242.v', os.read_file('build/android-maps/prepare-blur-proof241.v')!.replace('blur241', 'canvas242').replace('framework241-blur-styles', 'framework242-canvas-save').replace('framework240-date-ranges', 'framework241-blur-styles').replace('Landroid/graphics/BlurMaskFilter;,Landroid/graphics/BlurMaskFilter$Blur;', 'Landroid/graphics/Canvas;,Landroid/graphics/VinixPictureCanvas;,Landroid/graphics/VinixPictureCommand;,Landroid/graphics/RecordingCanvas;').replace('Lorg/vinix/bootstrap/BlurStylesProbe;', 'Lorg/vinix/bootstrap/CanvasSaveFlagsProbe;,Lorg/vinix/bootstrap/SaveLayerForwardCanvas;').replace('BLUR-STYLES PROOF PREPARED actual signed APK and BlurMaskFilter DEX', 'CANVAS-SAVE-FLAGS PROOF PREPARED actual signed APK and Canvas DEX'))!
	println('CANVAS242 PREPARED native235 unchanged, identical signed APK for baseline241/fixed242')
}
