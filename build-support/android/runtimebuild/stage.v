module runtimebuild

import androidhost as ah
import crypto.sha256
import encoding.hex

struct Overlays {
	art             ah.Value
	musl            ah.Value
	art_root        ah.Value
	bionic_root     ah.Value
	atl_root        ah.Value
	art_manifest    ah.Value
	bionic_manifest ah.Value
	atl_manifest    ah.Value
}

struct Cached {
	art     ah.Value
	bionic  ah.Value
	atl     ah.Value
	matches bool
}

fn manifests(args ah.Value) !Overlays {
	art := api('art_tools', [], {}, true)!
	musl := api('musl_tools', [], {}, true)!
	art_root := attribute(args, 'art_runtime', true)!
	if !test(art_root, 'is_dir')! {
		return fail('missing native 16 KiB ART overlay: ' + str(art_root)! + '; run build-support/android/build-art.sh on ARM64 Alpine Linux first')
	}
	art_manifest := method('acquire', art, 'read_manifest', [object(art_root)], {})!
	if !bool_object(get_default(art_manifest, 'bootclasspath')!)! {
		return fail("ART's Java boot libraries must be desugared first; run build-support/android/art-bootclasspath.py --build-dir " + str(join(attribute(args, 'build_dir', true)!, 'java-build')!)! + ' --art-runtime ' + str(art_root)!)
	}
	bionic_root := attribute(args, 'bionic_runtime', true)!
	if !test(bionic_root, 'is_dir')! {
		return fail('missing native 16 KiB APK library loader: ' + str(bionic_root)! + '; run build-support/android/build-bionic.sh on ARM64 Alpine Linux first')
	}
	bionic_manifest := method('acquire', art, 'read_bionic_manifest', [object(bionic_root)], {})!
	atl_root := attribute(args, 'atl_runtime', true)!
	if !test(atl_root, 'is_dir')! {
		return fail('missing coherent native ATL overlay: ' + str(atl_root)! + '; run build-support/android/build-atl.sh on ARM64 Alpine Linux first')
	}
	atl_manifest := method('acquire', art, 'read_atl_manifest', [object(atl_root)], {})!
	method('invoke', art, 'validate_atl_art_pair', [object(art_manifest), object(atl_manifest)], {})!
	return Overlays{art, musl, art_root, bionic_root, atl_root, art_manifest, bionic_manifest, atl_manifest}
}

fn read_bytes(path ah.Value) ![]u8 {
	return hex.decode(callback('invoke', {
		'id':        path
		'name':      ah.Value('read_bytes')
		'arguments': ah.Value([]ah.Value{})
		'bytes':     ah.Value(true)
	})!.text())!
}

fn (e Engine) sources() ![]ah.Value {
	mut paths := [api('Path', [ordinary(ah.Value(e.source))], {}, true)!]
	for name in ['run-android', 'art-runtime.py', 'art16k.patch', 'build-art.sh', 'art-bootclasspath.py',
		'bionic16k.patch', 'build-bionic.sh', 'build-atl.sh', 'atl-dex.py', 'musl-runtime.py',
		'musl-mallinfo.patch', 'musl-statistics.h'] {
		paths << e.support_path(name)!
	}
	for name in ['build-support/musl/stage.py', 'build-support/musl/malloc-retain.patch',
		'build-support/musl/alpine-1.2.6/manifest.json', 'build-support/java-cacerts.py'] {
		paths << e.root_path(name)!
	}
	for name in ['_native.py', 'host-query.v'] { paths << e.support_path(name)! }
	// Keep the original ordered inputs, then append the complete maintained
	// controller source closure. Never hash build-specific executable bytes.
	for pattern in ['*.v', '*.h'] {
		sequence := method('acquire', e.support_path('androidhost')!, 'glob', [ordinary(ah.Value(pattern))], {})!
		iter := iter_object(call('acquire', 'builtins', 'sorted', [object(sequence)], {})!)!
		for {
			path := next(iter)!
			if path == null() { break }
			paths << path
		}
	}
	for name in ['_boot_native.py', 'runtime-query.v'] { paths << e.support_path(name)! }
	paths << e.root_path('build-support/native_host.py')!
	for module_name in ['runtimebuild', 'boothost', 'androidhost', 'fixturehost', 'hosttest'] {
		mut closure := []ah.Value{}
		for pattern in ['*.v', '*.h'] {
			files := method('acquire', e.support_path(module_name)!, 'glob', [ordinary(ah.Value(pattern))], {})!
			iter := iter_object(files)!
			for {
				path := next(iter)!
				if path == null() { break }
				if attribute(path, 'name', false)!.text().ends_with('_test.v') { continue }
				closure << path
			}
		}
		iter := iter_object(call('acquire', 'builtins', 'sorted', [object(make_sequence(closure.map(object(it)))!)], {})!)!
		for {
			path := next(iter)!
			if path == null() { break }
			paths << path
		}
	}
	return paths
}

