// SPDX-License-Identifier: GPL-2.0-only
module hotplughost

import androidhost as ah

fn put(state string, name string, value string) ! {
	target := resolve('operator.setitem') or {
		release([value])!
		return err
	}
	result := invoke_owned(target, [o(state), v(ah.Value(name))!, o(value)], {}, [value])!
	release([result])!
}

fn path(parent string, name string) !string {
	result := call('operator.truediv', o(parent), v(ah.Value(name))!) or {
		release([parent])!
		return err
	}
	release([parent])!
	return result
}

fn state_path(state string, parent string, name string) !string {
	return path(get(state, parent)!, name)!
}

fn method_target(state string, name string, method_ string) !string {
	receiver := get(state, name)!
	target := member(receiver, method_) or {
		release([receiver])!
		return err
	}
	release([receiver])!
	return target
}

fn state_method(state string, name string, method_ string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return invoke(method_target(state, name, method_)!, args, kwargs)!
}

fn global_text(name string) !string {
	target := global('str')!
	value := global(name) or {
		release([target])!
		return err
	}
	return invoke_owned(target, [o(value)], {}, [value])!
}

fn state_text(state string, name string) !string {
	target := global('str')!
	value := get(state, name) or {
		release([target])!
		return err
	}
	return invoke_owned(target, [o(value)], {}, [value])!
}

fn argument_text(state string, name string) !string {
	target := global('str')!
	value := argument(state, name) or {
		release([target])!
		return err
	}
	return invoke_owned(target, [o(value)], {}, [value])!
}

fn global_path_text(parent string, name string) !string {
	target := global('str')!
	base := global(parent) or {
		release([target])!
		return err
	}
	value := path(base, name) or {
		release([target])!
		return err
	}
	return invoke_owned(target, [o(value)], {}, [value])!
}

fn state_path_text(state string, parent string, name string) !string {
	target := global('str')!
	value := state_path(state, parent, name) or {
		release([target])!
		return err
	}
	return invoke_owned(target, [o(value)], {}, [value])!
}

fn list_owned(ids []string) !string {
	return invoke_owned(resolve('_list_literal')!, ids.map(o(it)), {}, ids.reverse())!
}

fn dict_owned(keys []string, values []string) !string {
	mut pairs := []string{}
	for i, key in keys {
		pairs << invoke_owned(resolve('_tuple')!, [v(ah.Value(key))!, o(values[i])], {}, [values[i]])!
	}
	return invoke_owned(resolve('_dictionary')!, pairs.map(o(it)), {}, pairs.reverse())!
}

fn add_owned(left string, right string) !string {
	result := call('operator.add', o(left), o(right)) or {
		release([left, right])!
		return err
	}
	release([left, right])!
	return result
}

fn append_owned(state string, value string) ! {
	target := method_target(state, 'objects', 'append') or {
		release([value])!
		return err
	}
	release([invoke_owned(target, [o(value)], {}, [value])!])!
}

fn module_target(state string, name string) !string {
	helper := get(state, 'helper')!
	result := get(helper, name) or {
		release([helper])!
		return err
	}
	release([helper])!
	return result
}

fn hash_bytes(factory string, data string) !string {
	hash := invoke_owned(factory, [o(data)], {}, [data])!
	return temporary_method(hash, 'hexdigest', [], {})!
}

fn hash_path(factory string, path_id string) !string {
	data := temporary_method(path_id, 'read_bytes', [], {}) or {
		release([factory])!
		return err
	}
	return hash_bytes(factory, data)!
}

fn named_hash(state string, name string) !string {
	factory := global('hashlib.sha256')!
	value := get(state, name) or {
		release([factory])!
		return err
	}
	return hash_path(factory, value)!
}

fn file_hash(state string, parent string, name string) !string {
	factory := global('hashlib.sha256')!
	value := state_path(state, parent, name) or {
		release([factory])!
		return err
	}
	return hash_path(factory, value)!
}

