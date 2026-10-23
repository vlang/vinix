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

fn main() {
	out := os.dir(@FILE)
	b := 'build/android-maps/'
	task := b + 'accessibility235/'
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
			'framework234-interpolators'
		} else {
			'framework235-accessibility'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		os.write_file_array(out + '/' + mode + '-View.smali.gz', gzip.compress(os.read_bytes(task + 'verify-' + mode + '-smali/android/view/View.smali')!)!)!
	}
	mut fixture := map[string]string{}
	for path in os.walk_ext(task + 'source/startupfixture', '.v') {
		fixture[os.base(path)] = os.read_file(path)!
	}
	os.write_file_array(out + '/fixture-sources.json.gz', gzip.compress(json2.encode(fixture).bytes())!)!
	os.cp(task + 'fixture-source-sha256.json', out + '/fixture-sources-sha256.json')!
	os.write_file_array(out + '/StartupProbe.smali.gz', gzip.compress(os.read_bytes(task + 'verify-apk-smali/org/vinix/bootstrap/StartupProbe.smali')!)!)!
	for source, name in {
		b + 'prepare-accessibility235.v':                                  'prepare-fixture.v'
		b + 'build-accessibility235.v':                                    'build-fixture.v'
		task + 'build.log':                                                'fixture-build.log'
		task + 'compiled-xml.txt':                                         'compiled-xml.txt'
		task + 'prepare-proof.v':                                          'prepare-proof.v'
		task + 'proof-prepare.log':                                        'proof-prepare.log'
		task + 'staged-hashes.v':                                          'staged-hashes.v'
		b + 'accessibility235-apk/res/layout/accessibility_traversal.xml': 'accessibility_traversal.xml'
		b + 'prepare-framework235.v':                                      'prepare-framework.v'
		b + 'build-framework235-accessibility.v':                          'build-framework.v'
		b + 'snapshot-framework235.v':                                     'snapshot-framework.v'
	} {
		os.cp(source, out + '/' + name)!
	}
	for name in ['framework234-interpolators/api-impl.jar', 'framework235-accessibility/api-impl.jar',
		'libnative233.so', 'accessibility235-apk/bootstrap.apk', 'interpolators234-apk/bootstrap.apk',
		'suite159'] {
		inputs[b + name] = hash(b + name)!
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
		scope:     'Identical signed APK and native233 across framework234 baseline and framework235 fixed. Checks View traversal state and actual XML inflation in normal startup fixture, excluding only the separately retained InterpolatorProbe runtime invocation. Original signed interpolation APK remains unchanged. Exact frozen sources, actual DEX, compiled XML, staged binaries and raw outcomes retained. No Maps functional outcome implied.'
	}, prettify: true) + '\n')!
	println('ACCESSIBILITY-TRAVERSAL RETAIN PASS ${artifacts.len} artifacts')
}
