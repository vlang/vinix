module androidhost

import os

fn build_split_variants(row map[string]Value, base string, dex_path string, native string, elf []u8) ! {
	output := text(row, 'output')!
	split_manifest := text(row, 'split_manifest')!
	template := advanced_decode(probe_bytes(split_manifest)!)!.replace('\r\n', '\n').replace('\r', '\n')
	for name, xml in advanced_split_variants(template) {
		manifest := path_join(output, name + '.xml')
		os.write_file(manifest, xml) or { return file_error(manifest) }
		apk_path := path_join(output, name)
		advanced_command(row, [text(row, 'aapt2')!, 'link', '--manifest', manifest, '-I',
			text(row, 'framework_res')!, '-o', apk_path])!

		if name == 'config.arm64_v8a.apk' { advanced_append_configuration(apk_path, elf)! }
		if name == 'bad-hidden-dex.apk' { advanced_append_hidden(dex_path, apk_path)! }
	}
	missing := path_join(output, 'bad-missing-manifest.apk')
	advanced_missing_archive(missing)!
	if advanced_apk_names(base)!.any(it !in ['AndroidManifest.xml', 'resources.arsc', 'classes.dex']) {
		return ProbeExit{'unexpected base APK payload'}
	}
	if advanced_apk_names(path_join(output, 'config.arm64_v8a.apk'))!.any(it !in [
		'AndroidManifest.xml',
		'resources.arsc',
		'lib/arm64-v8a/libvinix_split_probe.so',
		'assets/vinix-split-marker.txt',
	]) {
		return ProbeExit{'unexpected configuration split payload'}
	}
	cases := path_join(output, 'test-cases.json')
	advanced_write(cases, Value(map[string]Value{
		'cases': advanced_split_cases()
	}))!
	mut inputs := map[string]Value{}
	for path in [text(row, 'source')!, text(row, 'manifest')!, split_manifest,
		text(row, 'native_source')!, text(row, 'framework_classes')!, text(row, 'framework_res')!,
		text(row, 'core_classes')!, text(row, 'r8')!] {
		inputs[path.all_after_last('/')] = Value(digest(path)!)
	}
	mut apk_names := os.ls(output) or { return file_error(output) }
	apk_names = apk_names.filter(it.ends_with('.apk'))
	apk_names.sort()
	mut outputs := map[string]Value{}
	for name in apk_names { outputs[name] = Value(digest(path_join(output, name))!) }
	receipt := Value(map[string]Value{
		'inputs':                  Value(inputs)
		'outputs':                 Value(outputs)
		'library_sha256':          Value(digest(native)!)
		'helper_sha256':           Value(digest(text(row, 'helper')!)!)
		'test_cases_sha256':       Value(digest(cases)!)
		'activity':                Value('org.vinix.tests.AndroidSplitApkProbe$BootstrapActivity')
		'expected_marker':         Value('ANDROID-SPLIT-PASS')
		'runtime_tested':          Value(false)
		'fixture_uses_public_api': Value(true)
		'signatures':              Value('Local unsigned test fixture only; genuine app archives are separately signature-verified.')
	})
	advanced_write(path_join(output, 'split-probe-build.json'), receipt)!
	println(base)
}

fn advanced_split_variants(template string) map[string]string {
	return {
		'config.arm64_v8a.apk': template
		'bad-package.apk':      template.replace('org.vinix.tests.split', 'org.vinix.tests.other')
		'bad-version.apk':      template.replace('7007', '7008')
		'bad-empty-name.apk':   template.replace(' split="config.arm64_v8a"', '')
		'bad-code.apk':         template.replace('android:hasCode="false"', 'android:hasCode="true"')
		'bad-dependent.apk':    template.replace('split="config.arm64_v8a"', 'split="config.arm64_v8a" configForSplit="feature"')
		'bad-components.apk':   template.replace('<application android:hasCode="false" android:extractNativeLibs="true" />', '<application android:hasCode="false"><activity android:name="org.vinix.tests.Other" /></application>')
		'duplicate-name.apk':   template
		'bad-hidden-dex.apk':   template
	}
}

fn advanced_split_cases() Value {
	return Value([
		Value(map[string]Value{
			'name':   Value('wrong-package')
			'splits': Value([Value('bad-package.apk')])
			'error':  Value('Split APK identity does not match the base')
		})
		Value(map[string]Value{
			'name':   Value('wrong-version')
			'splits': Value([Value('bad-version.apk')])
			'error':  Value('Split APK identity does not match the base')
		})
		Value(map[string]Value{
			'name':   Value('empty-name')
			'splits': Value([Value('bad-empty-name.apk')])
			'error':  Value('Split APK identity does not match the base')
		})
		Value(map[string]Value{
			'name':   Value('code')
			'splits': Value([Value('bad-code.apk')])
			'error':  Value('Split APK components or code are not supported')
		})
		Value(map[string]Value{
			'name':   Value('dependency')
			'splits': Value([Value('bad-dependent.apk')])
			'error':  Value('Feature and dependent split APKs are not supported')
		})
		Value(map[string]Value{
			'name':   Value('components')
			'splits': Value([Value('bad-components.apk')])
			'error':  Value('Split APK components or code are not supported')
		})
		Value(map[string]Value{
			'name':   Value('duplicate-name')
			'splits': Value([Value('config.arm64_v8a.apk'), Value('duplicate-name.apk')])
			'error':  Value('Split APK identity does not match the base')
		})
		Value(map[string]Value{
			'name':   Value('hidden-dex')
			'splits': Value([Value('bad-hidden-dex.apk')])
			'error':  Value('Split APK DEX code is not supported')
		})
		Value(map[string]Value{
			'name':   Value('missing-manifest')
			'splits': Value([Value('bad-missing-manifest.apk')])
			'error':  Value('APK archive has no AndroidManifest.xml')
		})
		Value(map[string]Value{
			'name':    Value('install')
			'splits':  Value([Value('config.arm64_v8a.apk')])
			'options': Value([Value('--install')])
			'error':   Value('installing split APKs is not supported')
		})
		Value(map[string]Value{
			'name':    Value('install-internal')
			'splits':  Value([Value('config.arm64_v8a.apk')])
			'options': Value([Value('--install-internal')])
			'error':   Value('installing split APKs is not supported')
		}),
	])
}

fn advanced_append_configuration(path string, elf []u8) ! {
	mut apk := open_probe_append(path)!
	defer { apk.stream.close() }
	apk.publish(ProbePayload{'lib/arm64-v8a/libvinix_split_probe.so', elf.clone(), 0o600})!
	apk.publish(ProbePayload{'assets/vinix-split-marker.txt', 'SPLIT-ASSET\n'.bytes(), 0o600})!
}

fn advanced_append_hidden(dex_path string, apk_path string) ! {
	dex := read_probe_zip(dex_path)!
	mut apk := open_probe_append(apk_path)!
	defer { apk.stream.close() }
	data := dex.read_name('classes.dex') or {
		if apk.new_archive { apk.publish(none)! }
		return err
	}
	apk.publish(ProbePayload{'classes.dex', data, 0o600})!
}

fn advanced_missing_archive(path string) ! {
	mut stream := os.create(path) or { return file_error(path) }
	defer { stream.close() }
	write_probe_bytes(mut stream, make_probe_zip([ProbePayload{'assets/only.txt', 'No manifest here\n'.bytes(), 0o600}])!)!
}