fn build(state string) !string {
	release([state_method(state, 'work', 'mkdir', [], {
		'parents':  v(ah.Value(true))!
		'exist_ok': v(ah.Value(false))!
	})!])!
	runner := global('runpy.run_path')!
	script := global_path_text('ROOT', 'tests/kernel-gaps/compile-v-fixture.py') or {
		release([runner])!
		return err
	}
	put(state, 'helper', invoke_owned(runner, [o(script)], {}, [script])!)!
	put(state, 'sources', dict_owned(['hotplugproduction'], [path(global('ROOT')!, 'kernel/apple/typec/hotplug.v')!])!)!
	put(state, 'objects', list_owned([])!)!
	put(state, 'hashes', call('_dictionary')!)!
	sources := get(state, 'sources')!
	items := temporary_method(sources, 'items', [], {})!
	iterator := call('_ITER', o(items)) or {
		release([items])!
		return err
	}
	release([items])!
	for {
		row := callback('next', {
			'owner': ah.Value(iterator)
		})!.object()
		if ah.field(row, 'done') as bool { break }
		members := callback('unpack_pair', {
			'owner': ah.field(row, 'value')
		}) or {
			release([iterator])!
			return err
		}
		pair := ah.field(row, 'value').text()
		release([pair])!
		values := members.items().map(it.text())
		put(state, 'module', values[0])!
		put(state, 'source', values[1])!
		base := get(state, 'work')!
		name := get(state, 'module')!
		staged := call('operator.truediv', o(base), o(name)) or {
			release([base, name, iterator])!
			return err
		}
		release([base, name])!
		put(state, 'staged', staged)!
		release([state_method(state, 'staged', 'mkdir', [], {})!])!
		put(state, 'text', state_method(state, 'source', 'read_text', [], {})!)!
		factory := global('hashlib.sha256')!
		encoded := state_method(state, 'text', 'encode', [], {}) or {
			release([factory, iterator])!
			return err
		}
		hash := hash_bytes(factory, encoded) or {
			release([iterator])!
			return err
		}
		converter := global('str') or {
			release([hash, iterator])!
			return err
		}
		relative_target := method_target(state, 'source', 'relative_to') or {
			release([converter, hash, iterator])!
			return err
		}
		root := global('ROOT') or {
			release([relative_target, converter, hash, iterator])!
			return err
		}
		relative := invoke_owned(relative_target, [o(root)], {}, [root]) or {
			release([converter, hash, iterator])!
			return err
		}
		key := invoke_owned(converter, [o(relative)], {}, [relative]) or {
			release([hash, iterator])!
			return err
		}
		hashes := get(state, 'hashes')!
		result := call('operator.setitem', o(hashes), o(key), o(hash)) or {
			release([hashes, key, hash, iterator])!
			return err
		}
		release([hashes, key, hash, result])!
		sub := global('re.sub')!
		concat_left := literal(ah.Value('module '))!
		name_ := get(state, 'module')!
		replacement := add_owned(concat_left, name_) or {
			release([sub, iterator])!
			return err
		}
		text_ := get(state, 'text')!
		multiline := global('re.M') or {
			release([text_, replacement, sub, iterator])!
			return err
		}
		replaced := invoke_owned(sub, [v(ah.Value(r'^module \w+'))!, o(replacement), o(text_)], {
			'count': v(ah.Value(1))!
			'flags': o(multiline)
		}, [multiline, text_, replacement]) or {
			release([iterator])!
			return err
		}
		put(state, 'text', replaced)!
		destination := state_path(state, 'staged', 'core.v')!
		writer := member(destination, 'write_text') or {
			release([destination, iterator])!
			return err
		}
		release([destination])!
		contents := get(state, 'text')!
		release([invoke_owned(writer, [o(contents)], {}, [contents])!])!
		appender := method_target(state, 'objects', 'append')!
		compiler := module_target(state, 'compile_module') or {
			release([appender, iterator])!
			return err
		}
		staged_ := get(state, 'staged')!
		work := get(state, 'work')!
		modname := get(state, 'module')!
		suffix := literal(ah.Value('.o'))!
		filename := add_owned(modname, suffix) or {
			release([work, staged_, compiler, appender, iterator])!
			return err
		}
		output := call('operator.truediv', o(work), o(filename)) or {
			release([work, filename, staged_, compiler, appender, iterator])!
			return err
		}
		release([work, filename])!
		arch := get(state, 'arch')!
		flags := get(state, 'flags')!
		include := global_path_text('ROOT', 'kernel/c') or {
			release([flags, arch, output, staged_, compiler, appender, iterator])!
			return err
		}
		extra := list_owned([literal(ah.Value('-ffreestanding'))!,
			literal(ah.Value('-fno-strict-aliasing'))!, literal(ah.Value('-DVINIX_V_RUNTIME'))!,
			literal(ah.Value('-I'))!, include])!
		compiler_flags := add_owned(flags, extra) or {
			release([arch, output, staged_, compiler, appender, iterator])!
			return err
		}
		object := invoke_owned(compiler, [o(staged_), o(output), o(arch), o(compiler_flags)], {}, [
			compiler_flags,
			arch,
			output,
			staged_,
		]) or {
			release([appender, iterator])!
			return err
		}
		release([invoke_owned(appender, [o(object)], {}, [object])!])!
	}
	release([iterator])!
	copier := global('shutil.copyfile')!
	header := path(global('ROOT')!, 'kernel/c/apple_display_hotplug.h') or {
		release([copier])!
		return err
	}
	destination := state_path(state, 'work', 'apple_display_hotplug.h') or {
		release([header, copier])!
		return err
	}
	release([invoke_owned(copier, [o(header), o(destination)], {}, [destination, header])!])!
	flags_ := get(state, 'flags')!
	work_text := state_text(state, 'work')!
	here_text := global_text('HERE')!
	includes := list_owned([literal(ah.Value('-I'))!, work_text, literal(ah.Value('-I'))!, here_text])!
	first := add_owned(flags_, includes)!
	guest := get(state, 'guest')!
	native := truth(guest) or {
		release([guest, first])!
		return err
	}
	release([guest])!
	define := list_owned(if native {
		[literal(ah.Value('-Dmain=hotplug_native_main'))!]
	} else {
		[]string{}
	})!
	put(state, 'fixture_flags', add_owned(first, define)!)!
	put(state, 'fixture', state_path(state, 'work', 'fixture.o')!)!
	original := get(state, 'original')!
	reference := truth(original) or {
		release([original])!
		return err
	}
	release([original])!
	if reference {
		dest := state_path(state, 'work', 'fixture.c')!
		writer := member(dest, 'write_bytes') or {
			release([dest])!
			return err
		}
		release([dest])!
		bytes := state_method(state, 'original', 'read_bytes', [], {}) or {
			release([writer])!
			return err
		}
		release([invoke_owned(writer, [o(bytes)], {}, [bytes])!])!
		flags_target := global('_compile_flags')!
		flags_id := get(state, 'fixture_flags')!
		put(state, 'compile_flags', invoke_owned(flags_target, [o(flags_id)], {}, [flags_id])!)!
		run := global('subprocess.run')!
		base_flags := get(state, 'compile_flags')!
		input := state_path_text(state, 'work', 'fixture.c')!
		output := state_text(state, 'fixture')!
		tail := list_owned([literal(ah.Value('-c'))!, input, literal(ah.Value('-o'))!, output])!
		args := add_owned(base_flags, tail)!
		release([invoke_owned(run, [o(args)], {
			'check': v(ah.Value(true))!
		}, [args])!])!
	} else {
		compiler := module_target(state, 'compile_module')!
		source := path(global('HERE')!, 'hotplugfixture')!
		output := get(state, 'fixture')!
		arch := get(state, 'arch')!
		flags := get(state, 'fixture_flags')!
		release([invoke_owned(compiler, [o(source), o(output), o(arch), o(flags)], {}, [flags,
			arch, output, source])!])!
	}
	append_owned(state, get(state, 'fixture')!)!
	capture := global('subprocess.check_output')!
	environ := global('os.environ')!
	nm := temporary_method(environ, 'get', [v(ah.Value('NM'))!, v(ah.Value('nm'))!], {}) or {
		release([capture])!
		return err
	}
	args_head := list_owned([nm, literal(ah.Value('-u'))!])!
	converter := global('_object_paths')!
	objects := get(state, 'objects')!
	names := invoke_owned(converter, [o(objects)], {}, [objects]) or {
		release([args_head, capture])!
		return err
	}
	argv := add_owned(args_head, names) or {
		release([capture])!
		return err
	}
	put(state, 'imports', invoke_owned(capture, [o(argv)], {
		'text': v(ah.Value(true))!
	}, [argv])!)!
	assertion := global('_no_allocators')!
	imports := get(state, 'imports')!
	release([invoke_owned(assertion, [o(imports)], {}, [imports])!])!
	guest_id := get(state, 'guest')!
	guest_build := truth(guest_id) or {
		release([guest_id])!
		return err
	}
	release([guest_id])!
	if guest_build {
		put(state, 'entry', state_path(state, 'work', 'entry')!)!
		release([state_method(state, 'entry', 'mkdir', [], {})!])!
		entry_header := state_path(state, 'entry', 'entry-native-abi.h')!
		writer := member(entry_header, 'write_text') or {
			release([entry_header])!
			return err
		}
		release([entry_header])!
		release([invoke(writer, [v(ah.Value('#include <stdio.h>\n#include <unistd.h>\nint hotplug_native_main(void);\n'))!], {})!])!
		source := state_path(state, 'entry', 'core.v')!
		writer_ := member(source, 'write_text') or {
			release([source])!
			return err
		}
		release([source])!
		release([invoke(writer_, [v(ah.Value(entry_fixture()))!], {})!])!
		appender := method_target(state, 'objects', 'append')!
		compiler := module_target(state, 'compile_module')!
		entry := get(state, 'entry')!
		output := state_path(state, 'work', 'entry.o')!
		arch := get(state, 'arch')!
		flags := get(state, 'flags')!
		object := invoke_owned(compiler, [o(entry), o(output), o(arch), o(flags)], {}, [
			flags,
			arch,
			output,
			entry,
		]) or {
			release([appender])!
			return err
		}
		release([invoke_owned(appender, [o(object)], {}, [object])!])!
		appender_ := method_target(state, 'objects', 'append')!
		serial := module_target(state, 'compile_serial')!
		output_ := state_path(state, 'work', 'serial.o')!
		arch_ := get(state, 'arch')!
		serial_flags := get(state, 'flags')!
		object_ := invoke_owned(serial, [o(output_), o(arch_), o(serial_flags)], {}, [
			serial_flags,
			arch_,
			output_,
		]) or {
			release([appender_])!
			return err
		}
		release([invoke_owned(appender_, [o(object_)], {}, [object_])!])!
	}
	put(state, 'executable', state_path(state, 'work', 'test')!)!
	runner_ := global('subprocess.run')!
	flags_left := get(state, 'flags')!
	guest_ := get(state, 'guest')!
	static_link := truth(guest_) or {
		release([guest_, flags_left, runner_])!
		return err
	}
	release([guest_])!
	statics := list_owned(if static_link { [literal(ah.Value('-static'))!] } else { []string{} })!
	initial := add_owned(flags_left, statics)!
	mapper := global('_object_paths')!
	objects_ := get(state, 'objects')!
	paths := invoke_owned(mapper, [o(objects_)], {}, [objects_]) or {
		release([initial, runner_])!
		return err
	}
	linked := add_owned(initial, paths) or {
		release([runner_])!
		return err
	}
	out := state_text(state, 'executable')!
	tail := list_owned([literal(ah.Value('-o'))!, out])!
	link_args := add_owned(linked, tail) or {
		release([runner_])!
		return err
	}
	release([invoke_owned(runner_, [o(link_args)], {
		'check': v(ah.Value(true))!
	}, [link_args])!])!
	mut values := []string{}
	defer { retire_parts(values) or {} }
	values << get(state, 'arch')!
	original_ := get(state, 'original')!
	has_original := truth(original_) or {
		release([original_])!
		return err
	}
	release([original_])!
	if has_original {
		values << state_text(state, 'original')!
	} else {
		values << literal(none_())!
	}
	values << get(state, 'guest')!
	values << get(state, 'flags')!
	values << get(state, 'hashes')!
	values << file_hash(state, 'work', 'apple_display_hotplug.h')!
	values << file_hash(state, 'work', 'fixture.c')!
	values << named_hash(state, 'executable')!
	values << state_method(state, 'imports', 'splitlines', [], {})!
	put(state, 'manifest', dict_owned(['arch', 'original', 'guest', 'compiler_flags',
		'production_sources', 'native_header_sha256', 'fixture_source_sha256', 'executable_sha256',
		'imports'], values)!)!
	dest_ := state_path(state, 'work', 'inputs.json')!
	writer_final := member(dest_, 'write_text') or {
		release([dest_])!
		return err
	}
	release([dest_])!
	encoder := global('json.dumps')!
	manifest := get(state, 'manifest')!
	encoded := invoke_owned(encoder, [o(manifest)], {
		'indent': v(ah.Value(2))!
	}, [manifest]) or {
		release([writer_final])!
		return err
	}
	newline := literal(ah.Value('\n'))!
	payload := add_owned(encoded, newline) or {
		release([writer_final])!
		return err
	}
	release([invoke_owned(writer_final, [o(payload)], {}, [payload])!])!
	return get(state, 'executable')!
}

