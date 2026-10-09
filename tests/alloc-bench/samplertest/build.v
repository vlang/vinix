// SPDX-License-Identifier: GPL-2.0-or-later
module samplertest

import androidhost as ah
import runtimebuild as rb

const original_entry = "module originalentry\n#include <entry-abi.h>\nfn C.sampler_original_main() i32\nfn C.fflush(voidptr) i32\nfn C.pause() i32\n@[export: 'main']\npub fn run() i32 { result := C.sampler_original_main(); C.fflush(unsafe { nil }); if result == 0 { for { C.pause() } }; return result }\n"

fn filtered_flags(flags ah.Value) !ah.Value {
	filtered := list([])!
	prefixes := rb.api('_filter_prefixes', [], {}, true)!
	iterator := rb.iter_object(flags)!
	mut current := rb.null()
	for {
		value := rb.next(iterator)!
		if value == rb.null() { break }
		old := current
		current = value
		release([old])!
		if !truth_value(method(current, 'startswith', [o(prefixes)])!)! { append(filtered, current)! }
	}
	release([current, iterator, prefixes])!
	return filtered
}

fn object_strings(objects ah.Value) !ah.Value {
	values := list([])!
	iterator := rb.iter_object(objects)!
	mut current := rb.null()
	for {
		value := rb.next(iterator)!
		if value == rb.null() { break }
		old := current
		current = value
		release([old])!
		statement(attr(values, 'append')!, [temp(str(current)!)], {})!
	}
	release([current, iterator])!
	return values
}

fn module_generator(provider string, child string) !ah.Value {
	loader := factory('runpy', 'run_path')!
	formatter := target('str') or { release([loader])!; return err }
	parent := target(provider) or { release([loader, formatter])!; return err }
	path := join(parent, child) or { release([loader, formatter, parent])!; return err }
	release([parent])!
	text := temporary_call(formatter, [o(path)], {}, {}, [path]) or { release([loader])!; return err }
	loaded := temporary_call(loader, [o(text)], {}, {}, [text])!
	generator := get(loaded, 'generate') or { release([loaded])!; return err }
	release([loaded])!
	return generator
}

fn compile_command(runner ah.Value, flags ah.Value, tail []ah.Value) ! {
	suffix := list(tail) or { release([runner])!; return err }
	argv := op('add', flags, o(suffix)) or { release([runner, suffix])!; return err }
	release([suffix])!
	discard(temporary_call(runner, [o(argv)], {'check': ah.Value(true)}, {}, [argv])!)!
}

