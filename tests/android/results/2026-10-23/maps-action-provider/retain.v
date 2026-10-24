import os
import json2
import crypto.sha256
import compress.gzip
import time

const base = 'build/android-maps/'
const framework = 'framework244-action-provider/'

struct Inputs {
	framework_source_files          int
	native_source_files             int
	files_sha256                    map[string]string
	staged_runtime_sha256           map[string]string
	additional_native_sha256        map[string]string
	prior_receipt                   string
	prior_receipt_sha256            string
	native_precision_receipt        string
	native_precision_receipt_sha256 string
	scope                           string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn copy_file(source string, target string) ! {
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
}

fn inputs(out string) ! {
	assert !os.exists(out + '/inputs.json'), 'Inputs are immutable after capture'
	manifest := json2.decode[map[string]json2.Any](os.read_file(base + framework + 'framework-manifest.json')!)!
	framework_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + framework + 'exact-sources.json.gz')!)!.bytestr())!
	declared := manifest['sources']!.as_map()
	assert framework_sources.len == declared.len
	for name, source in framework_sources {
		assert sha256.sum(source.bytes()).hex() == declared[name]!.str(), name
	}
	assert digest(base + framework + 'api-impl.jar')! == manifest['output_sha256']!.str()
	assert manifest['output_sha256']!.str() == '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'
	previous_framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-popup-menus/framework/exact-sources.json.gz')!)!.bytestr())!
	assert framework_sources.len == 113 && previous_framework.len == 112
	mut delta := map[string]map[string]string{}
	for name, source in framework_sources {
		if source != previous_framework[name] {
			delta[name] = {
				'previous_sha256': if name in previous_framework {
					sha256.sum(previous_framework[name].bytes()).hex()
				} else {
					''
				}
				'current_sha256':  sha256.sum(source.bytes()).hex()
			}
		}
	}
	assert delta.len == 2
	for name in ['tests/native-android-tools/androidtools/framework_classes.v',
		'tests/native-android-tools/androidtools/framework_action_provider.v'] {
		assert name in delta, name
	}
	for name in previous_framework.keys() {
		assert name in framework_sources, name
	}
	os.mkdir_all(out + '/framework')!
	os.write_file(out + '/framework/source-delta-from243.json', json2.encode(delta, prettify: true) + '\n')!
	native_manifest := json2.decode[map[string]string](os.read_file(base + 'native236-sources.json')!)!
	native_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + 'native236-exact-sources.json.gz')!)!.bytestr())!
	assert native_sources.len == 83 && native_sources.len == native_manifest.len
	for name, source in native_sources {
		assert sha256.sum(source.bytes()).hex() == native_manifest[name], name
	}
	assert digest(base + 'libnative236.so')! == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	previous_native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-popup-menus/native/exact-sources.json.gz')!)!.bytestr())!
	assert previous_native.len == native_sources.len
	mut native_delta := map[string]map[string]string{}
	for name, source in native_sources {
		assert name in previous_native, name
		if source != previous_native[name] {
			native_delta[name] = {'previous_sha256': sha256.sum(previous_native[name].bytes()).hex(), 'current_sha256': sha256.sum(source.bytes()).hex()}
		}
	}
	assert native_delta.len == 0
	os.mkdir_all(out + '/native')!
	os.write_file(out + '/native/source-delta-from236.json', json2.encode(native_delta, prettify: true) + '\n')!
	pre := json2.decode[map[string]string](os.read_file(base + 'identity244-inputs/pre-run-sha256.json')!)!
	assert pre.len == 7
	assert digest(base + 'identity244-inputs/vinix')! == pre['boot/vinix']
	assert digest(base + 'identity244-inputs/limine.conf')! == pre['boot/limine.conf']
	mut files := map[string]string{}
	for path in ['libnative236.so', 'GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk',
		framework + 'api-impl.jar', framework + 'classes.dex', 'suite239-stream', 'launcher200',
		'run244', 'interact244', 'manual244', 'identity244', 'verify-maps244-inputs'] {
		files[path] = digest(base + path)!
	}
	mut staged := map[string]string{}
	for path in ['opt/android-test/native-guest',
		'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session'] {
		staged[path] = digest(base + 'attempt244/module/' + path)!
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == files['libnative236.so']
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == files[framework + 'api-impl.jar']
	mut headers := map[string]string{}
	for name in ['android-native.c', 'androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		headers[name] = digest(base + 'native236/' + name)!
	}
	for source, target in {
		framework + 'framework-manifest.json':     'framework/manifest.json'
		framework + 'exact-sources.json.gz':       'framework/exact-sources.json.gz'
		'native236-sources.json':                  'native/sources-sha256.json'
		'native236-exact-sources.json.gz':         'native/exact-sources.json.gz'
		'native236-identity.txt':                  'native/identity.txt'
		'native236-production-source-sha256.json': 'native/production-source-sha256.json'
		'native236-source-delta.json':             'native/builder-source-delta-from235.json'
		'identity244-inputs/pre-run-sha256.json':  'pre-run/sha256.json'
		'identity244-inputs/scope.txt':            'pre-run/scope.txt'
		'identity244-inputs/limine.conf':          'pre-run/limine.conf'
		'attempt244.json':                         'configuration.json'
	} {
		copy_file(base + source, out + '/' + target)!
	}
	mut generated := map[string]string{}
	for name in ['AnimationUtils', 'VinixInterpolatorXml', 'PathInterpolator', 'LinearInterpolator',
		'AccelerateInterpolator', 'DecelerateInterpolator', 'AccelerateDecelerateInterpolator',
		'CycleInterpolator', 'AnticipateInterpolator', 'OvershootInterpolator',
		'AnticipateOvershootInterpolator', 'BounceInterpolator'] {
		path := 'android/view/animation/' + name + '.smali'
		generated[path] = os.read_file(base + framework + 'smali/' + path)!
	}
	for path in ['android/animation/VinixPathValues.smali', 'android/graphics/drawable/PathParser.smali',
		'android/view/View.smali', 'android/view/TextureView.smali', 'android/view/WindowInsets.smali',
		'android/view/WindowInsets$Builder.smali', 'android/view/WindowInsets$Type.smali',
		'android/graphics/Insets.smali', 'android/text/format/DateUtils.smali',
		'android/graphics/BlurMaskFilter.smali', 'android/graphics/BlurMaskFilter$Blur.smali',
		'android/graphics/Canvas.smali', 'android/atl/GskCanvas.smali',
		'android/view/ActionProvider.smali', 'android/view/ActionProvider$VisibilityListener.smali',
		'android/view/ActionProvider$SubUiVisibilityListener.smali', 'android/view/MenuItem.smali',
		'android/widget/PopupMenu.smali', 'android/widget/VinixPopupMenuClick.smali',
		'android/widget/VinixPopupMenuDismiss.smali', 'android/view/VinixMenu.smali',
		'android/view/VinixMenuItem.smali'] {
		generated[path] = os.read_file(base + framework + 'smali/' + path)!
	}
	os.write_file_array(out + '/framework/generated-smali.json.gz', gzip.compress(json2.encode(generated).bytes())!)!
	for name in ['build-native236.v', 'prepare-framework244.v', 'build-framework244-action-provider.v',
		'snapshot-framework244.v', 'prepare244.v', 'finish-prepare244.v', 'run244.v', 'interact244.v', 'manual244.v',
		'identity244.v', 'verify-maps244-inputs.v', 'trace-input.v', 'prepare-maps244-receipt.v',
		'verify-maps244-delta.v', 'capture-maps244-inputs.v',
		'validate-module-stream.v', 'suite-low-disk.v', 'suite239-stream.v'] {
		copy_file(base + name, out + '/helpers/' + name)!
	}
	for name in ['pipeline.v.txt', 'prototype.v.txt', 'prototype.v', 'prepare.v', 'suite.diff',
		'sha256.json', 'final-sha256.json', 'prototype.log', 'root-proof.log', 'production-proof.log',
		'production-sources-sha256.json'] {
		copy_file(base + 'stream238/' + name, out + '/streaming/' + name)!
	}
	for path in ['build-support/android/modulestream/stream.v',
		'build-support/android/modulestream/stream_test.v', 'tests/native-android-ws/suite.v'] {
		copy_file(path, out + '/streaming/production/' + os.base(path))!
	}
	for source, name in {
		'build-native236.log': 'native236-build.log'
		'framework244-build.log': 'framework244-build.log'
	} {
		os.write_file_array(out + '/' + name + '.gz', gzip.compress(os.read_bytes(base + source)!)!)!
	}
	for path in os.walk_ext(base + 'interpolator-resources234', '') {
		copy_file(path, out + '/maps-resources/' + os.base(path))!
	}
	assert os.read_file(out + '/maps-resources/apk-sha256.txt')!.trim_space() == files['GoogleMaps.apk']
	prior := '../maps-popup-menus/receipt.json'
	os.write_file(out + '/inputs.json', json2.encode(Inputs{
		framework_source_files:          framework_sources.len
		native_source_files:             native_sources.len
		files_sha256:                    files
		staged_runtime_sha256:           staged
		additional_native_sha256:        headers
		prior_receipt:                   prior
		prior_receipt_sha256:            digest(out + '/' + prior)!
		native_precision_receipt:        '../interpolators/receipt.json'
		native_precision_receipt_sha256: digest(out + '/../interpolators/receipt.json')!
		scope:                           'Maps244 adds the real ActionProvider base API relative to Maps243. Only framework_classes.v and the new framework_action_provider.v change in the 113-source framework. The complete native236 83-source archive, APKs, launcher and frozen suite239-stream binary are unchanged. Exact V archives and selected generated Smali are retained; binary APK/JAR/ELF/DEX/kernel/firmware/image artifacts are identified by hashes. Pre-run image/kernel/EFI/QEMU hashes were recorded before runtime injection; staged runtime hashes identify the injected module. Both Maps244 and Maps245 were interrupted before a final harness result. Workflow observations and interruption metadata are recorded separately; no final raw application outcome is inferred.'
	}, prettify: true) + '\n')!
	println('MAPS244-INPUTS PASS framework=' + framework_sources.len.str() + ' native=83 staged=7 pre-run=7')
}

