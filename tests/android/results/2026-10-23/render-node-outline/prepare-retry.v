import os
import json2
import compress.gzip
import crypto.sha256

fn main() {
	task := 'build/android-maps/outline228/'
	out := 'tests/android/results/2026-10-23/render-node-outline/initial-draw-color/'
	os.mkdir_all(out)!
	mut sources := map[string]string{}
	for path in os.walk_ext(task + 'source/startupfixture', '.v') {
		sources[os.base(path)] = os.read_file(path)!
	}
	os.write_file_array(out + 'fixture-sources.json.gz', gzip.compress(json2.encode(sources).bytes())!)!
	os.write_file(out + 'apk-sha256.txt', sha256.sum(os.read_bytes('build/android-maps/outline228-apk/bootstrap.apk')!).hex() + '\n')!
	for variant in ['baseline', 'fixed'] {
		run := task + 'run-' + variant + '/'
		for item in ['results.json', 'bootstrap-fixture/serial.log.gz',
			'bootstrap-fixture/application.png', 'staged-runtime-sha256.json'] {
			os.cp(run + item, out + variant + '-' + os.base(item))!
		}
		os.cp(task + variant + '.json', out + variant + '-configuration.json')!
		os.cp(task + variant + '-harness.log', out + variant + '-harness.log')!
		os.mv(task + 'run-' + variant, task + 'initial-run-' + variant)!
		os.write_file(task + variant + '.json', os.read_file(task + variant + '.json')!.replace('"startup_seconds": 40', '"startup_seconds": 120'))!
	}
	os.cp('tests/native-android-ws/startupfixture/render_node_outline.v', task + 'source/startupfixture/render_node_outline.v')!
	for name in ['classes.dex', 'bootstrap.apk', 'bootstrap.apk.idsig'] {
		path := 'build/android-maps/outline228-apk/' + name
		if os.exists(path) { os.rm(path)! }
	}
	os.rmdir_all(task + 'verify-apk-smali')!
	println('OUTLINE-RETRY prepared; initial baseline/fixed retained; only fixture covering draw operation changed')
}
