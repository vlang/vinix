import crypto.sha256
import guesthost
import json2
import os
struct Receipt {
	architecture string
	kernel_sha256 string
	source_sha256 string
	controller_sha256 string
	init_sha256 string
	iso_sha256 string
	exit_code int
}
fn hash(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn main() {
	assert os.args.len == 4
	arch := os.args[1]
	assert arch in ['aarch64', 'x86_64']
	state := os.args[2]
	assert !os.exists(state)
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(os.args[3] + '/bin/vinix', state + '/kernel/bin/vinix')!
	source := '/Users/alex/code/vinix/tests/memlock/test.c'
	source_hash := hash(source)
	code := guesthost.guest(source, '', state, state + '/kernel', arch,
		guesthost.memlock_features(), ['VINIX MEMLOCK: FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'],
		false, true, 360) or { eprintln(err); 1 }
	assert hash(source) == source_hash
	os.write_file(state + '/receipt.json', json2.encode(Receipt{arch, hash(state + '/kernel/bin/vinix'),
		source_hash, hash(@FILE), hash(state + '/init'), hash(state + '/test.iso'), code}, prettify: true) + '\n')!
	exit(code)
}
