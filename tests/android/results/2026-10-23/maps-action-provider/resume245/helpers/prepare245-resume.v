import os
import json2
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	assert !os.exists(b + 'attempt245.json')
	mut settings := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt244.json')!)!
	settings['output'] = b + 'attempt245'
	os.write_file(b + 'attempt245.json', json2.encode(settings, prettify: true) + '\n')!
	source := os.read_file(b + 'suite239-stream.v')!
	assert source.count('\tprepare_module(settings, app, output)!') == 1
	resumed := source.replace('\tprepare_module(settings, app, output)!',
		'\tvalidate_resume245(settings, output)!') + r'

// Resume the already staged, interrupted244 image. Metadata inspection,
// observation, timing and result classification above remain unchanged.
fn validate_resume245(settings map[string]json2.Any, output string) ! {
 b := "build/android-maps/"
 pre := json2.decode[map[string]json2.Any](os.read_file(b + "identity245-inputs/preflight.json")!)!
 image := settings["boot_image"]!.str()
 assert image == b + "maps-live-vm/boot.img"
 assert os.file_size(image) == u64(pre["boot_image_size"]!.i64())
 assert os.file_last_mod_unix(image) == pre["boot_image_mtime"]!.i64()
 assert pre["boot_image_sha256"]!.str().len == 64
 staged := pre["staged_runtime_sha256"]!.as_map()
 assert staged.len == 7
 for path, expected in staged {
  assert digest(b + "attempt244/module/" + path)! == expected.str(), path
 }
 assert staged["opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar"]!.str() == "933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8"
 assert staged["opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so"]!.str() == "78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d"
 os.cp(b + "attempt244/companion-packages.json", output + "/companion-packages.json")!
 os.cp(b + "identity245-inputs/preflight.json", output + "/resume-preflight.json")!
 println("RESUME245-PREFLIGHT PASS unchanged prepared244 image; staged7 verified; APK metadata reinspected")
}
'
	os.write_file(b + 'suite245-resume.v', resumed)!
	for name in ['interact', 'manual'] {
		os.write_file(b + name + '245.v', os.read_file(b + name + '244.v')!.replace('244', '245'))!
	}
	os.write_file(b + 'suite245-resume-delta.json', json2.encode({
		'original_source_sha256': sha256.sum(source.bytes()).hex()
		'resumed_source_sha256': sha256.sum(resumed.bytes()).hex()
		'scope': 'Only replace prepare_module call with prepared-image identity validation; metadata inspection, QEMU arguments, observation and classification unchanged.'
	}, prettify: true) + '\n')!
	println('PREPARE245-RESUME PASS same244 runtime, new output, original metadata and observation semantics')
}