fn build(work ah.Value, arch ah.Value, flags ah.Value, original ah.Value, guest ah.Value, debug bool) !ah.Value {
	mut f := Frame{}
	compile_flags := f.named('compile_flags', filtered_flags(flags)!)!
	generate := f.named('generate', module_generator('HERE', 'compile-v-sampler.py')!)!
	v_arch := f.named('v_arch', literal(if truth_value(op('eq', arch, v('aarch64'))!)! { 'arm64' } else { 'amd64' })!)!
	sampler := f.named('sampler', join(work, 'sampler.c')!)!
	discard(raw_invoke(generate, [o(sampler)], {'host_clock': ah.Value(true)}, {'arch': v_arch})!)!
	obj := f.named('obj', join(work, 'sampler.o')!)!
	compile_command(factory('subprocess', 'run')!, compile_flags, [v('-DVINIX_KALLOC_HOST_TEST'), v('-I'), temp(path_str(target('ROOT')!, 'kernel/c')!), v('-c'), temp(str(sampler)!), v('-o'), temp(str(obj)!)])!
	nm := f.named('nm', invoke(environ_get()!, [v('NM'), v('nm')], {})!)!
	imports := f.named('imports', temporary_call(factory('subprocess', 'check_output')!, [temp(list([o(nm), v('-u'), temp(str(obj)!)] )!)], {'text': ah.Value(true)}, {}, [])!)!
	if debug {
		if truth_value(invoke(factory('re', 'search')!, [v('\\b_?(?:malloc|calloc|realloc|free|memdup|new_array\\w*)\\b'), o(imports)], {})!)! { fail_message(imports)! }
		search := factory('re', 'search')!
		contents := method(sampler, 'read_text', []) or { release([search])!; return err }
		if truth_value(temporary_call(search, [v('\\b(?:memdup|new_array\\w*)\\s*\\('), o(contents)], {}, {}, [contents])!)! { fail_plain()! }
	}
	objects := f.named('objects', list([o(obj)])!)!
	if truth(original)! {
		fixture := f.named('fixture', join(work, 'original-fixture.o')!)!
		runner := factory('subprocess', 'run')!
		defines := list(if truth(guest)! { [v('-Dmain=sampler_original_main')] } else { []ah.Value{} })!
		prefix := op('add', compile_flags, o(defines))!
		release([defines])!
		compile_command(runner, prefix, [v('-c'), temp(str(original)!), v('-o'), temp(str(fixture)!)])!
		release([prefix])!
		append(objects, fixture)!
		if truth(guest)! {
			wrapper := f.named('wrapper', join(work, 'originalentry')!)!
			discard(method(wrapper, 'mkdir', [])!)!
			statement(receiver(join(wrapper, 'entry-abi.h')!, 'write_text')!, [v('#include <stdio.h>\n#include <unistd.h>\nint sampler_original_main(void);\n')], {})!
			statement(receiver(join(wrapper, 'core.v')!, 'write_text')!, [v(original_entry)], {})!
			generate_module := f.named('generate_module', module_generator('ROOT', 'build-support/compile-v-module.py')!)!
			generated := f.named('generated', join(work, 'originalentry.c')!)!
			discard(raw_invoke(generate_module, [o(wrapper), o(generated), o(v_arch)], {}, {})!)!
			wrapper_obj := f.named('wrapper_obj', join(work, 'originalentry.o')!)!
			compile_command(factory('subprocess', 'run')!, compile_flags, [v('-Wno-unused-function'), v('-Wno-unused-parameter'), v('-I'), temp(str(wrapper)!), v('-c'), temp(str(generated)!), v('-o'), temp(str(wrapper_obj)!)])!
			append(objects, wrapper_obj)!
		}
	} else {
		generated := f.named('generated', join(work, 'fixture.c')!)!
		generate_module := f.named('generate_module', module_generator('ROOT', 'build-support/compile-v-module.py')!)!
		fixture_source := join(target('HERE')!, 'samplerfixture')!
		features := tuple(if truth(guest)! { [v('sampler_guest')] } else { []ah.Value{} })!
		discard(raw_invoke(generate_module, [temp(fixture_source), o(generated), o(v_arch), temp(features)], {}, {})!)!
		fixture := f.named('fixture', join(work, 'fixture.o')!)!
		compile_command(factory('subprocess', 'run')!, compile_flags, [v('-Wno-unused-function'), v('-Wno-unused-parameter'), v('-I'), temp(path_str(target('HERE')!, 'samplerfixture')!), v('-c'), temp(str(generated)!), v('-o'), temp(str(fixture)!)])!
		fixture_imports := f.named('fixture_imports', temporary_call(factory('subprocess', 'check_output')!, [temp(list([o(nm), v('-u'), temp(str(fixture)!)] )!)], {'text': ah.Value(true)}, {}, [])!)!
		if debug {
			if truth_value(invoke(factory('re', 'search')!, [v('\\b_?(?:malloc|realloc|memdup|new_array\\w*|v_malloc)\\b'), o(fixture_imports)], {})!)! { fail_message(fixture_imports)! }
			for pattern in ['\\bcalloc\\(', '\\bfree\\('] {
				finder := factory('re', 'findall')!
				contents := method(generated, 'read_text', []) or { release([finder])!; return err }
				matches := temporary_call(finder, [v(pattern), o(contents)], {}, {}, [contents])!
				length := temporary_call(target('len')!, [o(matches)], {}, {}, [matches])!
				if !truth_value(temporary_call(factory('_operator', 'eq')!, [o(length), n(1)], {}, {}, [length])!)! { fail_plain()! }
			}
		}
		append(objects, fixture)!
		asm_object := f.named('asm', join(work, 'varargs.o')!)!
		runner := factory('subprocess', 'run')!
		assembly_formatter := target('str')!
		root := join(target('HERE')!, 'samplerfixture')!
		formatter := target('_varargs')!
		filename := temporary_call(formatter, [o(v_arch)], {}, {}, [])!
		assembly := temporary_call(factory('_operator', 'truediv')!, [o(root), o(filename)], {}, {}, [root, filename])!
		assembly_text := temporary_call(assembly_formatter, [o(assembly)], {}, {}, [assembly])!
		compile_command(runner, compile_flags, [v('-c'), temp(assembly_text), v('-o'), temp(str(asm_object)!)])!
		append(objects, asm_object)!
	}
	if truth(guest)! {
		serial := f.named('serial', join(work, 'serial.o')!)!
		loader := factory('runpy', 'run_path')!
		path := path_str(target('ROOT')!, 'tests/kernel-gaps/compile-v-fixture.py')!
		module_ := temporary_call(loader, [o(path)], {}, {}, [path])!
		compiler := get(module_, 'compile_serial')!
		release([module_])!
		discard(invoke(compiler, [o(serial), o(arch), o(flags)], {})!)!
		append(objects, serial)!
	}
	executable := f.named('executable', join(work, 'test')!)!
	linker := factory('subprocess', 'run')!
	static_flags := list(if truth(guest)! { [v('-static')] } else { []ah.Value{} })!
	prefix := op('add', flags, o(static_flags))!
	strings := object_strings(objects)!
	linked := op('add', prefix, o(strings))!
	release([static_flags, prefix, strings])!
	compile_command(linker, linked, [v('-o'), temp(str(executable)!)])!
	release([linked])!
	metadata_writer := receiver(join(work, 'inputs.json')!, 'write_text')!
	metadata_encoder := factory('json', 'dumps') or { release([metadata_writer])!; return err }
	original_name := if truth(original)! { str(original)! } else { call('_none', [])! }
	original_digest := if truth(original)! { digest(original)! } else { call('_none', [])! }
	metadata := dict(['arch', 'native_model', 'compiler_flags', 'original', 'original_sha256', 'sampler_generated_sha256', 'executable_sha256', 'sampler_imports'], [o(arch), o(guest), o(flags), temp(original_name), temp(original_digest), temp(digest(sampler)!), temp(digest(executable)!), temp(method(imports, 'splitlines', [])!)])!
	write_json(metadata_writer, metadata_encoder, metadata)!
	release([metadata])!
	return executable
}
