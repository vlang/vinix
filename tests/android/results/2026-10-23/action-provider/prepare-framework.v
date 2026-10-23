import os
import json2
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	previous := b + 'framework243-popup-menus'
	out := b + 'framework244-action-provider'
	assert !os.exists(out)
	manifest := json2.decode[map[string]json2.Any](os.read_file(previous + '/framework-manifest.json')!)!
	assert sha256.sum(os.read_bytes(previous + '/api-impl.jar')!).hex() == '0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc'
	os.mkdir_all(out + '/sources/androidtools')!
	for path, expected in manifest['sources']!.as_map() {
		frozen := if path.starts_with('tests/native-android-tools/androidtools/') {
			previous + '/sources/androidtools/' + os.base(path)
		} else { path }
		assert sha256.sum(os.read_bytes(frozen)!).hex() == expected.str(), path
	}
	for path in os.walk_ext(previous + '/sources/androidtools', '.v') {
		os.cp(path, out + '/sources/androidtools/' + os.base(path))!
	}
	for file in ['framework_classes.v', 'framework_action_provider.v'] {
		os.cp('tests/native-android-tools/androidtools/' + file, out + '/sources/androidtools/' + file)!
	}
	for name in ['build-framework243-popup-menus', 'snapshot-framework243'] {
		updated := name.replace('243-popup-menus', '244-action-provider').replace('243', '244')
		os.write_file(b + updated + '.v', os.read_file(b + name + '.v')!
			.replace('243-popup-menus', '244-action-provider').replace('243', '244')
			.replace('FRAMEWORK244-POPUP-MENUS', 'FRAMEWORK244-ACTION-PROVIDER'))!
	}
	println('FRAMEWORK244 frozen243 plus ActionProvider class, menu storage and dispatch hook')
}
