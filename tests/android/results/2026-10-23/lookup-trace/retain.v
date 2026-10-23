import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn cp(src string, dst string) ! { os.cp(src, dst)! }

fn gz(src string, dst string) ! { os.write_file_array(dst, gzip.compress(os.read_bytes(src)!)!)! }

fn main() {
	out := 'tests/android/results/2026-10-23/lookup-trace'
	b := 'build/android-maps/'
	p := b + 'lookup237/'
	f := b + 'framework237-lookup/'
	os.mkdir_all(out)!
	for pair in [
		[b + 'prepare-framework237.v', 'prepare-framework.v'],
		[b + 'build-framework237-lookup.v', 'build-framework.v'],
		[b + 'snapshot-lookup237.v', 'snapshot-framework.v'],
		[b + 'check-lookup237.v', 'check-invariant.v'],
		[p + 'source-validation.log', 'source-validation.log'],
		[p + 'invariant-validation.log', 'invariant-validation.log'],
		[b + 'prepare-lookup237.v', 'prepare-fixture.v'],
		[p + 'staged-hashes.v', 'staged-hashes.v'],
		[f + 'framework-manifest.json', 'raw-checkout-manifest.json'],
		[f + 'frozen-sources.json.gz', 'frozen-framework-sources.json.gz'],
		[f + 'frozen-source-sha256.json', 'frozen-framework-source-sha256.json'],
		[b + 'framework236-texture/exact-sources.json.gz', 'baseline-framework-sources.json.gz'],
		[b + 'framework236-texture/framework-manifest.json', 'baseline-framework-manifest.json'],
		[p + 'lookup-trace-fixture.v', 'build-fixture.v'],
		['tests/android/results/2026-10-23/interpolators/fixed-native-sources.json.gz',
			'native235-sources.json.gz'],
		['tests/android/results/2026-10-23/interpolators/fixed-native-sources-sha256.json',
			'native235-sources-sha256.json'],
		['tests/android/results/2026-10-23/interpolators/fixed-native-identity.txt',
			'native235-identity.txt'],
	] {
		cp(pair[0], out + '/' + pair[1])!
	}
	for pair in [
		[b + 'framework237-build.log', 'framework-build.log.gz'],
		[b + 'framework236-texture/smali/android/view/ViewGroup.smali', 'baseline-ViewGroup.smali.gz'],
		[f + 'smali/android/view/ViewGroup.smali', 'generated-ViewGroup.smali.gz'],
		[f + 'actual-dex/android/view/ViewGroup.smali', 'actual-ViewGroup.smali.gz'],
		[f + 'actual-dex/android/atl/VinixViewLookupTrace.smali', 'actual-lookup-helper.smali.gz'],
		[b + 'lookup237-apk/classes.dex', 'fixture-classes.dex.gz'],
	] {
		gz(pair[0], out + '/' + pair[1])!
	}
	mut fixture := map[string]string{}
	for path in os.walk_ext(b + 'lookup237-apk/smali', '.smali') {
		fixture[path.all_after('lookup237-apk/smali/')] = os.read_file(path)!
	}
	os.write_file_array(out + '/fixture-smali.json.gz', gzip.compress(json2.encode(fixture).bytes())!)!
	mut inputs := map[string]string{}
	for path in [
		b + 'lookup237-apk/probe.apk',
		b + 'framework236-texture/api-impl.jar',
		f + 'api-impl.jar',
		b + 'libnative235.so',
		'build/android-native-ws/original-qemu-runtime.tar',
		'build/qemu-horizontal/bin/qemu-system-aarch64',
		'/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'build/android-maps/suite159',
		'build/android-run',
	] {
		inputs[path] = hash(path)!
	}
	inputs['inherited-native235-receipt'] = hash('tests/android/results/2026-10-23/interpolators/receipt.json')!
	for mode in ['baseline', 'off', 'on'] {
		run := p + 'run-' + mode + '/'
		for pair in [[p + mode + '.json', 'configuration.json'], [p + mode + '-harness.log',
			'harness.log'], [p + 'launcher-' + mode + '.v', 'launcher.v'],
			[run + 'results.json', 'results.json'],
			[run + 'staged-runtime-sha256.json', 'staged-runtime-sha256.json'],
			[run + 'bootstrap-fixture/serial.log.gz', 'serial.log.gz']] {
			cp(pair[0], out + '/' + mode + '-' + pair[1])!
		}
		staged := json2.decode[map[string]string](os.read_file(run + 'staged-runtime-sha256.json')!)!
		for path, digest in staged { inputs[mode + '/staged/' + path] = digest }
	}
	cp(b + 'retain-lookup237.v', out + '/retain.v')!
	mut artifacts := map[string]string{}
	for name in os.ls(out)! {
		if name == 'receipt.json' { continue }
		artifacts[name] = hash(out + '/' + name)!
	}
	os.write_file(out + '/receipt.json', json2.encode(Receipt{ artifacts: artifacts, inputs: inputs, scope: 'Three boots of one signed standalone APK: immutable framework236 baseline, framework237 default disabled, framework237 opt-in enabled. Native235 unchanged. No Maps performance benchmark.' },
		prettify: true
	) + '\n')!
	println('LOOKUP237 retained ' + artifacts.len.str() + ' artifacts')
}
