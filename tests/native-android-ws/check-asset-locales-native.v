// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production locale adapter against recording C API/JNI boundaries.
// This checks ownership and dispatch, not ART or actual APK resource enumeration.
// The provider's internal new[]/strdup failure behavior is outside this probe.
module main

import crypto.sha256
import json2
import os

fn locale_hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn locale_function(source string, name string) !string {
	marker := 'fn ' + name + '('
	assert source.count(marker) == 1, 'unique production function required: ' + name
	start := source.index(marker) or { return error('missing function: ' + name) }
	open := start + (source[start..].index('{') or { return error('missing function body: ' + name) })
	mut depth := 0
	for index in open .. source.len {
		if source[index] == `{` { depth++ }
		if source[index] == `}` {
			depth--
			if depth == 0 { return source[start..index + 1] + '\n' }
		}
	}
	return error('unterminated function: ' + name)
}

fn locale_adapt(source string) string {
	return source.replace('C.AssetManager_getLocales(', 'probe_enumerate(')
		.replace('C.dlsym(', 'probe_symbol(').replace('C.free(', 'probe_free(')
}

fn locale_pins(paths []string) !map[string]string {
	mut pins := map[string]string{}
	for path in paths {
		assert os.real_path(path) == path && os.lstat(path)!.get_filetype() == .regular
		pins[path] = locale_hash(path)!
	}
	return pins
}