fn entry_fixture() string {
	return "module entry\n#include <entry-native-abi.h>\nfn C.hotplug_native_main() i32\nfn C.fflush(voidptr) i32\nfn C.pause() i32\n@[export: 'main']\npub fn run() i32 {\n    result := C.hotplug_native_main()\n    unsafe { C.fflush(nil) }\n    if result == 0 { for { C.pause() } }\n    return result\n}\n"
}

fn argument(state string, name string) !string {
	args := get(state, 'args')!
	value := member(args, name) or {
		release([args])!
		return err
	}
	release([args])!
	return value
}

fn check_argument(state string, name string) !bool { return tested(argument(state, name)!)! }

fn check_equal(id string, value string) !bool {
	result := call('operator.eq', o(id), v(ah.Value(value))!) or {
		release([id])!
		return err
	}
	release([id])!
	return tested(result)!
}

fn machine_field(name string) !string { return temporary_attribute(call('os.uname')!, name)! }

fn temporary_attribute(id string, name string) !string {
	value := member(id, name) or {
		release([id])!
		return err
	}
	release([id])!
	return value
}

fn env_get(name string, fallback ah.Value) !string {
	environ := global('os.environ')!
	target := member(environ, 'get') or {
		release([environ])!
		return err
	}
	release([environ])!
	return invoke(target, [v(ah.Value(name))!, fallback], {})!
}

