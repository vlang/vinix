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
	task := b + 'popup243/'
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
			'framework242-canvas-save'
		} else {
			'framework243-popup-menus'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		for dir in ['android/view', 'android/widget'] {
			for path in os.walk_ext(task + 'verify-' + mode + '-smali/' + dir, '.smali') {
				archive(path, out + '/' + mode + '-' + os.base(path) + '.gz')!
			}
		}
		native := if mode == 'baseline' { '235' } else { '236' }
		for pair in ['exact-sources.json.gz|sources.json.gz', 'sources.json|sources-sha256.json',
			'identity.txt|identity.txt'] {
			p := pair.split('|')
			os.cp(b + 'native' + native + '-' + p[0], out + '/' + mode + '-native-' + p[1])!
		}
	}
	os.cp(task + 'source/popup-menu-fixture.v', out + '/fixture.v')!
	for path in os.walk_ext(task + 'verify-apk-smali', '.smali') {
		archive(path, out + '/' + os.base(path) + '.gz')!
	}
	for source, name in {
		b + 'prepare-popup243.v':                      'prepare-fixture.v'
		task + 'build.log':                            'fixture-build.log'
		b + 'prepare-popup-proof243.v':                'prepare-proof.v'
		task + 'proof-prepare.log':                    'proof-prepare.log'
		task + 'staged-hashes.v':                      'staged-hashes.v'
		task + 'menu-resource-dump.txt':               'menu-resource-dump.txt'
		b + 'interact-popup243.v':                     'interact.v'
		task + 'interaction.log':                      'interaction.log'
		task + 'guest-ready.png':                      'guest-ready.png'
		task + 'guest-clicked.png':                    'guest-clicked.png'
		b + 'prepare-framework243.v':                  'prepare-framework.v'
		b + 'snapshot-framework243.v':                 'snapshot-framework.v'
		b + 'build-framework243.log':                  'framework-build.log'
		b + 'native236-source-delta.json':             'native-source-delta.json'
		b + 'native236-production-source-sha256.json': 'native-build-inputs.json'
		b + 'build-native236.log':                     'native-build.log'
		b + 'build-native236.v':                       'build-native.v'
	} {
		os.cp(source, out + '/' + name)!
	}
	archive(b + 'build-framework243-popup-menus.v', out + '/build-framework.v.gz')!
	for name in ['framework242-canvas-save/api-impl.jar', 'framework243-popup-menus/api-impl.jar',
		'libnative235.so', 'libnative236.so', 'popup243-apk/probe.apk', 'suite159'] {
		inputs[b + name] = hash(b + name)!
	}
	inputs['fixture.v'] = hash(out + '/fixture.v')!
	inputs['rejected-get-icon/apk'] = hash(task + 'rejected-get-icon/probe.apk')!
	os.mkdir_all(out + '/rejected-get-icon')!
	os.cp(task + 'rejected-get-icon/fixture.v', out + '/rejected-get-icon/fixture.v')!
	for mode in ['baseline', 'fixed'] {
		rej := task + 'rejected-get-icon/run-' + mode + '/'
		os.cp(rej + 'results.json', out + '/rejected-get-icon/' + mode + '-results.json')!
		os.cp(rej + 'bootstrap-fixture/serial.log.gz', out + '/rejected-get-icon/' + mode + '-serial.log.gz')!
		os.cp(rej + 'staged-runtime-sha256.json', out + '/rejected-get-icon/' + mode + '-staged-runtime-sha256.json')!
	}
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
		scope:     'Identical standalone signed APK: baseline framework242/native235 versus fixed framework243/native236. The two runtime components change together because native menu_context reads the new VinixMenu.vinixContext field; old framework/new native would be an unrelated ABI mismatch. Baseline fails at unimplemented PopupMenu.native_init. Fixed validates compiled menu XML, wrapped constructor Context resource work, resource submenu propagation and Activity-owner fallback, hidden/disabled/checked views, item-listener precedence/fallback, navigation, repeated show/dismiss, callback reentry and stale button rejection. Delayed dismiss counts are checked across eight real Dialog presentations. Final PASS requires a real guest mouse click on the visible leaf and its delayed dismissal. Standalone app has no prior startup probes. Exact framework/native sources, actual signed/framework DEX, staged identities, screenshots and raw outcomes retained. Centered Dialog fallback only; no anchor positioning or outside-click dismissal claim.'
	}, prettify: true) + '\n')!
	println('POPUP-MENU RETAIN PASS ${artifacts.len} artifacts')
}