fn (e Engine) cache_key(args ah.Value, package_lock ah.Value, overlay Overlays) !string {
	mut hash := sha256.new()
	hash.write(json_text(package_lock, {
		'sort_keys': ah.Value(true)
	})!.bytes())!
	hash.write(str(attribute(args, 'with_calculator', true)!)!.bytes())!
	for manifest in [overlay.art_manifest, overlay.bionic_manifest, overlay.atl_manifest] {
		hash.write(json_text(manifest, {
			'sort_keys': ah.Value(true)
		})!.bytes())!
	}
	tools := api('runtime_tools', [], {}, true)!
	hash.write(hex.decode(callback('invoke', {
		'id':        tools
		'name':      ah.Value('inputs')
		'arguments': ah.Value([]ah.Value{})
		'bytes':     ah.Value(true)
	})!.text())!)!
	for source in e.sources()! { hash.write(read_bytes(source)!)! }
	return hash.sum([]u8{}).hex()
}

fn (e Engine) cache_files(args ah.Value, cache ah.Value, key string, runtime ah.Value, staging ah.Value) !bool {
	if !test(cache, 'exists')! || read_strip(cache)! != key {
		return false
	}
	for name in e.c('REQUIRED').items() {
		if !test(join(runtime, name.text())!, 'is_file')! { return false }
	}
	if !test(join(staging, 'usr/bin/run-android')!, 'is_file')! { return false }
	if bool_object(attribute(args, 'with_calculator', true)!)! && !test(join(staging, 'usr/bin/run-android-calculator')!, 'is_file')! {
		return false
	}
	return true
}

fn (e Engine) cached_metadata(runtime ah.Value, package_lock ah.Value, overlay Overlays) !Cached {
	art := method('acquire', overlay.art, 'read_manifest', [object(runtime)], {})!
	bionic := method('acquire', overlay.art, 'read_bionic_manifest', [object(runtime)], {})!
	atl := method('acquire', overlay.art, 'read_atl_manifest', [object(runtime)], {})!
	musl := method('acquire', overlay.musl, 'read_manifest', [object(runtime)], {})!
	method('invoke', overlay.art, 'validate_atl_art_pair', [object(art), object(atl)], {})!
	contents := method('acquire', join(runtime, 'runtime-manifest.json')!, 'read_text', [], {})!
	cached := call('acquire', 'json', 'loads', [object(contents)], {})!
	dict_type := call('acquire', 'builtins', '__getattribute__', [ordinary(ah.Value('dict'))], {})!
	mut matches := truth(call('invoke', 'builtins', 'isinstance', [object(cached), object(dict_type)], {})!)
	if matches { matches = eq_value(get_default(cached, 'architecture')!, e.c('ARCHITECTURE'))! }
	if matches {
		matches = read_strip(join(runtime, 'architecture')!)! == e.c('ARCHITECTURE').text()
	}
	if matches { matches = eq_value(get_default(cached, 'execution')!, ah.Value('native'))! }
	if matches { matches = eq_value(get_default(cached, 'page_size')!, ah.Value(16384))! }
	if matches { matches = eq_value(get_default(cached, 'runtime_prefix')!, e.c('PREFIX'))! }
	if matches { matches = eq(get_default(cached, 'packages')!, get(package_lock, 'packages')!)! }
	if matches { matches = eq(get_default(cached, 'art')!, overlay.art_manifest)! }
	if matches { matches = eq(get_default(cached, 'bionic')!, overlay.bionic_manifest)! }
	if matches { matches = eq(get_default(cached, 'atl')!, overlay.atl_manifest)! }
	if matches { matches = eq(get_default(cached, 'musl')!, musl)! }
	return Cached{art, bionic, atl, matches}
}