fn main_build(state string, kind string, reference bool, guest bool) !string {
	target := global('build')!
	parent := get(state, 'work') or {
		release([target])!
		return err
	}
	location := path(parent, kind) or {
		release([target])!
		return err
	}
	arch := get(state, 'arch') or {
		release([location, target])!
		return err
	}
	flags := get(state, 'flags') or {
		release([arch, location, target])!
		return err
	}
	if reference {
		original := argument(state, 'original_reference') or {
			release([flags, arch, location, target])!
			return err
		}
		if guest {
			return invoke_owned(target, [o(location), o(arch), o(flags), o(original),
				v(ah.Value(true))!], {}, [original, flags, arch, location])!
		}
		return invoke_owned(target, [o(location), o(arch), o(flags), o(original)], {}, [
			original,
			flags,
			arch,
			location,
		])!
	}
	return invoke_owned(target, [o(location), o(arch), o(flags)], {}, [flags, arch, location])!
}

fn main_run(state string, name string, result string) ! {
	target := global('subprocess.run')!
	converter := global('str') or {
		release([target])!
		return err
	}
	binary := get(state, name) or {
		release([converter, target])!
		return err
	}
	text := invoke_owned(converter, [o(binary)], {}, [binary]) or {
		release([target])!
		return err
	}
	args := list_owned([text]) or {
		release([target])!
		return err
	}
	environment := get(state, 'environment') or {
		release([args, target])!
		return err
	}
	value := invoke_owned(target, [o(args)], {
		'capture_output': v(ah.Value(true))!
		'env':            o(environment)
		'timeout':        v(ah.Value(180))!
	}, [environment, args])!
	put(state, result, value)!
}

