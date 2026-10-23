import os

fn main() {
	b := 'build/android-maps/'
	output := b + 'framework236-texture'
	assert !os.exists(output), 'Frozen framework sources already exist'
	os.mkdir_all(output + '/sources/androidtools')!
	for path in os.walk_ext(b + 'framework235-accessibility/sources/androidtools', '.v') {
		os.cp(path, output + '/sources/androidtools/' + os.base(path))!
	}
	for name in ['framework_startup.v', 'framework_texture_transforms.v'] {
		os.cp('tests/native-android-tools/androidtools/' + name, output + '/sources/androidtools/' + name)!
	}
	for kind in ['build-framework235-accessibility', 'snapshot-framework235'] {
		converted := os.read_file(b + kind + '.v')!
			.replace('framework235-accessibility', 'framework236-texture')
			.replace('FRAMEWORK235-INTERPOLATORS', 'FRAMEWORK236-TEXTURE')
			.replace('FRAMEWORK235', 'FRAMEWORK236')
		name := if kind.starts_with('build-') { 'build-framework236-texture' } else { 'snapshot-framework236' }
		os.write_file(b + name + '.v', converted)!
	}
	println('FRAMEWORK236 PREPARED immutable235 base plus TextureView matrix property')
}
