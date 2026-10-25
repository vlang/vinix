module main
import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const root = '/Users/alex/.local/state/vinix/android/maps331-generation-preflight-2026-10-25'
const pins_path = '/Users/alex/.local/state/vinix/android/maps331-replacement-build-pins-2026-10-25.json'
const generator = repo + '/build/android-maps/maps-replay-generate314'
const generator_pin = '75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn inventory(path string, prefix string, mut result map[string]string) ! {
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		if key == 'sha256.json' { continue }
		file := path + '/' + name
		assert !os.is_link(file)
		if os.is_dir(file) { inventory(file, key, mut result)! }
		else { assert os.is_file(file); result[key] = hash(file)! }
	}
}
fn main() {
	assert os.getwd() == repo
	assert !os.exists(root + '/started.json'), 'one preflight invocation only'
	assert !os.exists(pins_path) && !os.is_link(pins_path), 'fresh replacement pins required'
	assert hash(generator)! == generator_pin
	assert hash(repo + '/tests/native-android-ws/maps-replay-generate.v')! == '39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84'
	assert hash(repo + '/tests/native-android-ws/maps298-run.v')! == '5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1'
	assert hash(repo + '/build/android-maps/queue284-tools/v_old276')! == '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
	pins := {
		'native_root': '/Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25'
		'native_manifest_sha256': '09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee'
		'native_sha256': '54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab'
		'framework_root': '/Users/alex/.local/state/vinix/android/system-package329-framework-build-2026-10-25'
		'framework_manifest_sha256': '4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e'
		'framework_sha256': 'c88b7f8a7ee34776641fc235922d0d86a0d8eefc60d09e50d55836aabb624934'
	}
	write_json(pins_path, pins)!
	write_json(root + '/replacement-build-pins.json', pins)!
	disk := os.exec(['/bin/df', '-k', '/Users/alex/.local/state/vinix/android'])
	assert disk.exit_code == 0
	os.write_file(root + '/disk-before.txt', disk.output)!
	argv := [generator, '331', pins_path, '--minimum-free-mib=1536']
	mut env := os.environ()
	mut removed := map[string]json2.Any{}
	for key, value in env.clone() {
		if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' {
			removed[key] = json2.Any(value.len == 0)
			env.delete(key)
		}
	}
	assert env.keys().all(!it.starts_with('VINIX_ANDROID_TRACE_') && it != 'ATL_UGLY_ENABLE_LOCATION')
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'generator_binary_sha256_before': json2.Any(hash(generator)!)
		'generator_source_sha256': json2.Any(hash(repo + '/tests/native-android-ws/maps-replay-generate.v')!)
		'maps298_source_sha256': json2.Any(hash(repo + '/tests/native-android-ws/maps298-run.v')!)
		'compiler_sha256': json2.Any(hash(repo + '/build/android-maps/queue284-tools/v_old276')!)
		'preflight_source_sha256': json2.Any(hash(root + '/preflight.v')!)
		'replacement_build_pins_sha256': json2.Any(hash(pins_path)!)
		'clean_environment_assertion': json2.Any(true)
		'removed_environment_keys_value_empty': json2.Any(removed)
		'policy': json2.Any('One existing generator invocation; unchanged1536MiB override; no prepare or run.')
	}
	write_json(root + '/started.json', receipt)!
	mut stdout := os.create(root + '/generator.stdout.log')!
	mut stderr := os.create(root + '/generator.stderr.log')!
	mut child := os.new_process(generator)
	child.set_args(argv[1..])
	child.set_environment(env)
	child.set_redirect_stdio()
	child.set_stdin_path('/dev/null')
	child.run()
	for {
		stdout.write_string(child.stdout_read())!
		stderr.write_string(child.stderr_read())!
		if !child.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	for _ in 0 .. 32 {
		out := child.stdout_read()
		err := child.stderr_read()
		stdout.write_string(out)!
		stderr.write_string(err)!
		if out.len == 0 && err.len == 0 { break }
	}
	stdout.close()
	stderr.close()
	receipt['exit_code'] = json2.Any(child.code)
	receipt['completed_utc'] = json2.Any(time.utc().str())
	receipt['generator_binary_sha256_after'] = json2.Any(hash(generator)!)
	assert hash(generator)! == generator_pin
	mut destinations := map[string]json2.Any{}
	for path in ['/Users/alex/.local/state/vinix/android/maps331-generation-2026-10-25', '/Users/alex/.local/state/vinix/android/maps331-run-build-c-2026-10-25', '/Users/alex/.local/state/vinix/android/maps331-2026-10-25', repo + '/build/android-maps/maps331-run-recorded', repo + '/build/android-maps/maps331', repo + '/build/android-maps/attempt331', repo + '/build/android-maps/attempt331.json'] {
		destinations[path] = json2.Any(os.exists(path) || os.is_link(path))
	}
	receipt['destination_exists_after'] = json2.Any(destinations)
	write_json(root + '/receipt.json', receipt)!
	mut seal := map[string]string{}
	inventory(root, '', mut seal)!
	write_json(root + '/sha256.json', seal)!
	println('MAPS331-GENERATOR-PREFLIGHT-RECORDED generator_exit=' + child.code.str() + ' seal=' + hash(root + '/sha256.json')!)
	exit(child.code)
}
