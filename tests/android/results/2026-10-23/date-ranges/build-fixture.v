import os
import crypto.sha256
import startupfixture

fn checked(args []string) {
	r := os.exec(args)
	print(r.output)
	assert r.exit_code == 0, r.output
}

fn main() {
	output := os.abs_path('build/android-maps/dates240-apk')
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	startupfixture.install(output, resources)!
	for name in ['classes.dex', 'unsigned.apk', 'bootstrap.apk'] {
		if os.is_file(output + '/' + name) { os.rm(output + '/' + name)! }
	}
	if os.is_dir(output + '/compiled-res') { os.rmdir_all(output + '/compiled-res')! }
	os.mkdir_all(output + '/compiled-res')!
	checked([os.abs_path('build/android-native-ws/aapt2'), 'compile', '--dir', output + '/res',
		'-o', output + '/compiled-res'])
	mut link := [os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', resources, '--manifest',
		output + '/AndroidManifest.xml', '-A', output + '/assets', '-0', 'txt', '-o',
		output + '/unsigned.apk']
	link << os.walk_ext(output + '/compiled-res', '.flat')
	checked(link)
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main',
		'assemble', output + '/smali', '-o', output + '/classes.dex'])
	assert os.is_file(output + '/classes.dex')
	checked(['zip', '-q', '-j', output + '/unsigned.apk', output + '/classes.dex'])
	mut zip := os.new_process('zip')
	zip.set_work_folder(output)
	zip.set_args(['-q', 'unsigned.apk', 'lib/arm64-v8a/libfixture.so',
		'lib/arm64-v8a/libfixture-dependency.so', 'lib/arm64-v8a/libfixture-broken.so',
		'lib/arm64-v8a/libfixture-tls.so'])
	zip.run()
	zip.wait()
	assert zip.code == 0
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'),
		'sign', '--ks', output + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass',
		'pass:android', '--key-pass', 'pass:android', '--out', output + '/bootstrap.apk',
		output + '/unsigned.apk'])
	assert sha256.sum(os.read_bytes('build/android-maps/interpolators234-apk/bootstrap.apk')!).hex() == '6dc384bc7cd0ace193317c5ebb45adb5d691a475e5e0a91756710320d0cde447'
	println('DATES240 APK ' + sha256.sum(os.read_bytes(output + '/bootstrap.apk')!).hex())
}
