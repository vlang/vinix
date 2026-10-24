import os
import json2
import crypto.sha256
import time

fn digest(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut h := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		h.write(buffer[..n])!
	}
	return h.sum([]u8{}).hex()
}

fn main() {
	b := 'build/android-maps/'
	out := b + 'identity245-inputs/'
	assert !os.exists(out + 'preflight.json'), 'Preflight is immutable'
	os.mkdir_all(out + 'archive-seven')!
	image := b + 'maps-live-vm/boot.img'
	before := os.stat(image)!
	image_hash := digest(image)!
	println('MAPS245 BOOT IMAGE SHA256 ' + image_hash)
	paths := ['opt/android-test/native-guest',
		'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session']
	// Static task-owned paths: stream the FAT runtime archive once and retain only seven files.
	command := 'set -o pipefail; mtype -i build/android-maps/maps-live-vm/boot.img ::/boot/qemu-runtime.tar | tar -xf - -C build/android-maps/identity245-inputs/archive-seven ' + paths.map('./' + it).join(' ')
	r := os.exec(['/bin/zsh', '-c', command])
	assert r.exit_code == 0, r.output
	mut staged := map[string]string{}
	mut archive := map[string]string{}
	for path in paths {
		staged[path] = digest(b + 'attempt244/module/' + path)!
		archive[path] = digest(out + 'archive-seven/' + path)!
		assert staged[path] == archive[path], path
	}
	assert staged[paths[1]] == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	assert staged[paths[2]] == '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'
	mut pre := map[string]string{}
	for name in ['vinix', 'limine.conf'] {
		rr := os.exec(['mcopy', '-o', '-i', image, '::/boot/' + name, out + name])
		assert rr.exit_code == 0, rr.output
		pre['boot/' + name] = digest(out + name)!
	}
	for path in [b + 'maps-live-vm/efivars.fd', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		b + 'suite239-stream', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		pre[path] = digest(path)!
	}
	pre[image] = image_hash
	after := os.stat(image)!
	assert before.size == after.size && before.mtime == after.mtime, 'Image changed during read-only preflight'
	mut record := map[string]json2.Any{}
	record['captured_utc'] = time.utc().str() + ' UTC'
	record['boot_image_sha256'] = image_hash
	record['boot_image_size'] = i64(before.size)
	record['boot_image_mtime'] = i64(before.mtime)
	record['staged_runtime_sha256'] = json2.decode[json2.Any](json2.encode(staged))!
	record['archive_runtime_sha256'] = json2.decode[json2.Any](json2.encode(archive))!
	record['pre_run_sha256'] = json2.decode[json2.Any](json2.encode(pre))!
	record['scope'] = 'Read-only preflight after interrupted Maps244 and before Maps245 direct resume. Seven files extracted from the FAT boot image runtime tar match the staged Maps244 module. No module rebuild or archive injection occurred.'
	os.write_file(out + 'preflight.json', json2.encode(record, prettify: true) + '\n')!
	os.write_file(out + 'preflight-sha256.txt', digest(out + 'preflight.json')! + '\n')!
	os.rmdir_all(out + 'archive-seven')!
	println('MAPS245 PREFLIGHT PASS image fixed; archived/staged7 match framework244/native236; seven infrastructure identities retained')
}