fn result(out string) ! {
	assert os.exists(out + '/inputs.json'), 'Capture staged inputs before retaining results'
	assert os.exists(out + '/resume245/preflight.json'), 'Retain continuation preflight first'
	assert !os.exists(out + '/interruption245.json'), 'Interruption snapshot is immutable'
	run := base + 'attempt245/'
	assert !os.exists(run + 'results.json'), 'This retention path records an interrupted run only'
	assert !os.exists(base + 'attempt245-harness.log')
	assert !os.exists(base + 'interact245.log')
	copy_file(run + 'companion-packages.json', out + '/companion-packages.json')!
	app := run + 'google-maps/'
	serial := os.read_bytes(app + 'serial.log')!
	log := serial.bytestr()
	assert log.contains('APK-SUITE-BEGIN id=google-maps ')
	assert log.contains('ANDROID-WS-READY backend=vinix-native')
	assert !log.contains('APK-SUITE-EXIT id=google-maps')
	assert !log.contains('ANDROID-WS-FAIL')
	if os.exists(app + 'serial.log.gz') {
		assert gzip.decompress(os.read_bytes(app + 'serial.log.gz')!)! == serial
	}
	os.write_file_array(out + '/serial.log.gz', gzip.compress(serial)!)!
	for name in os.ls(app)! {
		if name in ['serial.log', 'serial.log.gz'] { continue }
		if os.file_ext(name) in ['.png', '.log', '.txt', '.json'] || name == 'qemu.pid' {
			copy_file(app + name, out + '/run/' + name)!
		}
	}
	for name in ['attempt245-harness.log', 'run245-console.log', 'interact245.log', 'attempt245-timeline.log',
		'pan245.log', 'manual245-map-wait.log', 'map-wait245.log', 'wait-map245.log'] {
		if os.exists(base + name) { copy_file(base + name, out + '/run/' + name)! }
	}
	if os.exists(app + 'network.pcap') {
		os.write_file(out + '/network-pcap-sha256.txt', digest(app + 'network.pcap')! + '\n')!
	}
	processes := os.exec(['ps', '-o', 'pid,ppid,lstart,etime,command', '-p', '98852,99069,99070,1969'])
	assert !processes.output.contains('build/android-maps/run245')
	assert !processes.output.contains('build/android-maps/suite245-resume')
	assert !processes.output.contains('qemu-system-aarch64')
	os.write_file(out + '/resume245/processes-at-recovery.txt', time.utc().str() + ' UTC\n' + processes.output)!
	mut record := map[string]json2.Any{}
	record['captured_utc'] = time.utc().str() + ' UTC'
	record['serial_sha256'] = sha256.sum(serial).hex()
	record['serial_bytes'] = i64(serial.len)
	record['results_json_present'] = false
	record['final_harness_log_present'] = false
	record['final_interaction_log_present'] = false
	record['application_exit_marker_present'] = false
	record['framework_failure_marker_present'] = false
	record['observation_completed'] = false
	record['configured_observation_seconds'] = 900
	record['observed_end'] = 'Last timestamp in retained serial is 2026-10-23 16:07:33 UTC. The last successful screenshot at 19:07:34 UTC+3 shows the route overview after returning from Preview. The former wrapper, suite and QEMU processes were absent at recovery. The headless session ended before final results or harness/interaction logs were written. Completed UI actions are supported by screenshots and the manual timeline; completion of the configured 900-second observation and a final raw classifier are unavailable.'
	os.write_file(out + '/interruption245.json', json2.encode(record, prettify: true) + '\n')!
	println('MAPS245-INTERRUPTED retained partial serial/screenshots/timeline; completed UI workflow, no final classifier or completed 900-second observation')
}

