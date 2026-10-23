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
	task := b + 'canvas242/'
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
			'framework241-blur-styles'
		} else {
			'framework242-canvas-save'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		for name in ['Canvas', 'VinixPictureCanvas', 'VinixPictureCommand', 'VinixPictureCommand54',
			'RecordingCanvas'] {
			path := task + 'verify-' + mode + '-smali/android/graphics/' + name + '.smali'
			if os.is_file(path) {
				os.write_file_array(out + '/' + mode + '-' + name + '.smali.gz', gzip.compress(os.read_bytes(path)!)!)!
			}
		}
	}
	mut fixture := map[string]string{}
	for path in os.walk_ext(task + 'source/startupfixture', '.v') {
		fixture[os.base(path)] = os.read_file(path)!
	}
	os.write_file_array(out + '/fixture-sources.json.gz', gzip.compress(json2.encode(fixture).bytes())!)!
	os.cp(task + 'fixture-source-sha256.json', out + '/fixture-sources-sha256.json')!
	for name in ['CanvasSaveFlagsProbe', 'SaveLayerForwardCanvas', 'StartupProbe'] {
		os.write_file_array(out + '/' + name + '.smali.gz', gzip.compress(os.read_bytes(task + 'verify-apk-smali/org/vinix/bootstrap/' + name + '.smali')!)!)!
	}

	for source, name in {
		b + 'prepare-canvas242.v':             'prepare-fixture.v'
		b + 'build-canvas242.v':               'build-fixture.v'
		task + 'build.log':                    'fixture-build.log'
		b + 'prepare-canvas-proof242.v':       'prepare-proof.v'
		task + 'proof-prepare.log':            'proof-prepare.log'
		task + 'staged-hashes.v':              'staged-hashes.v'
		b + 'prepare-framework242.v':          'prepare-framework.v'
		b + 'snapshot-framework242.v':         'snapshot-framework.v'
		b + 'native235-exact-sources.json.gz': 'native-sources.json.gz'
		b + 'native235-sources.json':          'native-sources-sha256.json'
		b + 'native235-identity.txt':          'native-identity.txt'
	} {
		os.cp(source, out + '/' + name)!
	}
	os.write_file_array(out + '/build-framework.v.gz', gzip.compress(os.read_bytes(b + 'build-framework242-canvas-save.v')!)!)!
	for name in ['framework241-blur-styles/api-impl.jar', 'framework242-canvas-save/api-impl.jar',
		'libnative235.so', 'canvas242-apk/bootstrap.apk', 'suite159'] {
		inputs[b + name] = hash(b + name)!
	}
	inputs['prior-blur-styles/receipt.json'] = hash(out + '/../blur-styles/receipt.json')!
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
		scope:     'Identical signed APK and native235 across framework241 baseline and framework242 fixed. Exact missing six-argument Canvas.saveLayer baseline. Subclass five-argument override checks unchanged raw float bits including signed zero and a NaN payload, Paint/null identity, three distinct forwarded return values and flags0/31/-1. These flag cases document current wrapper behavior, not Android validation semantics. Native state tests use mask31: nested save depths and returned counts, translate/clip restoration, exact192 pixels across bitmap Canvas, Picture recording/playback and RecordingCanvas playback. All prior probes enabled. Only framework_canvas_save_flags.v and its startup hook differ; the generic picture recorder discovers the new API. No offscreen compositing, layer-paint or blur-pixel claim. Exact sources, signed/framework DEX, staged identities and raw outcomes retained.'
	}, prettify: true) + '\n')!
	println('CANVAS-SAVE-FLAGS RETAIN PASS ${artifacts.len} artifacts')
}
