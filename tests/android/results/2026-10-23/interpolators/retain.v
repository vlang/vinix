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
	task := b + 'interpolators234/'
	mut inputs := map[string]string{}
	for mode in ['baseline', 'rejected234', 'fixed'] {
		run_mode := match mode {
			'rejected234' { 'fixed' }
			'fixed' { 'fixed235' }
			else { mode }
		}
		run := task + 'run-' + run_mode + '/'
		for pair in ['results.json|results.json', 'bootstrap-fixture/serial.log.gz|serial.log.gz',
			'bootstrap-fixture/application.png|application.png',
			'staged-runtime-sha256.json|staged-runtime-sha256.json'] {
			p := pair.split('|')
			os.cp(run + p[0], out + '/' + mode + '-' + p[1])!
		}
		os.cp(task + run_mode + '.json', out + '/' + mode + '-configuration.json')!
		os.cp(task + run_mode + '-harness.log', out + '/' + mode + '-harness.log')!
		for name, digest in json2.decode[map[string]string](os.read_file(run + 'staged-runtime-sha256.json')!)! {
			inputs[mode + '/staged/' + name] = digest
		}
		jar := if mode == 'baseline' {
			'framework228-outline'
		} else {
			'framework234-interpolators'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		for name in ['AnimationUtils', 'PathInterpolator'] {
			smali_mode := if mode == 'baseline' { 'baseline' } else { 'fixed' }
			os.write_file_array(out + '/' + mode + '-' + name + '.smali.gz', gzip.compress(os.read_bytes(task + 'verify-' + smali_mode + '-smali/android/view/animation/' + name + '.smali')!)!)!
		}
	}
	for name in ['InterpolatorProbe', 'InterpolatorResources', 'InterpolatorContext',
		'InterpolatorParser', 'StartupProbe'] {
		os.write_file_array(out + '/' + name + '.smali.gz', gzip.compress(os.read_bytes(task + 'verify-apk-smali/org/vinix/bootstrap/' + name + '.smali')!)!)!
	}
	mut fixture := map[string]string{}
	mut fixture_hashes := map[string]string{}
	for path in os.walk_ext(task + 'source/startupfixture', '.v') {
		fixture[os.base(path)] = os.read_file(path)!
		fixture_hashes[os.base(path)] = hash(path)!
	}
	os.write_file_array(out + '/fixture-sources.json.gz', gzip.compress(json2.encode(fixture).bytes())!)!
	os.write_file(out + '/fixture-sources-sha256.json', json2.encode(fixture_hashes, prettify: true) + '\n')!
	mut xml := map[string]string{}
	for path in os.walk_ext(b + 'interpolators234-apk/res/anim', '.xml') {
		xml[os.base(path)] = os.read_file(path)!
	}
	os.write_file(out + '/compiled-resource-inputs.json', json2.encode(xml, prettify: true) + '\n')!
	for name in ['fpA', '4QZ', 'c0L', 'aJ7', 'apk-sha256'] {
		os.cp(b + 'interpolator-resources234/' + name + '.txt', out + '/maps-' + name + '.txt')!
	}
	for source, name in {
		b + 'prepare-interpolators234.v':              'prepare-fixture.v'
		b + 'interpolators234-build.v':                'build-fixture.v'
		task + 'build.log':                            'fixture-build.log'
		task + 'staged-hashes.v':                      'staged-hashes.v'
		task + 'prepare-proof.v':                      'prepare-proof.v'
		task + 'proof-prepare.log':                    'proof-prepare.log'
		task + 'prepare-fixed235.v':                   'prepare-fixed235.v'
		task + 'staged-hashes235.v':                   'staged-hashes235.v'
		task + 'check-path-precision.v':               'rejected234-check-path-precision.v'
		task + 'path-precision-source.v':              'rejected234-path-precision-source.v'
		task + 'path-precision.log':                   'rejected234-path-precision.log'
		task + 'compiled-xml.txt':                     'compiled-xml.txt'
		b + 'prepare-framework234.v':                  'prepare-framework.v'
		b + 'build-framework234-interpolators.v':      'build-framework.v'
		b + 'snapshot-framework234.v':                 'snapshot-framework.v'
		b + 'native233-sources.json':                  'baseline-native-sources-sha256.json'
		b + 'native233-exact-sources.json.gz':         'baseline-native-sources.json.gz'
		b + 'native233-identity.txt':                  'baseline-native-identity.txt'
		b + 'native235-sources.json':                  'fixed-native-sources-sha256.json'
		b + 'native235-exact-sources.json.gz':         'fixed-native-sources.json.gz'
		b + 'native235-identity.txt':                  'fixed-native-identity.txt'
		b + 'native235-source-delta.json':             'fixed-native-source-delta.json'
		b + 'native235-production-source-sha256.json': 'fixed-native-production-source-sha256.json'
		b + 'native235-reviewed-overlays.json':        'fixed-native-reviewed-overlays.json'
		b + 'native235-build.log':                     'fixed-native-build.log'
		b + 'build-native235.v':                       'build-native.v'
	} {
		os.cp(source, out + '/' + name)!
	}
	for name in ['framework228-outline/api-impl.jar', 'framework234-interpolators/api-impl.jar',
		'libnative233.so', 'libnative235.so', 'interpolators234-apk/bootstrap.apk', 'suite159'] {
		inputs[b + name] = hash(b + name)!
	}
	os.cp(out + '/../path-precision/receipt.json', out + '/path-precision-host-receipt.json')!
	inputs['path-precision-host-receipt'] = hash(out + '/path-precision-host-receipt.json')!
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
		scope:     'Identical signed APK in three runs: framework228/native233 reproduces null interpolator loader; framework234/native233 fails normalized pathData numerical assertion after the four Maps curves, scalar tags and quadratic pass; unchanged framework234/native235 validates all cases. The only native233-to235 source delta is four reviewed path-precision files. Real aapt-compiled XML, independent f64 numerical oracle, ten tags, four Maps Material curves, quadratic/pathData/vertical and legal outside-control paths, invalid paths and parser cleanup are covered. Proxy tracks close and unwraps the actual XmlBlock parser only for native typed attributes; theme is null. No Maps outcome is implied. Raw suite failure markers are retained separately from assertion completion. Exact fixture/framework/native source archives and staged binary identities are retained.'
	}, prettify: true) + '\n')!
	println('INTERPOLATORS-RETAIN PASS ${artifacts.len} artifacts;${fixture.len} frozen fixture sources')
}
