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
	task := b + 'blur241/'
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
			'framework240-date-ranges'
		} else {
			'framework241-blur-styles'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		for name in ['BlurMaskFilter', 'BlurMaskFilter$Blur'] {
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
	os.write_file_array(out + '/BlurMaskFilter-aosp.java.gz', gzip.compress(os.read_bytes(b + 'BlurMaskFilter-aosp.java')!)!)!
	for name in ['BlurStylesProbe', 'StartupProbe'] {
		os.write_file_array(out + '/' + name + '.smali.gz', gzip.compress(os.read_bytes(task + 'verify-apk-smali/org/vinix/bootstrap/' + name + '.smali')!)!)!
	}

	for source, name in {
		b + 'prepare-blur241.v':                'prepare-fixture.v'
		b + 'build-blur241.v':                  'build-fixture.v'
		task + 'build.log':                     'fixture-build.log'
		b + 'prepare-blur-proof241.v':          'prepare-proof.v'
		task + 'proof-prepare.log':             'proof-prepare.log'
		task + 'staged-hashes.v':               'staged-hashes.v'
		b + 'prepare-framework241.v':           'prepare-framework.v'
		b + 'build-framework241-blur-styles.v': 'build-framework.v'
		b + 'snapshot-framework241.v':          'snapshot-framework.v'
		b + 'native235-exact-sources.json.gz':  'native-sources.json.gz'
		b + 'native235-sources.json':           'native-sources-sha256.json'
		b + 'native235-identity.txt':           'native-identity.txt'
	} {
		os.cp(source, out + '/' + name)!
	}
	for name in ['framework240-date-ranges/api-impl.jar', 'framework241-blur-styles/api-impl.jar',
		'libnative235.so', 'blur241-apk/bootstrap.apk', 'suite159'] {
		inputs[b + name] = hash(b + name)!
	}
	inputs['prior-date-ranges/receipt.json'] = hash(out + '/../date-ranges/receipt.json')!
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
		scope:     'Identical signed APK and native235 across framework240 baseline and framework241 fixed. Exact missing Blur.OUTER field baseline. Checks all four enum names/order/ordinals, distinct singleton identities, reflected final native_int IDs0-3, typed and Enum valueOf identity, fresh values arrays and mutation isolation, unknown/null valueOf errors. All prior probes enabled. Only framework_blur_styles.v and its startup hook differ. Outer BlurMaskFilter constructor remains unchanged; no radius validation or rendered-blur claim. Exact sources, actual signed/framework DEX, staged identities and raw outcomes retained.'
	}, prettify: true) + '\n')!
	println('BLUR-STYLES RETAIN PASS ${artifacts.len} artifacts')
}
