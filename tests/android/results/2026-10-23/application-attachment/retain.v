import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
}

fn main() {
	out := os.dir(@FILE)
	base := 'build/android-maps/'
	for variant in ['baseline', 'fixed'] {
		run := base + 'attachment221-' + variant
		for pair in ['results.json|results.json', 'services/serial.log.gz|serial.log.gz',
			'services/application.png|application.png'] {
			names := pair.split('|')
			os.cp(run + '/' + names[0], out + '/' + variant + '-' + names[1])!
		}
		os.cp(run + '.json', out + '/' + variant + '-configuration.json')!
		os.cp(run + '.log', out + '/' + variant + '-harness.log')!
	}
	for name in ['build', 'run'] {
		os.cp(base + 'attachment221-sources/' + name + '.v', out + '/' + name + '.v')!
	}
	os.write_file_array(out + '/framework-build.log.gz', gzip.compress(os.read_bytes(base + 'build-attachment221.log')!)!)!
	os.cp(base + 'attachment221-fixture.log', out + '/fixture-build.log')!
	os.cp(base + 'framework-attachment221/framework-manifest.json', out + '/framework-manifest.json')!
	mut sources := map[string]string{}
	snapshot := base + 'attachment221-sources/'
	for file in os.walk_ext(snapshot, '.v') {
		sources[file.all_after(snapshot)] = os.read_file(file)!
	}
	for file in os.walk_ext(base + 'attachment221-apk', '.smali') {
		sources['fixture/' + file.all_after(base + 'attachment221-apk/')] = os.read_file(file)!
	}
	for item in ['baseline|framework217-observer2', 'fixed|framework-attachment221'] {
		names := item.split('|')
		sources[names[0] + '/ATLLoadedApp.smali'] = os.read_file(base + names[1] + '/smali/android/atl/ATLLoadedApp.smali')!
	}
	os.write_file_array(out + '/sources.json.gz', gzip.compress(json2.encode(sources,
		prettify: true
	).bytes())!)!
	mut inputs := map[string]string{}
	for file in ['framework217-observer2/api-impl.jar', 'framework-attachment221/api-impl.jar',
		'libnative204.so', 'attachment221-apk/client/probe.apk', 'attachment221-apk/companion/probe.apk',
		'suite159'] {
		inputs[base + file] = sha256.sum(os.read_bytes(base + file)!).hex()
	}
	for file in os.walk_ext(snapshot, '.v') {
		inputs['source/' + file.all_after(snapshot)] = sha256.sum(os.read_bytes(file)!).hex()
	}
	mut artifacts := map[string]string{}
	for name in os.ls(out)! {
		if os.file_ext(name) != '' && name != 'receipt.json' && name != 'validation.log' {
			artifacts[name] = sha256.sum(os.read_bytes(out + '/' + name)!).hex()
		}
	}
	os.write_file(out + '/receipt.json', json2.encode(Receipt{ artifacts: artifacts, inputs: inputs },
		prettify: true
	))!
	println('ATTACHMENT-RETAIN-PASS artifacts=${artifacts.len} sources=${sources.len}')
}
