import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const task = base + 'alpha224/'
const dest = 'tests/android/results/2026-10-23/alpha8/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn serial(mode string) !string {
	return gzip.decompress(os.read_bytes(task + 'run-' + mode + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
}

fn main() {
	b := serial('baseline')!
	f := serial('fixed')!
	canvas_marker := 'BOOTSTRAP-ALPHA8-PASS padded-stride byte-count erase get-set-pixels source-over clip paint-tinted-mask ARGB-preserved self-copy'
	gl_marker := 'BOOTSTRAP-ALPHA8-GL-PASS alpha-texture odd-width padded-rows shader-readback subimage unpack-state rejected-overrun'
	assert b.contains('Native WS bitmap storage requires ARGB_8888') && b.contains('Alpha8Probe.check')
	assert !b.contains(canvas_marker) && !b.contains(gl_marker)
	assert f.count(canvas_marker) >= 1 && f.count(gl_marker) >= 1
	assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
	fixed_result := json2.decode[[]map[string]json2.Any](os.read_file(task + 'run-fixed/results.json')!)![0]
	assert fixed_result['outcome']!.str() == 'startup_failed'
	assert fixed_result['backend_ready']!.bool() && !fixed_result['process_exited']!.bool()
	failure_markers := fixed_result['failure_markers']!.as_array()
	assert failure_markers.len == 2
	assert failure_markers[0].str().contains('NoSuchFieldError: no type "Lnge;"')
	assert failure_markers[1].str() == 'Caused by: java.lang.ClassNotFoundException: nge'
	assert f.contains('ANDROID-WS-TRANSITION-FUTURE-DIAGNOSTIC-FAIL')
	old := gzip.decompress(os.read_bytes(base + 'autofill-manager223/run-fixed/bootstrap-fixture/serial.log.gz')!)!.bytestr()
	mut markers := []string{}
	for line in old.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in markers { continue }
		assert f.contains(name), name
		markers << name
	}
	os.mkdir_all(dest)!
	mut artifacts := map[string]json2.Any{}
	for mode in ['baseline', 'fixed'] {
		for name in ['results.json', 'bootstrap-fixture/serial.log.gz',
			'bootstrap-fixture/application.png', 'staged-runtime-sha256.json'] {
			out := mode + '-' + os.base(name)
			os.cp(task + 'run-' + mode + '/' + name, dest + out)!
			artifacts[out] = hash(dest + out)!
		}
		for name in ['-harness.log', '.json'] {
			out := mode + if name == '.json' { '-configuration.json' } else { name }
			os.cp(task + mode + name, dest + out)!
			artifacts[out] = hash(dest + out)!
		}
		row := json2.decode[[]map[string]json2.Any](os.read_file(task + 'run-' + mode + '/results.json')!)![0]
		assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(base + 'alpha224-apk/bootstrap.apk')!
		runtime := json2.decode[map[string]string](os.read_file(task + 'run-' + mode + '/staged-runtime-sha256.json')!)!
		assert runtime['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']! == hash(base + 'framework223-autofill/api-impl.jar')!
		native := base + if mode == 'baseline' { 'libnative221.so' } else { 'libnative225.so' }
		assert runtime['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']! == hash(native)!
		assert runtime['usr/bin/run-android-calculator']! == hash(base + 'launcher200')!
	}
	for source, out in {
		'validate-alpha224.v':                                        'validate.v'
		'prepare-alpha224.v':                                         'prepare.v'
		'alpha224/staged-hashes.v':                                   'staged-hashes.v'
		'build-native225.v':                                          'build-native.v'
		'native225-sources.json':                                     'fixed-native-sources.json'
		'finalize-alpha224.v':                                        'finalize-fixture.v'
		'finalize-alpha224.log':                                      'finalize-fixture.log'
		'suite-low-disk.v':                                           'suite.v'
		'alpha224/initial-run-fixed/bootstrap-fixture/serial.log.gz': 'initial-fixed-serial.log.gz'
		'alpha224/initial-alpha8-gl.v':                               'initial-alpha8-gl.v'
	} {
		os.cp(base + source, dest + out)!
		artifacts[out] = hash(dest + out)!
	}
	for entry in [
		['fixture-sources.tar.gz', base + 'alpha224-apk', 'smali', 'res'],
		['fixture-v-sources.tar.gz', base + 'alpha224/source/startupfixture', 'alpha8.v', 'alpha8_gl.v',
			'startup.v', 'glutils.v'],
		['fixed-native-changed-sources.tar.gz', base + 'native225/atlframework', 'bitmaps.v',
			'graphics.v', 'glutils.v', 'ndk_surfaces.v'],
	] {
		mut args := ['tar', '-czf', os.abs_path(dest + entry[0]), '-C', entry[1]]
		args << entry[2..]
		r := os.exec(args)
		assert r.exit_code == 0, r.output
		artifacts[entry[0]] = hash(dest + entry[0])!
	}
	mut sources := map[string]json2.Any{}
	for name in ['alpha8.v', 'alpha8_gl.v', 'startup.v', 'glutils.v'] {
		sources['tests/native-android-ws/startupfixture/' + name] = hash(task + 'source/startupfixture/' + name)!
	}
	identity := 'tests/android/results/2026-10-23/maps-ws/attempt225-input-identities.json'
	assert os.is_file(identity)
	receipt := {
		'artifacts_sha256':                          json2.Any(artifacts)
		'sources_sha256':                            json2.Any(sources)
		'framework223_sha256':                       json2.Any(hash(base + 'framework223-autofill/api-impl.jar')!)
		'baseline_native221_sha256':                 json2.Any(hash(base + 'libnative221.so')!)
		'fixed_native225_sha256':                    json2.Any(hash(base + 'libnative225.so')!)
		'fixture_apk_sha256':                        json2.Any(hash(base + 'alpha224-apk/bootstrap.apk')!)
		'initial_fixture_apk_sha256':                json2.Any(hash(task + 'initial-bootstrap.apk')!)
		'initial_probe_limit':                       json2.Any('The first ALPHA8 APK reached Canvas PASS but its GL geometry used an existing unsupported glVertexAttribPointerBounds Buffer overload. That fixture-only failure is retained in initial-fixed-serial.log.gz and initial-alpha8-gl.v. Geometry was changed to the established VBO/integer-offset path, then the same newly signed APK was rerun on both baseline221 and fixed225; the result claims and hashes here describe that final pair.')
		'harness_binary_sha256':                     json2.Any(hash(base + 'suite159')!)
		'alpha8_canvas_pass_count':                  json2.Any(f.count(canvas_marker))
		'alpha8_gl_pass_count':                      json2.Any(f.count(gl_marker))
		'previous_pass_markers_retained':            json2.Any(markers.len)
		'fixed_raw_harness_outcome':                 fixed_result['outcome']!
		'fixed_raw_harness_failure_markers':         fixed_result['failure_markers']!
		'harness_limit':                            json2.Any('The fixed raw harness result is startup_failed, not a clean harness pass: native225 inherits the Maps-only queue219.v transition diagnostic, which attempts Main.bB:Lnge; on this fixture. It prints NoSuchFieldError/ClassNotFoundException and explicitly clears the exception. The validator requires exactly these two failure markers, backend_ready true and process_exited false, and separately requires both ALPHA8 assertion markers, all 95 earlier probe markers and READY, with no AssertionError, ANDROID-WS-FAIL or APK-SUITE-EXIT. The result claims are limited to those observed fixture contracts. The unmodified raw result and serial diagnostic are retained.')
		'full_native_input_identity_receipt':        json2.Any(identity)
		'full_native_input_identity_receipt_sha256': json2.Any(hash(identity)!)
		'scope':                                     json2.Any('The identical signed APK fails on native221 at the Canvas(ALPHA_8) rejection observed in Maps and reaches both ALPHA8 assertion PASS markers on native225 with framework223 and launcher200 held identical; the raw harness outcome qualification is stated separately. Canvas checks padded 3x2 storage (rowBytes4, byteCount8), alpha-only erase/get/setPixels, source-over alpha and clip bounds, paint-tinted masks into ARGB8888, and overlapping self-copy. On a real GLES context the GL probe shader-samples all three odd-width first-row texels and a second-row texel from GL_ALPHA storage, verifies explicit subimage upload, unpack state preservation and safe rejection when unpack8 would read past allocation. All prior fixture probes and READY remain. No NDK lock or standalone Maps success is claimed. Native224 was never booted; task directory name alpha224 was allocated before the stride correction required native225. Exact full native225 source and framework input retention is linked separately.')
	}
	os.write_file(dest + 'receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	println('ALPHA8-VALIDATION PASS identical signed APK; baseline Canvas rejection; fixed padded storage, Canvas pixels and GL_ALPHA shader readback; ${markers.len} previous markers retained; staged hashes verified')
}
