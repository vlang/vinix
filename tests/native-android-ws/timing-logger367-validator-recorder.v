module main
import os
import json2
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/timing-logger367-validator-build-2026-10-26'
const baseline = state + '/timing-logger367-run-bootstrap-build-2026-10-26'
const baseline_pin = 'c066198d7e6f7450a450ac1353b95015594605afd35da152fdedbc7a45a02708'
const checkout_source = '/Users/alex/code/vinix/tests/native-android-ws/timing-logger367-run.v'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const checker = '/Users/alex/code/vinix/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const cc_pin = '179301dcb41ea78accc3fa0048a7e6f6710d891945a751a34addd622020c1818'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	mut sum := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &sum[0] }, unsafe { &digest }) == 1
	return sum[..].hex()
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn record(label string, argv []string) !string {
	assert !os.exists(root + '/commands/' + label + '.json')
	exe := os.real_path(argv[0])
	pin := hash(exe)!
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	write_json(root + '/commands/' + label + '.json', {'argv': json2.Any(argv),
		'executable_sha256': json2.Any(pin), 'exit_code': json2.Any(r.exit_code),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str())})!
	assert hash(exe)! == pin
	assert r.exit_code == 0, r.output
	return r.output
}

fn inventory(path string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(path + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(path + '/' + key)!.get_filetype() {
			.directory { inventory(path, key, mut pins)! }
			.regular { pins[key] = hash(path + '/' + key)! }
			else { return error('nonregular bundle entry: ' + key) }
		}
	}
}

fn closure(label string, compiler string, vroot string, source string) !map[string]string {
	listing := record(label, [compiler, '-path', vroot + '/vlib', '-print-v-files', source])!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		assert os.real_path(path).starts_with(root + '/'), path
		pins[path] = hash(path)!
	}
	assert pins.len > 0
	write_json(root + '/' + label + '.json', pins)!
	return pins
}

fn run() ! {
	assert os.args.len == 3
	revision := os.args[1]
	source_pin := os.args[2]
	assert revision.len == 40 && revision.bytes().all(it in '0123456789abcdef'.bytes())
	assert source_pin.len == 64 && source_pin.bytes().all(it in '0123456789abcdef'.bytes())
	assert hash(checkout_source)! == source_pin
	assert !os.exists(root) && !os.is_link(root)
	assert hash(checker)! == checker_pin && hash('/usr/bin/cc')! == cc_pin
	assert hash(baseline + '/sha256.json')! == baseline_pin
	os.mkdir_all(root + '/commands')!
	committed := record('committed-source', ['/usr/bin/git', 'show', revision + ':tests/native-android-ws/timing-logger367-run.v'])!
	assert committed == os.read_file(checkout_source)!
	// The original 647-file bootstrap already has root and independent complete
	// readbacks. Validate exactly the inherited compiler tree against its sealed
	// inventory while preparing this separate validator build.
	baseline_files := json2.decode[map[string]string](os.read_file(baseline + '/sha256.json')!)!
	assert baseline_files['timing-logger367-run']! == 'f5d40c0f39cdf0a36d1fc60d47d5fdb8a2a2dbf4cbbccbb2d6b4eab6a394a1da'
	record('retain-baseline-manifest', ['/bin/cp', '-c', baseline + '/sha256.json', root + '/baseline-manifest.json'])!
	vroot := root + '/frozen/vroot'
	os.mkdir_all(root + '/frozen')!
	record('clone-vroot', ['/bin/cp', '-c', '-R', baseline + '/frozen/vroot', vroot])!
	mut inherited := map[string]string{}
	inventory(vroot, '', mut inherited)!
	mut expected := map[string]string{}
	for key, pin in baseline_files {
		if key.starts_with('frozen/vroot/') { expected[key.trim_string_left('frozen/vroot/')] = pin }
	}
	assert inherited == expected && inherited.len > 0
	write_json(root + '/inherited-vroot.json', inherited)!
	source := vroot + '/source/timing-logger367-validator.v'
	assert !os.exists(source)
	record('retain-source', ['/bin/cp', '-c', checkout_source, source])!
	assert hash(source)! == source_pin
	record('retain-recorder', ['/bin/cp', '-c', state + '/timing-logger367-validator-recorder.v', root + '/recorder.v'])!
	compiler := vroot + '/v'
	assert hash(compiler)! == compiler_pin
	os.mkdir_all(root + '/generated-c')!
	os.mkdir_all(root + '/vmodules')!
	os.setenv('VROOT', vroot, true)
	os.setenv('VEXE', compiler, true)
	os.setenv('VTMP', root + '/generated-c', true)
	os.setenv('VMODULES', root + '/vmodules', true)
	write_json(root + '/compile-environment.json', {'VROOT': vroot, 'VEXE': compiler, 'VTMP': root + '/generated-c', 'VMODULES': root + '/vmodules'})!
	mut host_tools := map[string]string{}
	for name in ['clang', 'ld'] {
		path := record('find-' + name, ['/usr/bin/xcrun', '--find', name])!.trim_space()
		host_tools[path] = hash(path)!
	}
	host_tools['/usr/bin/cc'] = cc_pin
	before := closure('closure-before', compiler, vroot, source)!
	output := root + '/timing-logger367-validator'
	record('compile', [compiler, '-path', vroot + '/vlib', '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-o', output, source])!
	assert !os.read_file(root + '/commands/compile.log')!.contains('/Users/alex/code/'), 'mutable checkout in C command'
	record('self-test', [output, 'self-test'])!

	assert before == closure('closure-after', compiler, vroot, source)!
	assert hash(checkout_source)! == source_pin && hash(source)! == source_pin
	assert hash(compiler)! == compiler_pin && hash(checker)! == checker_pin
	for path, pin in host_tools { assert hash(path)! == pin, path }
	write_json(root + '/build.json', {'source_commit': json2.Any(revision), 'source_sha256': json2.Any(hash(source)!),
		'binary_sha256': json2.Any(hash(output)!), 'compiler_sha256': json2.Any(compiler_pin),
		'host_tools': json2.decode[json2.Any](json2.encode(host_tools))!,
		'v_input_count': json2.Any(before.len), 'baseline_manifest_sha256': json2.Any(baseline_pin)})!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	write_json(root + '/sha256.json', pins)!
	seal := hash(root + '/sha256.json')!
	argv := [checker, root, seal, root + '-own-readback.json']
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '-own-readback.log', r.output)!
	write_json(root + '-own-readback-command.json', {'argv': json2.Any(argv),
		'executable_sha256': json2.Any(checker_pin), 'exit_code': json2.Any(r.exit_code),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str())})!
	assert r.exit_code == 0 && hash(checker)! == checker_pin, r.output
	println('TIMING367-VALIDATOR-BUILD-PASS source=' + hash(source)! + ' binary=' + hash(output)! + ' manifest=' + seal + ' files=' + pins.len.str())
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
