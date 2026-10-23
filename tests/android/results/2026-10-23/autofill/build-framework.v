import os
import androidtools
import crypto.sha256

fn main() {
	input := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	assert sha256.sum(os.read_bytes(input)!).hex() == '4acb4a9356b7c0ed53498923e46fbe55acfabfe362f899a0a0a45bfd58f12357'
	output := os.abs_path('build/android-maps/framework222-autofill')
	os.mkdir_all(output + '/sources/androidtools')!
	for file in os.walk_ext('tests/native-android-tools/androidtools', '.v') {
		os.cp(file, output + '/sources/androidtools/' + os.base(file))!
	}
	androidtools.extend_framework(input, output + '/api-impl.jar', output, os.abs_path('build/android-framework/tools'), '/opt/homebrew/opt/openjdk@25/bin/java')!
	println('FRAMEWORK222-AUTOFILL ' + sha256.sum(os.read_bytes(output + '/api-impl.jar')!).hex())
}
