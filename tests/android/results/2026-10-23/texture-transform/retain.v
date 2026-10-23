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
	task := b + 'texture236/'
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
			'framework235-accessibility'
		} else {
			'framework236-texture'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		os.write_file_array(out + '/' + mode + '-TextureView.smali.gz', gzip.compress(os.read_bytes(task + 'verify-' + mode + '-smali/android/view/TextureView.smali')!)!)!
	}
	mut fixture := map[string]string{}
	for path in os.walk_ext(task + 'source/startupfixture', '.v') {
		fixture[os.base(path)] = os.read_file(path)!
	}
	os.write_file_array(out + '/fixture-sources.json.gz', gzip.compress(json2.encode(fixture).bytes())!)!
	os.cp(task + 'fixture-source-sha256.json', out + '/fixture-sources-sha256.json')!
	for name in ['TextureViewTransformProbe', 'TransformTextureView', 'StartupProbe'] {
		os.write_file_array(out + '/' + name + '.smali.gz', gzip.compress(os.read_bytes(task + 'verify-apk-smali/org/vinix/bootstrap/' + name + '.smali')!)!)!
	}
	for source, name in {
		b + 'prepare-texture236.v':            'prepare-fixture.v'
		b + 'build-texture236.v':              'build-fixture.v'
		task + 'build.log':                    'fixture-build.log'
		task + 'prepare-proof.v':              'prepare-proof.v'
		task + 'proof-prepare.log':            'proof-prepare.log'
		task + 'staged-hashes.v':              'staged-hashes.v'
		b + 'prepare-framework236.v':          'prepare-framework.v'
		b + 'build-framework236-texture.v':    'build-framework.v'
		b + 'snapshot-framework236.v':         'snapshot-framework.v'
		b + 'native235-exact-sources.json.gz': 'native-sources.json.gz'
		b + 'native235-sources.json':          'native-sources-sha256.json'
		b + 'native235-identity.txt':          'native-identity.txt'
	} {
		os.cp(source, out + '/' + name)!
	}
	for name in ['framework235-accessibility/api-impl.jar', 'framework236-texture/api-impl.jar',
		'libnative235.so', 'texture236-apk/bootstrap.apk', 'suite159'] {
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
		scope:     'Identical signed APK/native235 across framework235 baseline and framework236 fixed. The exact TextureView.setTransform(Matrix) Maps blocker is called first. Checks private matrix copies, both existing constructors, per-view state, caller output identity, fresh output, repeated replacement, null reset, invalidation and unchanged background pixels/View geometry while surface is unavailable. All prior startup/interpolator/accessibility probes remain enabled. Exact sources, actual DEX, staged binaries and raw outcomes retained. No Maps functional outcome implied.'
	}, prettify: true) + '\n')!
	println('TEXTURE-TRANSFORM RETAIN PASS ${artifacts.len} artifacts')
}
