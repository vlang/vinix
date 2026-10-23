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
	task := b + 'dates240/'
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
			'framework239-insets'
		} else {
			'framework240-date-ranges'
		}
		os.cp(b + jar + '/framework-manifest.json', out + '/' + mode + '-framework-manifest.json')!
		os.cp(b + jar + '/exact-sources.json.gz', out + '/' + mode + '-framework-sources.json.gz')!
		for name in ['DateUtils', 'DateFormat'] {
			path := task + 'verify-' + mode + '-smali/android/text/format/' + name + '.smali'
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
	os.write_file_array(out + '/DateUtils-aosp.java.gz', gzip.compress(os.read_bytes(b + 'DateUtils-aosp.java')!)!)!
	for name in ['DateRangesProbe', 'FailRangeAppendable', 'StartupProbe'] {
		os.write_file_array(out + '/' + name + '.smali.gz', gzip.compress(os.read_bytes(task + 'verify-apk-smali/org/vinix/bootstrap/' + name + '.smali')!)!)!
	}

	for source, name in {
		b + 'prepare-dates240.v':               'prepare-fixture.v'
		b + 'refresh-dates240.v':               'refresh-fixture.v'
		b + 'build-dates240.v':                 'build-fixture.v'
		task + 'build.log':                     'fixture-build.log'
		b + 'prepare-dates-proof240.v':         'prepare-proof.v'
		task + 'proof-prepare.log':             'proof-prepare.log'
		task + 'staged-hashes.v':               'staged-hashes.v'
		b + 'prepare-framework240.v':           'prepare-framework.v'
		b + 'build-framework240-date-ranges.v': 'build-framework.v'
		b + 'snapshot-framework240.v':          'snapshot-framework.v'
		b + 'native235-exact-sources.json.gz':  'native-sources.json.gz'
		b + 'native235-sources.json':           'native-sources-sha256.json'
		b + 'native235-identity.txt':           'native-identity.txt'
	} {
		os.cp(source, out + '/' + name)!
	}
	os.write_file_array(out + '/DateIntervalFormat.smali.gz', gzip.compress(os.read_bytes(b + 'date-core/libcore/icu/DateIntervalFormat.smali')!)!)!
	for name in ['framework239-insets/api-impl.jar', 'framework240-date-ranges/api-impl.jar',
		'libnative235.so', 'dates240-apk/bootstrap.apk', 'suite159'] {
		inputs[b + name] = hash(b + name)!
	}
	inputs['prior-window-insets/receipt.json'] = hash(out + '/../window-insets/receipt.json')!
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
		scope:     'Identical signed APK and native235 across framework239 baseline and framework240 fixed. Exact missing full Formatter DateUtils API baseline. Tests literal range values and endpoints under default US locale, UTC/null/default/explicit zones, UTC flag precedence in actual core ICU, explicit 12/24-hour and current 24-hour preference, Formatter identity, percent prefix, repeated append, String and point wrappers, closed Formatter, IOException cause, and Locale/category/timezone restoration. All prior probes enabled. Only framework_date_ranges.v and its startup hook differ. Exact sources, actual signed/framework DEX, staged identities and raw outcomes retained. No Maps functional outcome implied.'
	}, prettify: true) + '\n')!
	println('DATE-RANGES RETAIN PASS ${artifacts.len} artifacts')
}
