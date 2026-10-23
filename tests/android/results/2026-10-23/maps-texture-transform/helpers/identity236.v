import os
import json2
import crypto.sha256
import time

fn hash_stream(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn main() {
	b := 'build/android-maps/'
	out := b + 'identity236-inputs'
	assert !os.exists(out + '/pre-run-sha256.json'), 'Do not overwrite pre-run identity'
	os.mkdir_all(out)!
	mut records := map[string]string{}
	for name in ['vinix', 'limine.conf'] {
		r := os.exec(['mcopy', '-o', '-i', b + 'maps-live-vm/boot.img', '::/boot/' + name, out + '/' + name])
		assert r.exit_code == 0, r.output
		records['boot/' + name] = hash_stream(out + '/' + name)!
	}
	for path in [b + 'maps-live-vm/boot.img', b + 'maps-live-vm/efivars.fd',
		'/opt/homebrew/share/qemu/edk2-aarch64-code.fd', b + 'suite159',
		'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		records[path] = hash_stream(path)!
	}
	os.write_file(out + '/pre-run-sha256.json', json2.encode(records, prettify: true) + '\n')!
	os.write_file(out + '/scope.txt', time.utc().str() + ' UTC\nCaptured before suite236 injects qemu-runtime.tar into the boot image. The pre-run full-image hash identifies its inherited state; the extracted kernel and limine.conf identify the unchanged boot payload. Runtime module identities are captured separately after staging.\n')!
	println('MAPS236 pre-run boot/kernel/firmware/QEMU identities retained')
}
