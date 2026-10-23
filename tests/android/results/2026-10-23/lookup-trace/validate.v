import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn gz(path string) !string { return gzip.decompress(os.read_bytes(path)!)!.bytestr() }

fn digest(text string) string { return sha256.sum(text.bytes()).hex() }

fn main() {
	out := os.dir(@FILE)
	r := json2.decode[Receipt](os.read_file(out + '/receipt.json')!)!
	for name, hash in r.artifacts {
		assert sha256.sum(os.read_bytes(out + '/' + name)!).hex() == hash, name
	}
	apk := '1adcb05901925f2a00352206b2806360f993dae39d335d931672d3296f88ebb5'
	base_jar := '9f5ddfbb7a17cff8265c0c1a4dba752b59a9ac12e88801e15c26b17654f0c584'
	fixed_jar := 'f19e4f06f69118447b52ac55b22eae4d6568bbac099ad57dab11d80c9c985199'
	native := '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	assert r.inputs['build/android-maps/lookup237-apk/probe.apk'] == apk
	assert r.inputs['build/android-maps/framework236-texture/api-impl.jar'] == base_jar
	assert r.inputs['build/android-maps/framework237-lookup/api-impl.jar'] == fixed_jar
	assert r.inputs['build/android-maps/libnative235.so'] == native
	mut counts := map[string]int{}
	for mode in ['baseline', 'off', 'on'] {
		serial := gz(out + '/' + mode + '-serial.log.gz')!
		assert serial.contains('LOOKUP-TRACE-PASS') && serial.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
		for forbidden in ['ANDROID-WS-FAIL', 'java.lang.AssertionError',
			'APK-SUITE-EXIT id=bootstrap-fixture'] {
			assert !serial.contains(forbidden), mode + ': ' + forbidden
		}
		assert serial.count('LOOKUP-TRACE-PROBE-BEGIN') == 1 && serial.count('LOOKUP-TRACE-PROBE-END') == 1
		phase := serial.all_after('LOOKUP-TRACE-PROBE-BEGIN').all_before('LOOKUP-TRACE-PROBE-END')
		assert phase.contains('LOOKUP-WARNING-PRESERVED') && phase.contains('LOOKUP-ERROR-PRESERVED')
		counts[mode] = phase.count('findViewById: looking for id:')
		if mode == 'off' {
			assert counts[mode] == 0 && !phase.contains('findViewById: found:')
			assert phase.contains('LOOKUP-TRACE-RESOURCE-WORK-SKIPPED') && !phase.contains('LOOKUP-TRACE-RESOURCE-WORK-PRESENT')
		} else {
			assert counts[mode] > 0 && phase.count('findViewById: found:') > 0
			assert phase.contains('LOOKUP-TRACE-RESOURCE-WORK-PRESENT') && !phase.contains('LOOKUP-TRACE-RESOURCE-WORK-SKIPPED')
		}
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == digest(serial)
		assert row['metadata']!.as_map()['apk_sha256']!.str() == apk
		assert row['outcome']!.str() == 'window_observed' && row['failure_markers']!.as_array().len == 0
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool() && row['backend_ready']!.bool()
		assert !row['process_exited']!.bool()
		staged := json2.decode[map[string]string](os.read_file(out + '/' + mode + '-staged-runtime-sha256.json')!)!
		assert staged.len == 6
		for path, hash in staged {
			assert r.inputs[mode + '/staged/' + path] == hash, path
			if !path.ends_with('api-impl.jar') && path != 'usr/bin/run-android-calculator' {
				assert hash == r.inputs['baseline/staged/' + path], path
			}
		}
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == if mode == 'baseline' {
			base_jar
		} else {
			fixed_jar
		}
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == native
		launcher := os.read_file(out + '/' + mode + '-launcher.v')!
		assert launcher.contains(if mode == 'on' {
			"os.setenv('VINIX_ANDROID_TRACE_VIEW_LOOKUP', '1', true)"
		} else {
			"os.unsetenv('VINIX_ANDROID_TRACE_VIEW_LOOKUP')"
		})
		assert launcher.contains("os.setenv('LOOKUP_EXPECT_TRACE', '" + if mode == 'off' {
			'0'
		} else {
			'1'
		} + "', true)")
	}
	assert counts['baseline'] == counts['on']
	baseline := gz(out + '/baseline-ViewGroup.smali.gz')!
	mut generated := gz(out + '/generated-ViewGroup.smali.gz')!
	for n in 0 .. 2 {
		label := ':vinix_lookup_trace_skip_' + n.str()
		gate := '    sget-boolean v0, Landroid/atl/VinixViewLookupTrace;->enabled:Z\n    if-eqz v0, ' + label + '\n'
		assert generated.count(gate) == 1 && generated.count('    ' + label + '\n\n') == 1
		generated = generated.replace_once(gate, '').replace_once('    ' + label + '\n\n', '')
	}
	assert generated == baseline, 'entire original ViewGroup must be byte-identical after removing only the gates'
	assert digest(generated) == 'bbd39627978aaa7724fb78e87a14cdb3f80c129853d7bf03417182190838de4a'
	assert gz(out + '/actual-ViewGroup.smali.gz')!.count('Landroid/atl/VinixViewLookupTrace;->enabled:Z') == 2
	helper := gz(out + '/actual-lookup-helper.smali.gz')!
	assert helper.contains('VINIX_ANDROID_TRACE_VIEW_LOOKUP') && helper.contains('Ljava/lang/System;->getenv') && helper.contains('Ljava/lang/String;->equals')
	frozen := json2.decode[map[string]string](gz(out + '/frozen-framework-sources.json.gz')!)!
	hashes := json2.decode[map[string]string](os.read_file(out + '/frozen-framework-source-sha256.json')!)!
	assert frozen.len == 129 && frozen.len == hashes.len
	for name, source in frozen {
		assert digest(source) == hashes[name], name
	}
	base := json2.decode[map[string]string](gz(out + '/baseline-framework-sources.json.gz')!)!
	manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/baseline-framework-manifest.json')!)!
	assert manifest['output_sha256']!.str() == base_jar
	assert base.len == 106 && base.len == manifest['sources']!.as_map().len
	mut changed := []string{}
	for name, source in base {
		assert digest(source) == manifest['sources']!.as_map()[name]!.str(), name
		assert name in frozen
		if source != frozen[name] { changed << os.base(name) }
	}
	assert changed == ['framework_startup.v'], changed.str()
	startup := 'tests/native-android-tools/androidtools/framework_startup.v'
	assert frozen[startup].replace_once(' framework_lookup_trace(smali)!\n', '') == base[startup]
	assert !frozen[startup].contains('framework_window_insets')
	for name in frozen.keys() {
		if name in base { continue }
		assert !os.base(name).starts_with('framework') || os.base(name) == 'framework_lookup_trace.v', name
	}
	raw := json2.decode[map[string]json2.Any](os.read_file(out + '/raw-checkout-manifest.json')!)!
	assert raw['output_sha256']!.str() == fixed_jar
	// The builder scanned the concurrent checkout for this non-authoritative map.
	assert raw['sources']!.as_map()[startup]!.str() != hashes[startup]
	native_sources := json2.decode[map[string]string](gz(out + '/native235-sources.json.gz')!)!
	native_hashes := json2.decode[map[string]string](os.read_file(out + '/native235-sources-sha256.json')!)!
	assert native_sources.len == 83 && native_sources.len == native_hashes.len
	for name, source in native_sources {
		assert digest(source) == native_hashes[name], name
	}
	assert os.read_file(out + '/native235-identity.txt')!.contains(native)
	fixture := json2.decode[map[string]string](gz(out + '/fixture-smali.json.gz')!)!
	assert fixture.len == 6
	probe := fixture['org/vinix/bootstrap/LookupProbe.smali']
	assert probe.count('->same(Landroid/view/View;ILandroid/view/View;Ljava/lang/String;)V') == 9
	assert probe.contains('removed branch excluded') && probe.contains('reparented branch follows earlier duplicate')
	assert digest(os.read_file(out + '/build-fixture.v')!) == digest(os.read_file('tests/native-android-ws/lookup-trace-fixture.v')!)
	println('LOOKUP TRACE PASS: three signed guest boots, unchanged lookup bytes, default skips diagnostic resource work, opt-in restores trace, warning/error output retained; ' + r.artifacts.len.str() + ' artifact hashes verified')
}
