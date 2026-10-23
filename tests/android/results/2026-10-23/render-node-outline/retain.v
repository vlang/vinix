import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	out := os.dir(@FILE)
	b := 'build/android-maps/'
	task := b + 'outline228/'
	mut inputs := map[string]string{}
	for variant in ['baseline', 'fixed'] {
		run := task + 'run-' + variant + '/'
		for pair in ['results.json|results.json', 'bootstrap-fixture/serial.log.gz|serial.log.gz',
			'bootstrap-fixture/application.png|application.png',
			'staged-runtime-sha256.json|staged-runtime-sha256.json'] {
			parts := pair.split('|')
			os.cp(run + parts[0], out + '/' + variant + '-' + parts[1])!
		}
		os.cp(task + variant + '.json', out + '/' + variant + '-configuration.json')!
		os.cp(task + variant + '-harness.log', out + '/' + variant + '-harness.log')!
		staged := json2.decode[map[string]string](os.read_file(run + 'staged-runtime-sha256.json')!)!
		for path, digest in staged { inputs[variant + '/staged/' + path] = digest }
		for name in ['android/graphics/RenderNode', 'android/graphics/Canvas', 'android/atl/GskCanvas'] {
			os.write_file_array(out + '/' + variant + '-' + os.base(name) + '.smali.gz',
				gzip.compress(os.read_bytes(task + 'verify-' + variant + '-smali/' + name + '.smali')!)!)!
		}
	}
	for name in ['RenderNodeOutlineProbe', 'StartupProbe'] {
		os.write_file_array(out + '/' + name + '.smali.gz', gzip.compress(os.read_bytes(task + 'verify-apk-smali/org/vinix/bootstrap/' + name + '.smali')!)!)!
	}
	for source, name in {
		b + 'framework228-outline/framework-manifest.json': 'framework-manifest.json'
		b + 'framework228-outline/exact-sources.json.gz':   'framework-sources.json.gz'
		b + 'framework228-source-snapshot.log':             'framework-source-check.log'
		b + 'outline228-finalize.log':                      'fixture-build.log'
		b + 'build-framework228-outline.v':                 'build-framework.v'
		b + 'prepare-framework228.v':                       'prepare-framework.v'
		b + 'finalize-outline228.v':                        'finalize-fixture.v'
		b + 'prepare-outline228.v':                         'prepare-fixture.v'
		task + 'prepare-proof.v':                           'prepare-proof.v'
		task + 'proof-prepare.log':                         'proof-prepare.log'
		task + 'staged-hashes.v':                           'staged-hashes.v'
		task + 'use-final-native.v':                        'use-final-native.v'
		task + 'prepare-retry.v':                           'prepare-retry.v'
		b + 'native228-sources.json':                       'native228-sources-sha256.json'
		b + 'native229-sources.json':                       'native229-sources-sha256.json'
		b + 'build-native228.v':                            'build-native228.v'
		b + 'rebuild-native228.v':                          'rebuild-native228.v'
		b + 'build-native229.v':                            'build-native229.v'
		b + 'native229-identity.txt':                       'native-identity.txt'
	} {
		os.cp(source, out + '/' + name)!
	}
	for source, name in {
		b + 'framework228-build.log': 'framework-build.log.gz'
		b + 'native229-build.log':    'native-build.log.gz'
	} {
		os.write_file_array(out + '/' + name, gzip.compress(os.read_bytes(source)!)!)!
	}
	mut fixture := map[string]string{}
	mut fixture_hashes := map[string]string{}
	for file in os.walk_ext(task + 'source/startupfixture', '.v') {
		name := os.base(file)
		fixture[name] = os.read_file(file)!
		fixture_hashes[name] = hash(file)!
	}
	os.write_file_array(out + '/fixture-sources.json.gz', gzip.compress(json2.encode(fixture).bytes())!)!
	os.write_file(out + '/fixture-sources-sha256.json', json2.encode(fixture_hashes, prettify: true) + '\n')!
	for version in ['228', '229'] {
		manifest := json2.decode[map[string]string](os.read_file(b + 'native' + version + '-sources.json')!)!
		mut native := map[string]string{}
		for name, digest in manifest {
			path := b + 'native' + version + '/atlframework/' + name
			assert hash(path)! == digest, path
			native[name] = os.read_file(path)!
		}
		os.write_file_array(out + '/native' + version + '-sources.json.gz', gzip.compress(json2.encode(native).bytes())!)!
	}
	for path in ['framework227-canvas-z/api-impl.jar', 'framework228-outline/api-impl.jar',
		'libnative225.so', 'libnative228.so', 'libnative229.so', 'outline228-apk/bootstrap.apk',
		'suite159', 'launcher200'] {
		inputs[b + path] = hash(b + path)!
	}
	inputs['inherited/native225-source-receipt'] = hash(out + '/../maps-ws/attempt225-input-identities.json')!
	mut artifacts := map[string]string{}
	for path in os.walk_ext(out, '') {
		name := path.all_after(out + '/')
		if name !in ['receipt.json', 'validation.log', 'retain', 'validate'] {
			artifacts[name] = hash(out + '/' + name)!
		}
	}
	os.write_file(out + '/receipt.json', json2.encode(Receipt{
		artifacts: artifacts
		inputs:    inputs
		scope:     'Identical signed APK: framework227/native225 reproduces rectangular-only RenderNode exception; framework228/native229 checks 5600 exact pixels, outline/path copies, transforms, alpha, four path fill rules, recorded path replay and 70 nested immutable clipping intersections. Native229 is frozen native228 plus f64 crossing arithmetic; native228 was run by Maps but not this fixed pair. Exact framework, fixture and native228/229 V source archives and actual framework/APK DEX disassembly are retained. Other staged runtime identities are compared. Raw harness may classify passing fixture startup_failed because inherited Maps-only Future diagnostics print and clear fixture-irrelevant NoSuchFieldError/nge exceptions; assertion markers plus READY establish completion. Native225 source identities inherit the Maps225 receipt. No Maps functional success or GPU clipping is claimed; mutable boot image is not source proof.'
	}, prettify: true) + '\n')!
	println('RENDER-NODE-OUTLINE-RETAIN PASS ${artifacts.len} artifacts;${fixture.len} frozen fixture sources;actual DEX and staged runtime identities')
}