fn run(command []string, environment ah.Value) ! {
	row := {
		'module':    ah.Value('subprocess')
		'name':      ah.Value('run')
		'arguments': ah.Value([ordinary(strings(command))])
		'options':   ah.Value({
			'check': ah.Value(true)
		})
	}
	mut arguments := row.clone()
	if environment != null() {
		arguments['keyword_objects'] = ah.Value({
			'env': environment
		})
	}
	callback('invoke', arguments)!
}

fn (e Engine) stage(args ah.Value, package_lock ah.Value, downloads ah.Value) !ah.Value {
	build_dir := attribute(args, 'build_dir', true)!
	staging := join(build_dir, 'staging')!
	runtime := join(staging, e.c('PREFIX').text().trim_left('/'))!
	overlay := manifests(args)!
	key := e.cache_key(args, package_lock, overlay)!
	cache := join(build_dir, '.staging-cache-key')!
	if e.cache_files(args, cache, key, runtime, staging)! {
		cached := e.cached_metadata(runtime, package_lock, overlay) or {
			if !error_is(err, ['RuntimeError', 'OSError', 'ValueError'])! { return err }
			nothing := callback('retain', {
				'value': ordinary(null())
			})!
			Cached{nothing, nothing, nothing, false}
		}
		matched := eq(cached.art, overlay.art_manifest)! && eq(cached.bionic, overlay.bionic_manifest)! && eq(cached.atl, overlay.atl_manifest)! && cached.matches
		if matched {
			print_flush('Reusing pinned native Android runtime in ' + str(staging)!)!
			return staging
		}
	}
	compiler := call('acquire', 'shutil', 'which', [ordinary(ah.Value('aarch64-linux-musl-gcc'))], {})!
	if is_none(compiler)! {
		return fail('aarch64-linux-musl-gcc is required to build the Android compatibility library')
	}
	unlink(cache, true)!
	if test(staging, 'exists')! { call('invoke', 'shutil', 'rmtree', [object(staging)], {})! }
	method('invoke', runtime, 'mkdir', [], {
		'parents': ah.Value(true)
	})!
	archives := pool_map('fetch_package', get(package_lock, 'packages')!, {
		'downloads':    object(downloads)
		'package_lock': object(package_lock)
	})!
	iter := iter_object(archives)!
	for {
		archive := next(iter)!
		if archive == null() { break }
		api('extract_apk', [object(archive), object(runtime)], {}, false)!
	}
	api('materialize_library_links', [object(runtime)], {}, false)!
	os_module := callback('borrow_global', {
		'name': ah.Value('os')
	})!
	env := call('acquire', 'builtins', 'dict', [object(attribute(os_module, 'environ', true)!)], {
		'VINIX_OPTIMIZED_MUSL': ah.Value('1')
		'VINIX_MUSL_RETAIN':    ah.Value('1')
	})!
	run(['python3', str(e.root_path('build-support/musl/stage.py')!)!, '--arch', 'aarch64', '--staging',
		str(runtime)!, '--build-dir', str(join(build_dir, 'musl-build')!)!, '--cc', str(compiler)!,
		'--extra-patch', str(e.support_path('musl-mallinfo.patch')!)!, '--max-page-size', '65536',
		'--require-export', '__vinix_malloc_stats'], env)!
	api('materialize_library_links', [object(runtime)], {}, false)!
	musl := method('acquire', overlay.musl, 'read_manifest', [object(runtime)], {})!
	method('invoke', overlay.art, 'apply', [object(overlay.art_root), object(runtime),
		object(overlay.art_manifest)], {})!
	write_json(join_object(runtime, attribute(overlay.art, 'MANIFEST', true)!)!, overlay.art_manifest)!
	method('invoke', overlay.art, 'apply_bionic', [object(overlay.bionic_root), object(runtime),
		object(overlay.bionic_manifest)], {})!
	write_json(join_object(runtime, attribute(overlay.art, 'BIONIC_MANIFEST', true)!)!, overlay.bionic_manifest)!
	method('invoke', overlay.art, 'apply_atl', [object(overlay.atl_root), object(runtime),
		object(overlay.atl_manifest)], {})!
	write_json(join_object(runtime, attribute(overlay.art, 'ATL_MANIFEST', true)!)!, overlay.atl_manifest)!
	api('relocate_configuration', [object(runtime)], {}, false)!
	run(['python3', str(e.support_path('compile-v-runtime.py')!)!,
		str(join(runtime, 'usr/lib/libvinix-android-compat.so')!)!, '--cc', str(compiler)!,
		'--generated-dir', str(join(build_dir, 'runtime-generated')!)!], null())!
	run(['python3', str(e.root_path('build-support/java-cacerts.py')!)!,
		str(join(runtime, 'usr/share/ca-certificates/mozilla')!)!,
		str(join(runtime, 'etc/ssl/certs/java/cacerts')!)!], null())!
	resources := join(runtime, 'usr/share/atl')!
	if test(resources, 'exists')! {
		call('invoke', 'shutil', 'copytree', [object(resources),
			object(join(staging, 'usr/share/atl')!)], {
			'symlinks': ah.Value(true)
		})!
	}
	commands := join(staging, 'usr/bin')!
	method('invoke', commands, 'mkdir', [], {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
	})!
	launcher := join(commands, 'run-android')!
	call('invoke', 'shutil', 'copy2', [object(e.support_path('run-android')!), object(launcher)], {})!
	method('invoke', launcher, 'chmod', [ordinary(ah.Value(0o755))], {})!
	manifest := call('acquire', 'builtins', 'dict', [object(package_lock)], {})!
	put(manifest, 'runtime_prefix', ordinary(e.c('PREFIX')))!
	put(manifest, 'execution', ordinary(ah.Value('native')))!
	put(manifest, 'page_size', ordinary(ah.Value(16384)))!
	put(manifest, 'art', object(overlay.art_manifest))!
	put(manifest, 'bionic', object(overlay.bionic_manifest))!
	put(manifest, 'atl', object(overlay.atl_manifest))!
	put(manifest, 'musl', object(musl))!
	put(manifest, 'upstream', ordinary(ah.Value('https://gitlab.com/android_translation_layer/android_translation_layer')))!
	if bool_object(attribute(args, 'with_calculator', true)!)! {
		apk := api('calculator_apk', [object(downloads)], {}, true)!
		samples := join(staging, 'usr/share/vinix/android')!
		method('invoke', samples, 'mkdir', [], {
			'parents':  ah.Value(true)
			'exist_ok': ah.Value(true)
		})!
		call('invoke', 'shutil', 'copy2', [object(apk),
			object(join_object(samples, attribute(apk, 'name', true)!)!)], {})!
		calculator := join(commands, 'run-android-calculator')!
		method('invoke', calculator, 'write_text', [ordinary(ah.Value('#!/bin/sh\nexec /usr/bin/run-android /usr/share/vinix/android/Arity-1.1.apk -l calculator/Calculator -w 480 -h 640 "\$@"\n'))], {})!
		method('invoke', calculator, 'chmod', [ordinary(ah.Value(0o755))], {})!
		put(manifest, 'calculator', object(callback('borrow_global', {
			'name': ah.Value('CALCULATOR')
		})!))!
	}
	write_json(join(runtime, 'runtime-manifest.json')!, manifest)!
	architecture := call('acquire', 'operator', 'add', [
		object(get(package_lock, 'architecture')!),
		ordinary(ah.Value('\n')),
	], {})!
	method('invoke', join(runtime, 'architecture')!, 'write_text', [object(architecture)], {})!
	for name in e.c('REQUIRED').items() {
		if !test(join(runtime, name.text())!, 'is_file')! {
			return fail('missing staged Android runtime file: ' + name.text())
		}
	}
	method('invoke', cache, 'write_text', [ordinary(ah.Value(key + '\n'))], {})!
	print_flush('Staged ' + length(get(package_lock, 'packages')!)!.str() + ' pinned packages in ' + str(staging)!)!
	return staging
}
