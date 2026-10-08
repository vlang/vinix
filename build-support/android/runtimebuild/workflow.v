module runtimebuild

import androidhost as ah

fn (e Engine) tools(kind string) !ah.Value {
	name, filename := match kind {
		'art_tools' { 'vinix_art_runtime', 'art-runtime.py' }
		'musl_tools' { 'vinix_android_musl', 'musl-runtime.py' }
		else { 'vinix_android_runtime', 'compile-v-runtime.py' }
	}
	return callback('load_module', {
		'name': ah.Value(name)
		'path': object(e.support_path(filename)!)
	})!
}

fn (e Engine) main(args ah.Value) !ah.Value {
	mut build_dir := attribute(args, 'build_dir', true)!
	if is_none(build_dir)! {
		build_dir = e.root_path('build-aarch64-android/aarch64')!
		setattr(args, 'build_dir', build_dir)!
	}
	build_dir = method('acquire', method('acquire', build_dir, 'expanduser', [], {})!, 'resolve', [], {})!
	setattr(args, 'build_dir', build_dir)!
	for name in ['art_runtime', 'bionic_runtime', 'atl_runtime'] {
		mut value := attribute(args, name, true)!
		if !bool_object(value)! { value = join(build_dir, name.replace('_', '-'))! }
		value = method('acquire', method('acquire', value, 'expanduser', [], {})!, 'resolve', [], {})!
		setattr(args, name, value)!
	}
	downloads := join(build_dir, 'downloads')!
	method('invoke', downloads, 'mkdir', [], {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
	})!
	lock_path := callback('borrow_global', {
		'name': ah.Value('LOCK')
	})!
	mut package_lock := null()
	if bool_object(attribute(args, 'update_lock', true)!)! {
		mirror := method('acquire', attribute(args, 'mirror', true)!, 'rstrip', [ordinary(ah.Value('/'))], {})!
		package_lock = api('make_lock', [object(downloads), object(mirror)], {}, true)!
		write_json(lock_path, package_lock)!
	} else {
		source := method('acquire', lock_path, 'read_text', [], {})!
		package_lock = call('acquire', 'json', 'loads', [object(source)], {})!
	}
	if !eq_value(get(package_lock, 'architecture')!, e.c('ARCHITECTURE'))! {
		return fail('package lock architecture does not match requested runtime')
	}
	api('stage', [object(args), object(package_lock), object(downloads)], {}, false)!
	return ah.Value(0)
}