fn locale_json(path string, value json2.Any) ! {
	assert !os.exists(path), 'immutable receipt already exists: ' + path
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn locale_map(value map[string]string) !json2.Any { return json2.decode[json2.Any](json2.encode(value))! }
fn locale_args(value []string) !json2.Any { return json2.decode[json2.Any](json2.encode(value))! }

fn locale_record(root string, label string, args []string) !os.Result {
	result := os.exec(args)
	os.write_file(root + '/' + label + '.log', result.output)!
	locale_json(root + '/' + label + '.json', {
		'argv': locale_args(args)!, 'exit_code': json2.Any(result.exit_code)
	})!
	return result
}

fn main() {
	$if prod { panic('assertions required; compile without -prod') }
	assert os.args.len == 3, 'usage: check-asset-locales-native REPO FRESH_EXTERNAL_OUTPUT'
	repo, out := os.real_path(os.args[1]), os.abs_path(os.args[2])
	assert !out.starts_with(repo + '/') && !os.exists(out) && !os.is_link(out)
	assert os.real_path(os.dir(out)) == os.dir(out), 'canonical existing output parent required'
	source_path := repo + '/build-support/android/nativews/asset_locales.v'
	jni_path := repo + '/build-support/android/atlframework/jni.v'
	resources_path := repo + '/build-support/android/nativews/resources.v'
	binding_path := repo + '/build-support/android/nativews/bindings.txt'
	baseline := '/Users/alex/.local/state/vinix/android/current-native-build-2026-11-02-stable-display-r2/native/bindings.txt'
	header := os.dir(baseline) + '/androidfw_c_api.h'
	compiler := os.real_path(os.find_abs_path_of_executable(os.getenv_opt('VINIX_V_COMPILER') or { 'v' })!)
	cc, make := os.real_path(os.find_abs_path_of_executable('cc')!), os.real_path(os.find_abs_path_of_executable('make')!)
	paths := [source_path, jni_path, resources_path, binding_path, baseline, header,
		os.real_path(@FILE), os.real_path(os.executable()), compiler, cc, make]
	before := locale_pins(paths)!
	assert before[baseline] == '76f62e0ceefb04f147856b711cce651380841027ee3d3fd70e4bc9787b956d60'
	assert before[header] == 'e233a055133776838b8044ca43eb9e8dfac387a0580918786d60207276d37af4'
	binding := 'android/content/res/AssetManager|getLocales()[Ljava/lang/String;|return ws_asset_locales(e,this)\n'
	assert os.read_file(binding_path)! == os.read_file(baseline)! + binding, 'one exact appended locale binding required'
	assert os.read_file(header)!.contains('char **AssetManager_getLocales(struct AssetManager *asset_manager, bool exclude_system, bool merge_equivalent_languages);')
	source, jni, resources := os.read_file(source_path)!, os.read_file(jni_path)!, os.read_file(resources_path)!
	assert source.count('fn C.AssetManager_getLocales(voidptr, bool, bool) &&char') == 1
	assert source.count('type WsLocaleArrayDelete = fn (voidptr)') == 1
	query, release := locale_function(source, 'ws_asset_locales')!, locale_function(source, 'ws_locale_vector_delete')!
	mut program := 'module main\n' + locale_harness + '\ntype WsLocaleArrayDelete = fn (voidptr)\n'
	for name in ['slot', 'pending', 'cls'] { program += locale_function(jni, name)! }
	program += locale_function(resources, 'ws_string')! + locale_adapt(release + query)
	program += '\nfn locale_binding(e voidptr, this voidptr) voidptr { ' + binding.all_after_last('|').trim_space() + ' }\n'
	mut mutations := []string{}
	changes := [query.replace('ws_resources_enter(manager)', ''), query.replace('ws_resources_leave(manager)', ''),
		query, query, query.replace('manager, false, true)', 'manager, true, false)'),
		query.replace('for locales[count] != nil { count++ }', 'for locales[count] != nil { count++ }; count = 1')]
	for index, changed in changes {
		mut cleanup := release
		if index == 2 { cleanup = cleanup.replace('C.free(locales[index])', '') }
		if index == 3 { cleanup = cleanup.replace('release(voidptr(locales))', '') }
		assert changed != query || cleanup != release, 'negative control no longer applies'
		name := 'locale_mutant_' + index.str()
		mutated := (cleanup + changed).replace('ws_locale_vector_delete', name + '_delete').replace('ws_asset_locales', name)
		program += locale_adapt(mutated)
		mutations << name
	}
	program += '\nfn main() {\n assert locale_suite(locale_binding)\n'
	for name in mutations { program += ' assert !locale_suite(' + name + '), "escaped negative control ' + name + '"\n' }
	program += ' println("' + locale_pass + '")\n}\n'
	os.mkdir(out, mode: 0o700)!
	os.mkdir(out + '/inputs', mode: 0o700)!
	for path in [source_path, jni_path, resources_path, binding_path, baseline, header, os.real_path(@FILE)] {
		copy := out + '/inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(copy))!
		os.cp(path, copy)!
		assert locale_hash(copy)! == before[path]
	}
	locale_json(out + '/inputs-before.json', locale_map(before)!)!
	os.write_file(out + '/probe.v', program)!
	os.mkdir(out + '/tmp', mode: 0o700)!
	os.setenv('VTMP', out + '/tmp', true)
	project := out + '/c-project'
	generate := [compiler, '-no-parallel', '-generate-c-project', project, '-w', '-n', '-enable-globals',
		'-gc', 'none', '-cc', cc, '-o', out + '/probe', out + '/probe.v']
	generated := locale_record(out, 'generate', generate)!
	mut native_before := map[string]string{}
	mut built, mut ran := os.Result{exit_code: -1}, os.Result{exit_code: -1}
	build := [make, '-j1', '-C', project, '-f', 'Makefile']
	if generated.exit_code == 0 {
		assert os.ls(project)!.sorted() == ['Makefile', 'build.bat', 'build.sh', 'build_command.txt', 'probe.c'].sorted()
		mut native_paths := []string{}
		for name in os.ls(project)! { native_paths << project + '/' + name }
		// Use the complete emitted Makefile, retaining every native source/object
		// it names, including V's neighboring C helpers. Never relink only probe.c.
		for token in os.read_file(project + '/Makefile')!.split("'") {
			if token.starts_with('/') && (token.ends_with('.c') || token.ends_with('.o') || token.ends_with('.h')) {
				native_paths << token
			}
		}
		native_before = locale_pins(native_paths)!
		locale_json(out + '/native-inputs-before.json', locale_map(native_before)!)!
		for path, pin in native_before {
			copy := out + '/native-inputs/' + path.trim_left('/')
			os.mkdir_all(os.dir(copy))!
			os.cp(path, copy)!
			assert locale_hash(copy)! == pin
		}
		built = locale_record(out, 'compile', build)!
		if built.exit_code == 0 { ran = locale_record(out, 'run', [project + '/probe'])! }
	}
	after := locale_pins(paths)!
	native_after := locale_pins(native_before.keys())!
	locale_json(out + '/inputs-after.json', locale_map(after)!)!
	locale_json(out + '/native-inputs-after.json', locale_map(native_after)!)!
	locale_json(out + '/receipt.json', {
		'scope': json2.Any('Host execution of exact production locale/JNI bodies with recording C API, resource lock and allocator boundaries; no ART, actual C++ allocation or APK resource enumeration qualification.'),
		'inputs_before': locale_map(before)!, 'inputs_after': locale_map(after)!,
		'native_inputs_before': locale_map(native_before)!, 'native_inputs_after': locale_map(native_after)!,
		'generate_argv': locale_args(generate)!, 'generate_exit': json2.Any(generated.exit_code),
		'compile_argv': locale_args(build)!, 'compile_exit': json2.Any(built.exit_code),
		'run_argv': locale_args([project + '/probe'])!, 'run_exit': json2.Any(ran.exit_code),
		'negative_controls': locale_args(mutations)!, 'probe_sha256': json2.Any(locale_hash(out + '/probe.v')!)
	})!
	assert before == after && native_before == native_after, 'input changed during check'
	assert generated.exit_code == 0, generated.output
	assert built.exit_code == 0, built.output
	assert ran.exit_code == 0 && ran.output.trim_space() == locale_pass, ran.output
	println(locale_pass)
}

const locale_pass = 'ASSET-LOCALES-NATIVE-PASS locks flags datasets empty fresh-arrays native-cleanup jni-errors 6-negative-controls'

const locale_harness = r'
type Lookup = fn (voidptr, &char) voidptr
type Check = fn (voidptr) u8
type Drop = fn (voidptr, voidptr)
type WsNewArray = fn (voidptr, i32, voidptr, voidptr) voidptr
type WsNewUtf = fn (voidptr, &char) voidptr
type WsArraySet = fn (voidptr, voidptr, i32, voidptr)
type LocaleQuery = fn (voidptr, voidptr) voidptr
enum Failure { none initial_pending manager_pending manager_absent delete_missing enum_absent class_absent class_pending array_absent array_pending string_absent string_pending set_pending }
struct Probe {
mut:
 dataset int
 fail Failure
 at int
 pending bool
 bad bool
 locked bool
 managers int
 symbols int
 enters int
 enumerations int
 leaves int
 native_count int
 owned bool
 allocations int
 frees int
 deletes int
 vector [5]&char
 freed [4]bool
 finds int
 class_live int
 class_drops int
 array_calls int
 array_live [8]bool
 array_counts [8]int
 array_sets [8]int
 array_values [8][4]string
 array_drops int
 string_calls int
 call_string_index int
 string_live [32]bool
 string_values [32]string
 string_drops int
 sets int
 throws int
 thrown string
}
__global probe Probe
fn expected(dataset int) []string {
 return match dataset { 0 { ["en-US", "fr", "sr-Latn-RS"] } 1 { ["de", "ja"] } else { []string{} } }
}
fn probe_pending(_ voidptr) u8 { return u8(probe.pending) }
fn ws_manager(_ voidptr, object voidptr) voidptr {
 probe.managers++
 if object != voidptr(0x200) || probe.pending || probe.locked { probe.bad = true }
 if probe.fail == .manager_pending { probe.pending = true; return voidptr(0x300) }
 return if probe.fail == .manager_absent { unsafe { nil } } else { voidptr(0x300) }
}
fn throw(_ voidptr, class &char, _ &char) {
 if probe.locked || probe.pending { probe.bad = true }
 probe.throws++
 probe.thrown = unsafe { class.vstring() }
 probe.pending = true
}
fn probe_symbol(handle voidptr, name &char) voidptr {
 probe.symbols++
 if handle != unsafe { nil } || unsafe { name.vstring() } != "_ZdaPv"
  || probe.locked || probe.symbols != probe.enumerations + 1 || probe.owned || probe.pending { probe.bad = true }
 return if probe.fail == .delete_missing { unsafe { nil } } else { voidptr(probe_delete) }
}
fn ws_resources_enter(manager voidptr) {
 probe.enters++
 if manager != voidptr(0x300) || probe.locked || probe.pending { probe.bad = true }
 probe.locked = true
}
fn ws_resources_leave(manager voidptr) {
 probe.leaves++
 if manager != voidptr(0x300) || !probe.locked || probe.enumerations != probe.enters { probe.bad = true }
 probe.locked = false
}
fn probe_enumerate(manager voidptr, exclude_system bool, merge_equivalent bool) &&char {
 probe.enumerations++
 if manager != voidptr(0x300) || !probe.locked || probe.symbols != probe.enumerations
  || exclude_system || !merge_equivalent || probe.owned { probe.bad = true }
 if probe.fail == .enum_absent { return unsafe { nil } }
 probe.allocations++
 probe.owned = true
 probe.native_count = expected(probe.dataset).len
 probe.call_string_index = 0
 for index in 0 .. 5 { probe.vector[index] = unsafe { nil } }
 for index in 0 .. 4 { probe.freed[index] = false }
 if probe.dataset == 0 { probe.vector[0] = c"en-US"; probe.vector[1] = c"fr"; probe.vector[2] = c"sr-Latn-RS" }
 if probe.dataset == 1 { probe.vector[0] = c"de"; probe.vector[1] = c"ja" }
 return unsafe { &&char(&probe.vector[0]) }
}
fn probe_free(value voidptr) {
 if probe.locked || !probe.owned { probe.bad = true }
 mut found := false
 for index in 0 .. probe.native_count {
  if value == voidptr(probe.vector[index]) {
   if probe.freed[index] { probe.bad = true }
   probe.freed[index] = true
   found = true
  }
 }
 if !found { probe.bad = true }
 probe.frees++
}
fn probe_delete(value voidptr) {
 if probe.locked || !probe.owned || value != unsafe { voidptr(&probe.vector[0]) } { probe.bad = true }
 for index in 0 .. probe.native_count { if !probe.freed[index] { probe.bad = true } }
 probe.owned = false
 probe.deletes++
}
fn java_allowed() {
 if probe.locked || probe.pending || !probe.owned || probe.enters != probe.enumerations
  || probe.leaves != probe.enumerations { probe.bad = true }
}
fn probe_find(_ voidptr, name &char) voidptr {
 java_allowed()
 probe.finds++
 if unsafe { name.vstring() } != "java/lang/String" { probe.bad = true }
 if probe.fail == .class_absent { probe.pending = true; return unsafe { nil } }
 probe.class_live++
 if probe.fail == .class_pending { probe.pending = true }
 return voidptr(0x400)
}
fn probe_array(_ voidptr, count i32, class voidptr, initial voidptr) voidptr {
 java_allowed()
 probe.array_calls++
 if class != voidptr(0x400) || initial != unsafe { nil } || probe.class_live != 1
  || count != probe.native_count || count < 0 || count > 4 || probe.array_calls > 8 { probe.bad = true }
 if probe.fail == .array_absent { probe.pending = true; return unsafe { nil } }
 index := probe.array_calls - 1
 if index >= 8 { probe.pending = true; return unsafe { nil } }
 probe.array_live[index] = true
 probe.array_counts[index] = int(count)
 if probe.fail == .array_pending { probe.pending = true }
 return voidptr(0x1000 + index)
}
fn probe_string(_ voidptr, text &char) voidptr {
 java_allowed()
 index := probe.call_string_index
 probe.call_string_index++
 probe.string_calls++
 if index >= probe.native_count || text == unsafe { nil } || probe.string_calls > 32 {
  probe.bad = true; probe.pending = true; return unsafe { nil }
 }
 if text != probe.vector[index] { probe.bad = true }
 if probe.fail == .string_absent && index == probe.at { probe.pending = true; return unsafe { nil } }
 key := probe.string_calls - 1
 probe.string_live[key] = true
 probe.string_values[key] = unsafe { text.vstring() }
 if probe.fail == .string_pending && index == probe.at { probe.pending = true }
 return voidptr(0x2000 + key)
}
fn probe_set(_ voidptr, array voidptr, index i32, text voidptr) {
 java_allowed()
 probe.sets++
 a, s := int(usize(array)) - 0x1000, int(usize(text)) - 0x2000
 if a < 0 || a >= 8 || s < 0 || s >= 32 || index < 0 || index >= 4 { probe.bad = true; return }
 if !probe.array_live[a] || !probe.string_live[s] || index != probe.array_sets[a]
  || index >= probe.array_counts[a] { probe.bad = true }
 probe.array_sets[a]++
 if probe.fail == .set_pending && int(index) == probe.at { probe.pending = true; return }
 probe.array_values[a][index] = probe.string_values[s]
}
fn probe_drop(_ voidptr, value voidptr) {
 if probe.locked { probe.bad = true }
 if value == voidptr(0x400) { probe.class_live--; probe.class_drops++; if probe.class_live < 0 { probe.bad = true }; return }
 key := int(usize(value))
 if key >= 0x1000 && key < 0x1008 {
  index := key - 0x1000
  if !probe.array_live[index] { probe.bad = true }
  probe.array_live[index] = false; probe.array_drops++; return
 }
 if key >= 0x2000 && key < 0x2020 {
  index := key - 0x2000
  if !probe.string_live[index] { probe.bad = true }
  probe.string_live[index] = false; probe.string_drops++; return
 }
 probe.bad = true
}
fn string_locals_clean() bool {
 if probe.class_live != 0 { return false }
 for live in probe.string_live { if live { return false } }
 return true
}
fn case_ok(query LocaleQuery, e voidptr, dataset int, fail Failure, at int) bool {
 probe = Probe{dataset: dataset, fail: fail, at: at, pending: fail == .initial_pending}
 result := query(e, voidptr(0x200))
 early := fail in [.initial_pending, .manager_pending, .manager_absent, .delete_missing]
 enums := int(!early)
 allocations := int(!early && fail != .enum_absent)
 classes := allocations
 arrays := int(classes != 0 && fail !in [.class_absent, .class_pending])
 strings := if arrays == 0 || fail in [.array_absent, .array_pending] { 0 }
  else if fail in [.string_absent, .string_pending, .set_pending] { at + 1 } else { expected(dataset).len }
 sets := strings - int(fail in [.string_absent, .string_pending])
 array_drops := int(arrays != 0 && fail !in [.none, .array_absent])
 if probe.bad || probe.locked || probe.owned || !string_locals_clean()
  || probe.managers != int(fail != .initial_pending)
  || probe.symbols != int(fail !in [.initial_pending, .manager_pending, .manager_absent])
  || probe.enumerations != enums || probe.enters != enums || probe.leaves != enums
  || probe.allocations != allocations || probe.deletes != allocations || probe.frees != allocations * expected(dataset).len
  || probe.finds != classes || probe.class_drops != classes - int(fail == .class_absent)
  || probe.array_calls != arrays || probe.array_drops != array_drops
  || probe.string_calls != strings || probe.string_drops != strings - int(fail == .string_absent)
  || probe.sets != sets { return false }
 thrown := match fail { .manager_absent { "java/lang/IllegalStateException" } .delete_missing { "java/lang/UnsatisfiedLinkError" } .enum_absent { "java/lang/OutOfMemoryError" } else { "" } }
 if probe.throws != int(thrown != "") || probe.thrown != thrown || probe.pending != (fail != .none) { return false }
 if fail != .none {
  for live in probe.array_live { if live { return false } }
  return result == unsafe { nil }
 }
 if result != voidptr(0x1000) || !probe.array_live[0] || probe.array_counts[0] != expected(dataset).len { return false }
 for index, value in expected(dataset) { if probe.array_values[0][index] != value { return false } }
 return true
}
fn locale_suite(query LocaleQuery) bool {
 mut slots := [229]voidptr{}
 slots[6] = voidptr(probe_find); slots[23] = voidptr(probe_drop)
 slots[167] = voidptr(probe_string); slots[172] = voidptr(probe_array)
 slots[174] = voidptr(probe_set); slots[228] = voidptr(probe_pending)
 mut table := unsafe { voidptr(&slots[0]) }
 e := unsafe { voidptr(&table) }
 probe = Probe{}
 if query(unsafe { nil }, voidptr(0x200)) != unsafe { nil } || probe.managers != 0 || probe.symbols != 0 { return false }
 for dataset in 0 .. 3 { if !case_ok(query, e, dataset, .none, 0) { return false } }
 for fail in [Failure.initial_pending, .manager_pending, .manager_absent, .delete_missing, .enum_absent,
  .class_absent, .class_pending, .array_absent, .array_pending] {
  if !case_ok(query, e, 0, fail, 0) { return false }
 }
 for fail in [Failure.string_absent, .string_pending, .set_pending] {
  for at in 0 .. 3 { if !case_ok(query, e, 0, fail, at) { return false } }
 }
 probe = Probe{}
 first := query(e, voidptr(0x200))
 probe.dataset = 1
 second := query(e, voidptr(0x200))
 probe.dataset = 2
 third := query(e, voidptr(0x200))
 if first != voidptr(0x1000) || second != voidptr(0x1001) || third != voidptr(0x1002)
  || probe.bad || probe.owned || probe.locked || probe.pending || !string_locals_clean()
  || probe.allocations != 3 || probe.deletes != 3 || probe.frees != 5 || probe.array_drops != 0
  || probe.array_counts[0] != 3 || probe.array_counts[1] != 2 || probe.array_counts[2] != 0 { return false }
 for array in 0 .. 2 {
  for index, value in expected(array) { if probe.array_values[array][index] != value { return false } }
 }
 // A caller may change its Java array without changing later snapshots.
 probe.array_values[0][0] = "caller changed"
 probe.dataset = 0
 fourth := query(e, voidptr(0x200))
 if fourth != voidptr(0x1003) || probe.bad || probe.owned || probe.locked || probe.pending
  || !string_locals_clean() || probe.allocations != 4 || probe.deletes != 4 || probe.frees != 8
  || probe.array_drops != 0 || probe.array_counts[3] != 3
  || probe.array_values[0][0] != "caller changed" || probe.array_counts[2] != 0 { return false }
 for index, value in expected(0) { if probe.array_values[3][index] != value { return false } }
 for index, value in expected(1) { if probe.array_values[1][index] != value { return false } }
 return true
}
'