fn resume_inputs(out string) ! {
	assert !os.exists(out + '/resume245/preflight.json'), 'Continuation input snapshot is immutable'
	pre := json2.decode[map[string]json2.Any](os.read_file(base + 'identity245-inputs/preflight.json')!)!
	assert pre['staged_runtime_sha256']!.as_map() == pre['archive_runtime_sha256']!.as_map()
	inputs_row := json2.decode[map[string]json2.Any](os.read_file(out + '/inputs.json')!)!
	assert pre['staged_runtime_sha256']!.as_map() == inputs_row['staged_runtime_sha256']!.as_map()
	before := json2.decode[map[string]string](os.read_file(base + 'identity245-inputs/helpers-before-run.json')!)!
	assert before.len == 15
	for path, expected in before { assert digest(path)! == expected, path }
	for name in ['preflight.json', 'preflight-sha256.txt', 'helpers-before-run.json',
		'helpers-before-run-scope.txt'] {
		copy_file(base + 'identity245-inputs/' + name, out + '/resume245/' + name)!
	}
	for path in os.walk_ext(base + 'identity245-inputs/helpers', '') {
		copy_file(path, out + '/resume245/helpers/' + os.base(path))!
	}
	for name in ['preflight245.log', 'validate244-inputs.log', 'retain244-inputs.log'] {
		copy_file(base + name, out + '/resume245/' + name)!
	}
	os.write_file(out + '/resume245/scope.txt', 'Maps245 boots the already staged Maps244 FAT image. A read-only V preflight hashes the full image once and streams its runtime archive to verify seven entries against staged files. The resumed suite trusts that preflight image hash and checks image size/mtime plus staged file hashes; it does not independently hash the full image again. Original APK inspection, QEMU arguments, observation timing and classification are preserved. Both runs were interrupted; neither establishes a completed observation or final raw classifier.\n')!
	println('MAPS245-INPUTS PASS archive/staged7 identical; 15 helper identities frozen before launch')
}

fn main() {
	assert os.args.len == 2 && os.args[1] in ['inputs', 'resume-inputs', 'result', 'manifest'], 'usage: retain.v inputs|resume-inputs|result|manifest'
	out := os.dir(@FILE)
	if os.args[1] == 'inputs' { inputs(out)! }
	if os.args[1] == 'resume-inputs' { resume_inputs(out)! }
	if os.args[1] == 'result' { result(out)! }
	mut artifacts := map[string]string{}
	for path in os.walk_ext(out, '') {
		name := path.all_after(out + '/')
		if name !in ['receipt.json', 'validation.log', 'retain', 'validate'] {
			artifacts[name] = digest(path)!
		}
	}
	os.write_file(out + '/receipt.json', json2.encode(artifacts, prettify: true) + '\n')!
}