fn main_policy(state string) !string {
	if check_argument(state, 'state_dir')! {
		put(state, 'work', temporary_method(argument(state, 'state_dir')!, 'resolve', [], {})!)!
	} else {
		factory := global('Path')!
		directory := get(state, 'directory') or {
			release([factory])!
			return err
		}
		put(state, 'work', invoke_owned(factory, [o(directory)], {}, [directory])!)!
	}
	if check_argument(state, 'state_dir')! {
		release([state_method(state, 'work', 'mkdir', [], {
			'parents':  v(ah.Value(true))!
			'exist_ok': v(ah.Value(false))!
		})!])!
	}
	selected := argument(state, 'arch')!
	if truth(selected)! {
		put(state, 'arch', selected)!
	} else {
		release([selected])!
		host := argument(state, 'host_arch')!
		put(state, 'arch', literal(ah.Value(if check_equal(host, 'arm64')! {
			'aarch64'
		} else {
			'x86_64'
		}))!)!
	}
	if check_equal(argument(state, 'arch')!, 'aarch64')! {
		factory := global('Path')!
		environ := global('os.environ')!
		getter := member(environ, 'get') or {
			release([environ, factory])!
			return err
		}
		release([environ])!
		fallback := path(global('ROOT')!, 'build-aarch64-userland/sysroot') or {
			release([getter, factory])!
			return err
		}
		selected_sdk := invoke_owned(getter, [v(ah.Value('VINIX_AARCH64_SYSROOT'))!, o(fallback)], {}, [fallback]) or {
			release([factory])!
			return err
		}
		put(state, 'sdk', invoke_owned(factory, [o(selected_sdk)], {}, [selected_sdk])!)!
		mut values := []string{}
		values << env_get('CC_AARCH64', v(ah.Value('clang'))!)!
		values << literal(ah.Value('--target=aarch64-linux-musl'))!
		values << concatenate([literal(ah.Value('--sysroot='))!,
			formatted_temporary(get(state, 'sdk')!)!])!
		values << literal(ah.Value('-fuse-ld=lld'))!
		values << concatenate([literal(ah.Value('-L'))!, formatted_temporary(get(state, 'sdk')!)!,
			literal(ah.Value('/lib'))!])!
		put(state, 'cc', list_owned(values)!)!
	} else if check_argument(state, 'arch')! {
		put(state, 'cc', list_owned([env_get('CC_AMD64', v(ah.Value('x86_64-linux-musl-gcc'))!)!])!)!
	} else {
		put(state, 'cc', list_owned([env_get('CC', v(ah.Value('clang'))!)!])!)!
		if check_equal(machine_field('sysname')!, 'Darwin')! {
			arch := get(state, 'arch')!
			selected_arch := literal(ah.Value(if check_equal(arch, 'aarch64')! {
				'arm64'
			} else {
				'x86_64'
			}))!
			left := get(state, 'cc')!
			extra := list_owned([literal(ah.Value('-arch'))!, selected_arch])!
			value := call('operator.iadd', o(left), o(extra)) or {
				release([left, extra])!
				return err
			}
			release([left, extra])!
			put(state, 'cc', value)!
		}
	}
	left := get(state, 'cc')!
	extra := list_owned(['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin'].map(literal(ah.Value(it))!))!
	put(state, 'flags', add_owned(left, extra)!)!
	if !check_argument(state, 'arch')! {
		put(state, 'sanitizer', env_get('VINIX_HOTPLUG_SANITIZERS', v(ah.Value('address,undefined'))!)!)!
		sanitizer := get(state, 'sanitizer')!
		unequal := call('operator.ne', o(sanitizer), v(ah.Value('none'))!) or {
			release([sanitizer])!
			return err
		}
		release([sanitizer])!
		if tested(unequal)! {
			flags := get(state, 'flags')!
			argument_ := add_owned(literal(ah.Value('-fsanitize='))!, get(state, 'sanitizer')!) or {
				release([flags])!
				return err
			}
			additions := list_owned([argument_, literal(ah.Value('-fno-omit-frame-pointer'))!])!
			value := call('operator.iadd', o(flags), o(additions)) or {
				release([flags, additions])!
				return err
			}
			release([flags, additions])!
			put(state, 'flags', value)!
		}
	}
	if check_argument(state, 'arch')! {
		put(state, 'binary', main_build(state, 'native', true, true)!)!
		if check_argument(state, 'build_only')! {
			target := global('print')!
			binary := get(state, 'binary')!
			release([invoke_owned(target, [o(binary)], {}, [binary])!])!
			return literal(ah.Value(0))!
		}
		target := global('subprocess.call')!
		mut values := []string{}
		defer { retire_parts(values) or {} }
		values << literal(ah.Value('python3'))!
		values << global_path_text('ROOT', 'tests/kernel-gaps/run.py')!
		values << literal(ah.Value('--arch'))!
		values << get(state, 'arch')!
		for name in ['--no-network', '--kernel-dir'] { values << literal(ah.Value(name))! }
		values << argument_text(state, 'kernel_dir')!
		values << literal(ah.Value('--prebuilt-init'))!
		values << state_text(state, 'binary')!
		values << literal(ah.Value('--state-dir'))!
		values << argument_text(state, 'guest_state_dir')!
		for name in ['--expect', 'apple display hotplug state tests passed', '--fail', 'check failed',
			'--timeout', '300'] {
			values << literal(ah.Value(name))!
		}
		argv := list_owned(values)!
		return invoke_owned(target, [o(argv)], {}, [argv])!
	}
	put(state, 'translated', main_build(state, 'v', false, false)!)!
	put(state, 'leaks', literal(ah.Value(if check_equal(machine_field('sysname')!, 'Darwin')! {
		'0'
	} else {
		'1'
	}))!)!
	environment_factory := global('_environment')!
	leaks := get(state, 'leaks')!
	put(state, 'environment', invoke_owned(environment_factory, [o(leaks)], {}, [leaks])!)!
	main_run(state, 'translated', 'v')!
	validator := global('_validate')!
	value_v := get(state, 'v')!
	release([invoke_owned(validator, [o(value_v)], {}, [value_v])!])!
	if check_argument(state, 'original_reference')! {
		put(state, 'original', main_build(state, 'c', true, false)!)!
		main_run(state, 'original', 'c')!
		compare := global('_same_result')!
		value_c := get(state, 'c')!
		value_v_ := get(state, 'v')!
		release([invoke_owned(compare, [o(value_c), o(value_v_)], {}, [value_v_, value_c])!])!
	}
	for name in ['stdout', 'stderr'] {
		location := state_path(state, 'work', name)!
		writer := member(location, 'write_bytes') or {
			release([location])!
			return err
		}
		release([location])!
		process := get(state, 'v')!
		contents := temporary_attribute(process, name) or {
			release([writer])!
			return err
		}
		release([invoke_owned(writer, [o(contents)], {}, [contents])!])!
	}
	printer := global('print')!
	process_ := get(state, 'v')!
	stdout := temporary_attribute(process_, 'stdout') or {
		release([printer])!
		return err
	}
	decoded := temporary_method(stdout, 'decode', [], {}) or {
		release([printer])!
		return err
	}
	release([invoke_owned(printer, [o(decoded)], {
		'end': v(ah.Value(''))!
	}, [decoded])!])!
	return literal(ah.Value(0))!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	ids := ah.field(row, 'arguments').items().map(it.text())
	current_builtins = ids[1]
	start := checkpoint()!
	operation := ah.field(row, 'operation').text()
	result := execute(operation, ids[2]) or {
		cause := err
		pin := resolve('operator.setitem')!
		release([invoke(pin, [o(ids[0]), v(ah.Value('_state'))!, o(ids[2])], {})!])!
		clean_since(start, [])!
		return cause
	}
	clean_since(start, [result])!
	return ah.Value(result)
}

fn execute(operation string, state string) !string {
	if operation == 'build' { return build(state)! }
	if operation == 'main' { return main_policy(state)! }
	return error('unknown display-hotplug operation')
}
