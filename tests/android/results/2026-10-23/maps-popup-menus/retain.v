import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const framework = 'framework243-popup-menus/'

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
	assert manifest['output_sha256']!.str() == '0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc'
	previous_framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-canvas-save/framework/exact-sources.json.gz')!)!.bytestr())!
	assert framework_sources.len == 112 && previous_framework.len == 111
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
	assert delta.len == 3
	for name in ['tests/native-android-tools/androidtools/framework_classes.v',
		'tests/native-android-tools/androidtools/framework_popup_menus.v',
		'build-support/android/atlframework/menus.v'] {
		assert name in delta, name
	}
	for name in previous_framework.keys() {
		assert name in framework_sources, name
	}
	os.mkdir_all(out + '/framework')!
	os.write_file(out + '/framework/source-delta-from242.json', json2.encode(delta, prettify: true) + '\n')!
	native_manifest := json2.decode[map[string]string](os.read_file(base + 'native236-sources.json')!)!
	native_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + 'native236-exact-sources.json.gz')!)!.bytestr())!
	assert native_sources.len == 83 && native_sources.len == native_manifest.len
	for name, source in native_sources {
		assert sha256.sum(source.bytes()).hex() == native_manifest[name], name
	}
	assert digest(base + 'libnative236.so')! == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	previous_native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-canvas-save/native/exact-sources.json.gz')!)!.bytestr())!
	assert previous_native.len == native_sources.len
	mut native_delta := map[string]map[string]string{}
	for name, source in native_sources {
		assert name in previous_native, name
		if source != previous_native[name] {
			native_delta[name] = {'previous_sha256': sha256.sum(previous_native[name].bytes()).hex(), 'current_sha256': sha256.sum(source.bytes()).hex()}
		}
	}
	assert native_delta.len == 1 && 'menus.v' in native_delta
	os.mkdir_all(out + '/native')!
	os.write_file(out + '/native/source-delta-from235.json', json2.encode(native_delta, prettify: true) + '\n')!
	pre := json2.decode[map[string]string](os.read_file(base + 'identity243-inputs/pre-run-sha256.json')!)!
	assert pre.len == 7
	assert digest(base + 'identity243-inputs/vinix')! == pre['boot/vinix']
	assert digest(base + 'identity243-inputs/limine.conf')! == pre['boot/limine.conf']
	mut files := map[string]string{}
	for path in ['libnative236.so', 'GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk',
		framework + 'api-impl.jar', framework + 'classes.dex', 'suite239-stream', 'launcher200'] {
		files[path] = digest(base + path)!
	}
	mut staged := map[string]string{}
	for path in ['opt/android-test/native-guest',
		'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session'] {
		staged[path] = digest(base + 'attempt243/module/' + path)!
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
		'identity243-inputs/pre-run-sha256.json':  'pre-run/sha256.json'
		'identity243-inputs/scope.txt':            'pre-run/scope.txt'
		'identity243-inputs/limine.conf':          'pre-run/limine.conf'
		'attempt243.json':                         'configuration.json'
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
		'android/widget/PopupMenu.smali', 'android/widget/VinixPopupMenuClick.smali',
		'android/widget/VinixPopupMenuDismiss.smali', 'android/view/VinixMenu.smali',
		'android/view/VinixMenuItem.smali'] {
		generated[path] = os.read_file(base + framework + 'smali/' + path)!
	}
	os.write_file_array(out + '/framework/generated-smali.json.gz', gzip.compress(json2.encode(generated).bytes())!)!
	for name in ['build-native236.v', 'prepare-framework243.v', 'build-framework243-popup-menus.v',
		'snapshot-framework243.v', 'prepare243.v', 'finish-prepare243.v', 'run243.v', 'interact243.v', 'manual243.v',
		'identity243.v', 'verify-maps243-inputs.v', 'trace-input.v', 'prepare-maps243-receipt.v',
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
		'build-framework243.log': 'framework243-build.log'
		'build-framework243-compile.log': 'framework243-compile.log'
	} {
		os.write_file_array(out + '/' + name + '.gz', gzip.compress(os.read_bytes(base + source)!)!)!
	}
	for path in os.walk_ext(base + 'interpolator-resources234', '') {
		copy_file(path, out + '/maps-resources/' + os.base(path))!
	}
	assert os.read_file(out + '/maps-resources/apk-sha256.txt')!.trim_space() == files['GoogleMaps.apk']
	prior := '../maps-canvas-save/receipt.json'
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
		scope:                           'Maps243 replaces the PopupMenu GTK presentation with a real Dialog and VinixMenu model relative to Maps242. The 112-source framework changes framework_classes.v, framework_popup_menus.v, and its recorded atlframework/menus.v input. Native236 changes only menus.v relative to native235 to resolve menu resources through Context, propagate submenu context, and guard Activity-only action expansion. Native path precision and the independently tested frozen suite239-stream staging helper are unchanged. Exact V archives and selected generated Smali are retained; binary APK/JAR/ELF/DEX/kernel/firmware/image artifacts are identified by hashes. Pre-run image/kernel/EFI/QEMU hashes were recorded before runtime injection; staged runtime hashes identify the injected module. Raw application outcome is recorded separately after the run completes.'
	}, prettify: true) + '\n')!
	println('MAPS243-INPUTS PASS framework=' + framework_sources.len.str() + ' native=83 staged=7 pre-run=7')
}

fn result(out string) ! {
	assert os.exists(out + '/inputs.json'), 'Capture staged inputs before retaining results'
	run := base + 'attempt243/'
	copy_file(run + 'results.json', out + '/results.json')!
	copy_file(run + 'companion-packages.json', out + '/companion-packages.json')!
	app := run + 'google-maps/'
	serial := os.read_bytes(app + 'serial.log')!
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
	for name in ['attempt243-harness.log', 'run243.log', 'interact243.log', 'attempt243-timeline.log',
		'pan243.log', 'map-wait243.log', 'wait-map243.log'] {
		if os.exists(base + name) { copy_file(base + name, out + '/run/' + name)! }
	}
	if os.exists(app + 'network.pcap') {
		os.write_file(out + '/network-pcap-sha256.txt', digest(app + 'network.pcap')! + '\n')!
	}
	println('MAPS243-RESULT retained raw results, serial, screenshots and logs; outcome requires separate observations')
}

fn main() {
	assert os.args.len == 2 && os.args[1] in ['inputs', 'result', 'manifest'], 'usage: retain.v inputs|result|manifest'
	out := os.dir(@FILE)
	if os.args[1] == 'inputs' { inputs(out)! }
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
