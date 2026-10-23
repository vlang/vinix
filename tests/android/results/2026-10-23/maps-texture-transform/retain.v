import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const framework = 'framework236-texture/'

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
	assert manifest['output_sha256']!.str() == '9f5ddfbb7a17cff8265c0c1a4dba752b59a9ac12e88801e15c26b17654f0c584'
	previous_framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-accessibility/framework/exact-sources.json.gz')!)!.bytestr())!
	assert framework_sources.len == 106 && previous_framework.len == 105
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
	for name in ['tests/native-android-tools/androidtools/framework_startup.v',
		'tests/native-android-tools/androidtools/framework_texture_transforms.v'] {
		assert name in delta, name
	}
	for name in previous_framework.keys() {
		assert name in framework_sources, name
	}
	os.mkdir_all(out + '/framework')!
	os.write_file(out + '/framework/source-delta-from235.json', json2.encode(delta, prettify: true) + '\n')!
	native_manifest := json2.decode[map[string]string](os.read_file(base + 'native235-sources.json')!)!
	native_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + 'native235-exact-sources.json.gz')!)!.bytestr())!
	assert native_sources.len == 83 && native_sources.len == native_manifest.len
	for name, source in native_sources {
		assert sha256.sum(source.bytes()).hex() == native_manifest[name], name
	}
	assert digest(base + 'libnative235.so')! == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	pre := json2.decode[map[string]string](os.read_file(base + 'identity236-inputs/pre-run-sha256.json')!)!
	assert pre.len == 7
	assert digest(base + 'identity236-inputs/vinix')! == pre['boot/vinix']
	assert digest(base + 'identity236-inputs/limine.conf')! == pre['boot/limine.conf']
	mut files := map[string]string{}
	for path in ['libnative235.so', 'GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk',
		framework + 'api-impl.jar', framework + 'classes.dex', 'suite159', 'launcher200'] {
		files[path] = digest(base + path)!
	}
	mut staged := map[string]string{}
	for path in ['opt/android-test/native-guest',
		'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session'] {
		staged[path] = digest(base + 'attempt236/module/' + path)!
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == files['libnative235.so']
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == files[framework + 'api-impl.jar']
	mut headers := map[string]string{}
	for name in ['android-native.c', 'androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		headers[name] = digest(base + 'native235/' + name)!
	}
	for source, target in {
		framework + 'framework-manifest.json':     'framework/manifest.json'
		framework + 'exact-sources.json.gz':       'framework/exact-sources.json.gz'
		'native235-sources.json':                  'native/sources-sha256.json'
		'native235-exact-sources.json.gz':         'native/exact-sources.json.gz'
		'native235-identity.txt':                  'native/identity.txt'
		'native235-production-source-sha256.json': 'native/production-source-sha256.json'
		'native235-reviewed-overlays.json':        'native/reviewed-overlays.json'
		'native235-source-delta.json':             'native/source-delta-from233.json'
		'identity236-inputs/pre-run-sha256.json':  'pre-run/sha256.json'
		'identity236-inputs/scope.txt':            'pre-run/scope.txt'
		'identity236-inputs/limine.conf':          'pre-run/limine.conf'
		'attempt236.json':                         'configuration.json'
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
		'android/view/View.smali', 'android/view/TextureView.smali'] {
		generated[path] = os.read_file(base + framework + 'smali/' + path)!
	}
	os.write_file_array(out + '/framework/generated-smali.json.gz', gzip.compress(json2.encode(generated).bytes())!)!
	for name in ['build-native235.v', 'prepare-framework236.v', 'build-framework236-texture.v',
		'snapshot-framework236.v', 'prepare-texture236.v', 'prepare236.v', 'run236.v', 'interact236.v',
		'manual236.v', 'identity236.v', 'trace-input.v', 'prepare-maps236-receipt.v'] {
		copy_file(base + name, out + '/helpers/' + name)!
	}
	for name in ['native235-build.log', 'framework236-build.log'] {
		os.write_file_array(out + '/' + name + '.gz', gzip.compress(os.read_bytes(base + name)!)!)!
	}
	for name in ['results.json', 'run.log'] {
		copy_file(base + 'attempt236-prelaunch-failure/' + name, out + '/prelaunch-failure/' + name)!
	}
	os.write_file(out + '/prelaunch-failure/scope.txt',
		'The initial Maps236 attempt failed while creating module.tar: the harness reported tar Write error after host disk exhaustion. It did not boot the guest or execute the APK. The completed run in this receipt is a retry with identical framework/native/APK inputs; this staging failure is retained separately from the application outcome.\n')!
	for path in os.walk_ext(base + 'interpolator-resources234', '') {
		copy_file(path, out + '/maps-resources/' + os.base(path))!
	}
	assert os.read_file(out + '/maps-resources/apk-sha256.txt')!.trim_space() == files['GoogleMaps.apk']
	prior := '../maps-accessibility/receipt.json'
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
		scope:                           'Maps236 uses the independently tested native235 path precision implementation and framework236 TextureView content transform state. Exact V archives and selected generated Smali are retained; binary APK/JAR/ELF/DEX/kernel/firmware/image artifacts are identified by hashes. Pre-run image/kernel/EFI/QEMU hashes were recorded before runtime injection; staged runtime hashes identify the injected module. Raw application outcome is recorded separately after the run completes.'
	}, prettify: true) + '\n')!
	println('MAPS236-INPUTS PASS framework=' + framework_sources.len.str() + ' native=83 staged=7 pre-run=7')
}

fn result(out string) ! {
	assert os.exists(out + '/inputs.json'), 'Capture staged inputs before retaining results'
	run := base + 'attempt236/'
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
	for name in ['attempt236-harness.log', 'run236.log', 'interact236.log', 'attempt236-timeline.log',
		'pan236.log', 'map-wait236.log'] {
		if os.exists(base + name) { copy_file(base + name, out + '/run/' + name)! }
	}
	if os.exists(app + 'network.pcap') {
		os.write_file(out + '/network-pcap-sha256.txt', digest(app + 'network.pcap')! + '\n')!
	}
	println('MAPS236-RESULT retained raw results, serial, screenshots and logs; outcome requires separate observations')
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
