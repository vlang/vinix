module benchtest

import androidhost as ah
import runtimebuild as rb

const entry_source = "module guestentry
#include <entry-abi.h>
fn C.alloc_bench_native_main(i32, &&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    unsafe {
        args := [&char(c'alloc-bench'), &char(c'--iterations'), &char(c'65'), &char(c'--samples'), &char(c'6'), &char(c'--label'), &char(c'native'), &char(nil)]!
        result := C.alloc_bench_native_main(7, &args[0])
        C.fflush(nil)
        if result == 0 { for { C.pause() } }
        return result
    }
}
"

fn module_generator(loader ah.Value, parent ah.Value, child string) !ah.Value {
    formatter := target('str') or { release([loader, parent])!; return err }
    path := join(parent, child) or { release([parent, formatter, loader])!; return err }
    release([parent])!
    text := temporary_call(formatter, [o(path)], {}, {}, [path]) or { release([loader])!; return err }
    loaded := temporary_call(loader, [o(text)], {}, {}, [text])!
    gen := get(loaded, 'generate') or { release([loaded])!; return err }
    release([loaded])!
    return gen
}

fn make_argv(left ah.Value, right ah.Value, tail []ah.Value) !ah.Value {
	value := op('add', left, o(right))!
	suffix := list(tail)!
	out := op('add', value, o(suffix)) or { release([value, suffix])!; return err }
	release([value, suffix])!
	return out
}
fn run_argv(target_ ah.Value, args ah.Value) ! {
	discard(temporary_call(target_, [o(args)], {'check': ah.Value(true)}, {}, [args])!)!
}
fn filtered_flags(flags ah.Value) !ah.Value {
    filtered := list([])!
    prefixes := rb.api('_filter_prefixes', [], {}, true)!
    iterator := item_iter(flags) or { release([prefixes])!; return err }
    mut current := rb.null()
    for {
        value := rb.next(iterator)!
        if value == rb.null() { break }
        old := current
        current = value
        release([old])!
        starts := method(current, 'startswith', [o(prefixes)])!
        keep := truth_value(starts)!
        if !keep { append(filtered, current)! }
    }
    release([current, iterator, prefixes])!
    return filtered
}
fn model_defines(aliases ah.Value) !ah.Value {
    values := list([])!
    items := invoke(receiver(aliases, 'items')!, [], {})!
    iterator := item_iter(items) or { release([items])!; return err }
    release([items])!
    mut key := rb.null()
    mut value := rb.null()
    for {
        row := rb.next(iterator)!
        if row == rb.null() { break }
        pair := rb.callback('unpack_pair', {'id': row}) or { release([row])!; return err }
        members := pair.items()
        release([row])!
        old_key := key
        key = members[0]
        release([old_key])!
        old_value := value
        value = members[1]
        release([old_value])!
        entry := rb.api('_define', [o(key), o(value)], {}, true)!
        append(values, entry)!
        release([entry])!
    }
    release([key, value, iterator])!
    return values
}
fn flags_strings(flags ah.Value) !ah.Value {
    strings := list([])!
    iterator := item_iter(flags)!
    mut current := rb.null()
    for {
        value := rb.next(iterator)!
        if value == rb.null() { break }
        old := current
        current = value
        release([old])!
        text := str(current)!
        append(strings, text)!
        release([text])!
    }
    release([current, iterator])!
    return strings
}
fn build(work ah.Value, flags ah.Value, arch ah.Value, original ah.Value, model ah.Value, guest ah.Value, debug bool) !ah.Value {
	mut f := Frame{}
	source := f.named('source', join(work, 'bench.c')!)!
	mut manifest := rb.null()
	if truth(original)! {
		writer := attr(source, 'write_bytes')!
		content := method(original, 'read_bytes', []) or { release([writer])!; return err }
		discard(temporary_call(writer, [o(content)], {}, {}, [content])!)!
		manifest = f.named('manifest', dict(['source_sha256', 'original'], [temp(digest(source)!), temp(str(original)!)])!)!
	} else {
		loader := factory('runpy', 'run_path')!
		gen := module_generator(loader, target('HERE')!, 'compile-v-bench.py')!
		manifest = f.named('manifest', invoke(gen, [o(source), o(arch)], {})!)!
	}
	compile_flags := f.named('compile_flags', filtered_flags(flags)!)!
	obj := f.named('obj', join(work, 'bench.o')!)!
	defines := f.named('defines', if truth(model)! { model_defines(target('ALIASES')!)! } else { list([])! })!
	if truth(guest)! { append_text(defines, '-Dmain=alloc_bench_native_main')! }
	run_ := factory('subprocess', 'run')!
	argv := make_argv(compile_flags, defines, [v('-I'), temp(str(work)!), v('-c'), temp(str(source)!), v('-o'), temp(str(obj)!)])!
	run_argv(run_, argv)!
	capture := factory('subprocess', 'check_output')!
	getenv := environ_get()!
	nm := invoke(getenv, [v('NM'), v('nm')], {})!
	nm_args := list([o(nm), v('-u'), temp(str(obj)!)])!
	imports := f.named('imports', temporary_call(capture, [o(nm_args)], {'text': ah.Value(true)}, {}, [nm, nm_args])!)!
	if debug {
		match_ := invoke(factory('re', 'search')!, [v('\\b_?(?:calloc|realloc|memdup|v_malloc|new_array\\w*)\\b'), o(imports)], {})!
		if truth_value(match_)! { fail_message(imports)! }
		search := factory('re', 'search')!
		text := method(source, 'read_text', []) or { release([search])!; return err }
		match2 := temporary_call(search, [v('\\b(?:memdup|new_array\\w*|v_malloc)\\s*\\('), o(text)], {}, {}, [text])!
		if truth_value(match2)! { fail_plain()! }
	}
	objects := f.named('objects', list([o(obj)])!)!
	if truth(model)! {
		provider := f.named('provider', join(work, 'provider.c')!)!
		loader := factory('runpy', 'run_path')!
		gen := module_generator(loader, target('ROOT')!, 'build-support/compile-v-module.py')!
		fixture := join(target('HERE')!, 'benchfixture')!
		discard(temporary_call(gen, [o(fixture), o(provider), o(arch)], {}, {}, [fixture])!)!
		provider_obj := f.named('provider_obj', join(work, 'provider.o')!)!
		run2 := factory('subprocess', 'run')!
		include := path_str(target('HERE')!, 'benchfixture')!
		suffix := list([v('-Wno-unused-function'), v('-Wno-unused-parameter'), v('-I'), o(include), v('-c'), temp(str(provider)!), v('-o'), temp(str(provider_obj)!)])!
		argv2 := op('add', compile_flags, o(suffix))!
		release([suffix, include])!
		run_argv(run2, argv2)!
		append(objects, provider_obj)!
	}
	if truth(guest)! {
		entry := f.named('entry', join(work, 'guestentry')!)!
		discard(method(entry, 'mkdir', [])!)!
		statement(receiver(join(entry, 'entry-abi.h')!, 'write_text')!, [v('#include <stdio.h>\n#include <unistd.h>\nint alloc_bench_native_main(int, char **);\n')], {})!
		statement(receiver(join(entry, 'core.v')!, 'write_text')!, [v(entry_source)], {})!
		generated := f.named('generated', join(work, 'entry.c')!)!
		loader := factory('runpy', 'run_path')!
		gen := module_generator(loader, target('ROOT')!, 'build-support/compile-v-module.py')!
		discard(invoke(gen, [o(entry), o(generated), o(arch)], {})!)!
		entry_obj := f.named('entry_obj', join(work, 'entry.o')!)!
		run3 := factory('subprocess', 'run')!
		suffix := list([v('-Wno-unused-function'), v('-Wno-unused-parameter'), v('-I'), temp(str(entry)!), v('-c'), temp(str(generated)!), v('-o'), temp(str(entry_obj)!)])!
		argv3 := op('add', compile_flags, o(suffix))!
		release([suffix])!
		run_argv(run3, argv3)!
		append(objects, entry_obj)!
		serial := f.named('serial', join(work, 'serial.o')!)!
		load_serial := factory('runpy', 'run_path')!
		serial_path := path_str(target('ROOT')!, 'tests/kernel-gaps/compile-v-fixture.py')!
		serial_module := temporary_call(load_serial, [o(serial_path)], {}, {}, [serial_path])!
		compile_serial := get(serial_module, 'compile_serial')!
		release([serial_module])!
		serial_arch := if truth_value(op('eq', arch, v('arm64'))!)! { 'aarch64' } else { 'x86_64' }
		discard(invoke(compile_serial, [o(serial), v(serial_arch), o(flags)], {})!)!
		append(objects, serial)!
	}
	exe := f.named('exe', join(work, 'test')!)!
	run4 := factory('subprocess', 'run')!
	static_flags := if truth(guest)! { list([v('-static')])! } else { list([])! }
	prefix := op('add', flags, o(static_flags))!
	object_strings := flags_strings(objects)!
	argv4 := make_argv(prefix, object_strings, [v('-o'), temp(str(exe)!)])!
	release([static_flags, prefix, object_strings])!
	run_argv(run4, argv4)!
	update := attr(manifest, 'update')!
	sha := digest(exe)!
	lines := method(imports, 'splitlines', [])!
	discard(temporary_call(update, [], {}, {'compiler_flags': flags, 'arch': arch, 'model': model, 'guest': guest, 'executable_sha256': sha, 'imports': lines}, [sha, lines])!)!
	write_json(join(work, 'inputs.json')!, manifest)!
	return exe
}
