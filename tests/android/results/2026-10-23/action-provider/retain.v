import os
import crypto.sha256
import json2
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn archive(from string, to string) ! {
	os.write_file_array(to, gzip.compress(os.read_bytes(from)!)!)!
}

fn main() {
	out := os.dir(@FILE)
	b := 'build/android-maps/'
	task := b + 'action244/'
	mut inputs := map[string]string{}
	for mode in ['baseline', 'fixed'] {
		run := task + 'run-' + mode + '/'
		for pair in ['results.json|results.json', 'bootstrap-fixture/serial.log.gz|serial.log.gz',
			'bootstrap-fixture/application.png|application.png',
			'staged-runtime-sha256.json|staged-runtime-sha256.json'] {
			p := pair.split('|')
			os.cp(run + p[0], out + '/' + mode + '-' + p[1])!
		}
		os.cp(task + mode + '.json', out + '/' + mode + '-configuration.json')!
		os.cp(task + mode + '-harness.log', out + '/' + mode + '-harness.log')!
		for name, digest in json2.decode[map[string]string](os.read_file(run + 'staged-runtime-sha256.json')!)! {
			inputs[mode + '/staged/' + name] = digest
		}
		jar := if mode == 'baseline' {
			'framework243-popup-menus'
		} else {
			'framework244-action-provider'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		for path in os.walk_ext(task + 'verify-' + mode + '-smali', '.smali') {
			archive(path, out + '/' + mode + '-' + os.base(path) + '.gz')!
		}
	}
	os.cp(task + 'source/action-provider-fixture.v', out + '/fixture.v')!
	for path in os.walk_ext(task + 'verify-apk-smali', '.smali') {
		archive(path, out + '/' + os.base(path) + '.gz')!
	}
	for source, name in {
		b + 'prepare-action244.v':             'prepare-fixture.v'
		b + 'action244-prepare.log':           'fixture-prepare.log'
		b + 'action244-apk-build.log':         'fixture-build.log'
		task + 'staged-hashes.v':              'staged-hashes.v'
		b + 'prepare-framework244.v':          'prepare-framework.v'
		b + 'snapshot-framework244.v':         'snapshot-framework.v'
		b + 'framework244-build.log':          'framework-build.log'
		b + 'native236-exact-sources.json.gz': 'native-sources.json.gz'
		b + 'native236-sources.json':          'native-sources-sha256.json'
		b + 'native236-identity.txt':          'native-identity.txt'
	} {
		os.cp(source, out + '/' + name)!
	}
	archive(b + 'build-framework244-action-provider.v', out + '/build-framework.v.gz')!
	for name in ['framework243-popup-menus/api-impl.jar', 'framework244-action-provider/api-impl.jar',
		'libnative236.so', 'action244-apk/probe.apk', 'suite159'] {
		inputs[b + name] = hash(b + name)!
	}
	inputs['fixture.v'] = hash(out + '/fixture.v')!
	mut artifacts := map[string]string{}
	for path in os.walk_ext(out, '') {
		name := path.all_after(out + '/')
		if name !in ['receipt.json', 'validation.log', 'retain', 'validate'] {
			artifacts[name] = hash(path)!
		}
	}
	os.write_file(out + '/receipt.json', json2.encode(Receipt{
		artifacts: artifacts
		inputs:    inputs
		scope:     'Same signed standalone APK and native236: framework243 missing ActionProvider versus framework244. Full ActionProvider defaults, virtual factories, visibility/subUI listener replacement/removal/reset; bounded MenuItem provider retention/reset/clear and real popup Button callback order item then Popup then provider default action. Framework changes only new generator and classes hook; native unchanged. No prior startup probes, provider-created action views, menu visibility/submenus, direct-actionView provider invalidation, navigation or rendered effects claimed. Exact sources, actual signed/framework DEX, staged runtime identities and raw outcomes retained.'
	}, prettify: true) + '\n')!
	println('ACTION-PROVIDER RETAIN PASS ${artifacts.len} artifacts')
}
