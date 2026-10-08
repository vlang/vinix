module runtimefixture

import crypto.sha256
import json2
import os

const atl_original_source = '221b257173b4980ec0be6364aa26de023a8da4720d6430df1b32f22b2d4eb0f6'

struct AtlContext {
	root      string
	overlay   string
	runtime   string
	constants map[string]json2.Any
mut:
	manifest map[string]json2.Any
}

fn atl_context() !AtlContext {
	constants := map_field(call({
		'attributes': json2.Any(['ATL_SOURCE_COMMIT', 'ATL_SOURCE_SHA256', 'ATL_SOURCE_SHA512',
			'ATL_PATCH', 'PATCH', 'ATL_CORE_CLASSES_SHA256', 'ATL_ELFS', 'ATL_JARS', 'ATL_RESOURCES',
			'ATL_FONTS', 'ATL_MANIFEST', 'ATL_REQUIRED', 'ATL_DEX_DIRECTORY', 'MANIFEST',
			'BIONIC_MANIFEST', 'ANDROIDFW_HEADER', 'ANDROIDFW_LIBRARY', 'LIBART'].map(json2.Any(it)))
	})!, 'result').as_map()
	boot := map_field(call({
		'module':     json2.Any('boot')
		'attributes': json2.Any(['INPUTS', 'COMPILER_ARGUMENTS'].map(json2.Any(it)))
	})!, 'result').as_map()
	root := temporary()!
	mut transferred := false
	defer { if !transferred { os.rmdir_all(root) or { panic(err) } } }
	os.mkdir(root + '/overlay')!
	support := repository() + '/build-support/android'
	probe := native_call('configuration_probe_digest', []string{}, []json2.Any{})!
	mut c := AtlContext{root, root + '/overlay', root + '/runtime', constants, {
		'format':                      json2.Any(1)
		'architecture':                json2.Any('aarch64')
		'page_size':                   json2.Any(16384)
		'source_commit':               map_field(constants, 'ATL_SOURCE_COMMIT')
		'source_sha256':               map_field(constants, 'ATL_SOURCE_SHA256')
		'source_sha512':               map_field(constants, 'ATL_SOURCE_SHA512')
		'patch_sha256':                json2.Any(sha256.sum(os.read_bytes(text(constants, 'ATL_PATCH'))!).hex())
		'androidfw_patch_sha256':      json2.Any(sha256.sum(os.read_bytes(text(constants, 'PATCH'))!).hex())
		'androidfw_configuration_api': json2.Any(1)
		'androidfw_header_sha256':     json2.Any('a'.repeat(64))
		'androidfw_library_sha256':    json2.Any('c'.repeat(64))
		'configuration_probe_sha256':  probe
		'build_flags':                 json2.Any(['--buildtype=release', '-Wl,-z,max-page-size=65536'].map(json2.Any(it)))
		'builder_sha256':              json2.Any(sha256.sum(os.read_bytes(support + '/build-atl.sh')!).hex())
		'dex_adapter_sha256':          json2.Any(sha256.sum(os.read_bytes(support + '/atl-dex.py')!).hex())
		'dex_compiler_sha256':         map_field(map_field(boot, 'INPUTS').as_array()[2].as_map(), 'sha256')
		'java_core_classes_sha256':    map_field(constants, 'ATL_CORE_CLASSES_SHA256')
		'dex_compiler_arguments':      map_field(boot, 'COMPILER_ARGUMENTS')
		'dex_compiler':                json2.Any('D8 8.3.37 (build official)')
		'files':                       json2.Any([]json2.Any{})
	}}
	for name in strings(constants, 'ATL_ELFS') { c.payload(name, elf(183, 0), 0o755)! }
	for name in strings(constants, 'ATL_JARS') {
		c.payload(name, c.archive([['classes.dex', boot_dex('Landroid/os/Build;', 0).hex()]])!, 0o755)!
	}
	c.payload(text(constants, 'ATL_RESOURCES'), c.archive([
		['AndroidManifest.xml', 'manifest'.bytes().hex()],
		['resources.arsc', 'resources'.bytes().hex()],
	])!, 0o755)!
	c.payload(text(constants, 'ATL_FONTS'), '<familyset><family><font>Roboto-Regular.ttf</font></family></familyset>'.bytes(), 0o755)!
	transferred = true
	return c
}

fn (c AtlContext) archive(entries [][]string) ![]u8 {
	path := c.root + '/fixture-archive.zip'
	boot_zip_write(path, entries)!
	defer { os.rm(path) or { panic(err) } }
	return os.read_bytes(path)!
}

fn (mut c AtlContext) write_manifest() ! {
	os.write_file(c.overlay + '/' + text(c.constants, 'ATL_MANIFEST'), json2.encode(c.manifest))!
}

fn (mut c AtlContext) payload(name string, contents []u8, mode u32) !string {
	path := c.overlay + '/' + name
	os.mkdir_all(os.dir(path))!
	os.write_file_array(path, contents)!
	os.chmod(path, int(mode))!
	mut records := map_field(c.manifest, 'files').as_array().filter(text(it.as_map(), 'path') != name)
	mut record := {
		'path':   json2.Any(name)
		'size':   json2.Any(contents.len)
		'sha256': json2.Any(sha256.sum(contents).hex())
	}
	record['kind'] = json2.Any(if contents.len >= 4 && contents[..4] == [u8(0x7f), `E`, `L`, `F`] {
		'elf'
	} else if name.ends_with('.jar') {
		'dex'
	} else {
		'data'
	})
	if name.ends_with('.jar') {
		record['class_count'] = json2.Any(1)
		record['bootstrap_callsites'] = json2.Any(0)
	}
	records << json2.Any(record)
	c.manifest['files'] = json2.Any(records)
	c.write_manifest()!
	return path
}

fn (c AtlContext) read() !json2.Any {
	return native_call('read_atl_manifest', [c.overlay], []json2.Any{})!
}

fn (mut c AtlContext) reject() ! {
	c.write_manifest()!
	failure('read_atl_manifest', [c.overlay], []json2.Any{}, ['RuntimeError'], '')!
}

fn atl_installs_one_coherent_native_framework_without_mutating_old_alias(mut c AtlContext) ! {
	name := 'usr/lib/libandroid.so.0'
	old := c.runtime + '/' + name
	os.mkdir_all(os.dir(old))!
	os.write_file(old, 'old framework')!
	alias := c.root + '/old-package-library.so'
	link(old, alias)!
	verified := c.read()!
	assert equivalent(native_call('apply_atl', [c.overlay, c.runtime], [verified])!, verified)
	assert os.read_file(alias)! == 'old framework'
	for record in map_field(verified.as_map(), 'files').as_array() {
		assert os.read_bytes(c.runtime + '/' + text(record.as_map(), 'path'))! == os.read_bytes(c.overlay + '/' + text(record.as_map(), 'path'))!
	}
}

fn atl_androidfw_pair_requires_exact_header_library_patch_and_api(mut c AtlContext) ! {
	dependency := {
		'androidfw_configuration_api': json2.Any(1)
		'patch_sha256':                json2.Any(sha256.sum(os.read_bytes(text(c.constants, 'PATCH'))!).hex())
		'files':                       json2.Any([
			json2.Any({
				'path':   map_field(c.constants, 'ANDROIDFW_HEADER')
				'sha256': json2.Any('a'.repeat(64))
			}),
			json2.Any({
				'path':   map_field(c.constants, 'ANDROIDFW_LIBRARY')
				'sha256': json2.Any('c'.repeat(64))
			}),
		])
	}
	native_call('validate_atl_art_pair', []string{}, [json2.Any(dependency), json2.Any(c.manifest)])!
	for key in ['androidfw_configuration_api', 'patch_sha256'] {
		mut changed := record_copy(dependency)
		changed[key] = json2.Any('changed')
		failure('validate_atl_art_pair', []string{}, [json2.Any(changed), json2.Any(c.manifest)], ['RuntimeError'], '')!
	}
	for index in 0 .. 2 {
		mut changed := boot_copy_manifest(dependency)
		mut files := map_field(changed, 'files').as_array().clone()
		mut record := record_copy(files[index].as_map())
		record['sha256'] = json2.Any('b'.repeat(64))
		files[index] = json2.Any(record)
		changed['files'] = json2.Any(files)
		failure('validate_atl_art_pair', []string{}, [json2.Any(changed), json2.Any(c.manifest)], ['RuntimeError'], '')!
	}
}

fn atl_rejects_wrong_source_builder_compiler_flags_or_inputs(mut c AtlContext) ! {
	changes := [BootMutation{'page_size', json2.Any(4096)},
		BootMutation{'architecture', json2.Any('x86_64')},
		BootMutation{'source_commit', json2.Any('b'.repeat(40))},
		BootMutation{'source_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'source_sha512', json2.Any('b'.repeat(128))},
		BootMutation{'builder_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'patch_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'androidfw_patch_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'androidfw_configuration_api', json2.Any(0)},
		BootMutation{'androidfw_header_sha256', json2.Any('invalid')},
		BootMutation{'androidfw_library_sha256', json2.Any('invalid')},
		BootMutation{'configuration_probe_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'dex_adapter_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'dex_compiler_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'java_core_classes_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'dex_compiler_arguments', json2.Any([]json2.Any{})},
		BootMutation{'build_flags', json2.Any([]json2.Any{})},
		BootMutation{'dex_compiler', json2.Any('D8 other')}]
	for change in changes {
		old := map_field(c.manifest, change.name)
		c.manifest[change.name] = change.value
		c.reject()!
		c.manifest[change.name] = old
	}
}

fn atl_requires_every_framework_component(mut c AtlContext) ! {
	original := map_field(c.manifest, 'files')
	for name in strings(c.constants, 'ATL_REQUIRED') {
		c.manifest['files'] = json2.Any(original.as_array().filter(text(it.as_map(), 'path') != name))
		c.reject()!
	}
	c.manifest['files'] = original
}

fn atl_rejects_non_native_elf_or_mismatched_soname(mut c AtlContext) ! {
	for contents in [elf(62, 0), elf(183, 4096), 'not an ELF'.bytes(), stale_elf()] {
		c.payload('usr/lib/libandroid.so', contents, 0o755)!
		c.reject()!
	}
}

fn atl_rejects_checksum_consistent_jar_with_bootstrap_calls_or_false_class_receipt(mut c AtlContext) ! {
	name := text(c.constants, 'ATL_DEX_DIRECTORY') + '/api-impl.jar'
	c.payload(name, c.archive([['classes.dex', boot_dex('Landroid/os/Build;', 1).hex()]])!, 0o755)!
	c.reject()!
	c.payload(name, c.archive([['classes.dex', boot_dex('Landroid/os/Build;', 0).hex()]])!, 0o755)!
	mut files := map_field(c.manifest, 'files').as_array().clone()
	mut record := record_copy(files.last().as_map())
	record['class_count'] = json2.Any(2)
	files[files.len - 1] = json2.Any(record)
	c.manifest['files'] = json2.Any(files)
	c.reject()!
	c.payload(name, 'not a JAR'.bytes(), 0o755)!
	c.reject()!
}

fn atl_rejects_incomplete_resource_apk_and_font_map(mut c AtlContext) ! {
	name := text(c.constants, 'ATL_RESOURCES')
	c.payload(name, c.archive([['AndroidManifest.xml', 'manifest'.bytes().hex()]])!, 0o755)!
	c.reject()!
	c.payload(name, c.archive([['AndroidManifest.xml', 'manifest'.bytes().hex()],
		['resources.arsc', 'resources'.bytes().hex()]])!, 0o755)!
	for contents in ['<bad>', '<familyset/>', '<wrong><family/></wrong>'] {
		c.payload(text(c.constants, 'ATL_FONTS'), contents.bytes(), 0o755)!
		c.reject()!
	}
}

fn binding_value(value json2.Any) json2.Any {
	return json2.Any({
		'kind':  json2.Any('value')
		'value': value
	})
}

fn binding_return(value json2.Any) json2.Any {
	return json2.Any({
		'kind':  json2.Any('return')
		'value': value
	})
}

fn binding_public(operation string, keywords map[string]json2.Any) json2.Any {
	return json2.Any({
		'kind':      json2.Any('public')
		'module':    json2.Any('art-runtime.py')
		'operation': json2.Any(operation)
		'keywords':  json2.Any(keywords)
	})
}

fn (c AtlContext) stage_android() !map[string]json2.Any {
	build := c.root + '/build'
	art := c.root + '/art'
	bionic := c.root + '/bionic'
	for directory in [build, art, bionic] { os.mkdir_all(directory)! }
	log := c.root + '/build-calls.jsonl'
	os.write_file(log, '')!
	mut attributes := map[string]json2.Any{}
	for name in ['MANIFEST', 'BIONIC_MANIFEST', 'ATL_MANIFEST'] {
		attributes[name] = binding_value(map_field(c.constants, name))
	}
	attributes['read_manifest'] = binding_return(binding_value(json2.Any({
		'bootclasspath': json2.Any({
			'verified': json2.Any(true)
		})
	})))
	attributes['read_bionic_manifest'] = binding_return(binding_value(json2.Any({
		'verified': json2.Any(true)
	})))
	attributes['read_atl_manifest'] = binding_public('_read_manifest', {
		'atl': json2.Any(true)
	})
	attributes['validate_atl_art_pair'] = binding_return(binding_value(json2.Any(json2.Null{})))
	attributes['apply'] = json2.Any({
		'kind':      json2.Any('callback')
		'operation': json2.Any('install_art')
		'context':   json2.Any(c.constants)
	})
	attributes['apply_bionic'] = binding_return(binding_value(json2.Any(json2.Null{})))
	attributes['apply_atl'] = binding_public('apply_atl', map[string]json2.Any{})
	namespace := json2.Any({
		'kind':       json2.Any('namespace')
		'attributes': json2.Any(attributes)
	})
	musl := json2.Any({
		'kind':       json2.Any('namespace')
		'attributes': json2.Any({
			'read_manifest': binding_return(binding_value(json2.Any({
				'verified': json2.Any(true)
			})))
		})
	})
	patches := [json2.Any([json2.Any('art_tools'), binding_return(namespace)]),
		json2.Any([json2.Any('musl_tools'), binding_return(musl)]),
		json2.Any([json2.Any('shutil.which'),
			binding_return(binding_value(json2.Any('isolated-test-compiler')))]),
		json2.Any([json2.Any('subprocess.run'),
			json2.Any({
				'kind':      json2.Any('callback')
				'operation': json2.Any('run')
				'completed': json2.Any(true)
				'context':   json2.Any({
					'log': json2.Any(log)
				})
			})])]
	arguments := [boot_arg('namespace', json2.Any({
		'build_dir':       boot_path(build)
		'art_runtime':     boot_path(art)
		'bionic_runtime':  boot_path(bionic)
		'atl_runtime':     boot_path(c.overlay)
		'with_calculator': boot_arg('value', json2.Any(false))
	})),
		boot_arg('value', json2.Any({
			'architecture': json2.Any('aarch64')
			'mirror':       json2.Any('https://example.invalid')
			'packages':     json2.Any([]json2.Any{})
		})), boot_path(build + '/downloads')]
	return call({
		'module':          json2.Any('builder')
		'operation':       json2.Any('stage')
		'arguments':       json2.Any(arguments)
		'patches':         json2.Any(patches)
		'callback_binary': json2.Any(os.executable())
		'record_patch':    json2.Any(log)
	})!
}

fn (c AtlContext) staged() !map[string]json2.Any {
	row := c.stage_android()!
	assert 'result' in row, json2.encode(row)
	staging := text(row, 'result')
	prefix := map_field(call({
		'module':     json2.Any('builder')
		'attributes': json2.Any([json2.Any('PREFIX')])
	})!, 'result').as_map()
	return {
		'runtime': json2.Any(staging + '/' + text(prefix, 'PREFIX').trim_left('/'))
		'calls':   map_field(row, 'run_calls')
	}
}

fn atl_builder_stages_coherent_atl_and_rejects_stale_cached_framework(mut c AtlContext) ! {
	staged := c.staged()!
	runtime := text(staged, 'runtime')
	assert map_field(staged, 'calls').int() > 0
	for record in map_field(c.manifest, 'files').as_array() {
		name := text(record.as_map(), 'path')
		assert os.read_bytes(runtime + '/' + name)! == os.read_bytes(c.overlay + '/' + name)!
	}
	mut receipt := json2.decode[map[string]json2.Any](os.read_file(runtime + '/runtime-manifest.json')!)!
	assert equivalent(map_field(receipt, 'atl'), c.read()!)
	assert map_field(c.staged()!, 'calls').int() == 0
	os.write_file(runtime + '/' + text(c.constants, 'ATL_DEX_DIRECTORY') + '/api-impl.jar', 'stale framework')!
	assert map_field(c.staged()!, 'calls').int() > 0
	assert equivalent(native_call('_read_manifest', [runtime], [json2.Any(false), json2.Any(true)])!, c.read()!)
	c.payload(text(c.constants, 'ATL_FONTS'), '<familyset><family><font>NewFont.ttf</font></family></familyset>'.bytes(), 0o755)!
	assert map_field(c.staged()!, 'calls').int() > 0
	receipt = json2.decode[map[string]json2.Any](os.read_file(runtime + '/runtime-manifest.json')!)!
	assert equivalent(map_field(receipt, 'atl'), c.read()!)
	assert os.read_bytes(runtime + '/' + text(c.constants, 'ATL_FONTS'))! == os.read_bytes(c.overlay + '/' + text(c.constants, 'ATL_FONTS'))!
}

fn atl_invalid_atl_input_does_not_replace_existing_staging(mut c AtlContext) ! {
	runtime := text(c.staged()!, 'runtime')
	sentinel := runtime + '/existing-staging'
	os.write_file(sentinel, 'retain on invalid source')!
	os.write_file(c.overlay + '/' + text(c.constants, 'ATL_DEX_DIRECTORY') + '/api-impl.jar', 'invalid source')!
	row := c.stage_android()!
	assert text(row, 'kind') == 'RuntimeError', json2.encode(row)
	assert os.read_file(sentinel)! == 'retain on invalid source'
	assert equivalent(native_call('_read_manifest', [runtime], [json2.Any(false), json2.Any(true)])!, json2.Any(c.manifest))
}

// Generic unittest mock callbacks are request-local Python stdlib primitives;
// fixture command effects and ELF generation belong to this native policy.
pub fn atl_binding(row map[string]json2.Any) !json2.Any {
	arguments := map_field(row, 'arguments').as_array()
	context := map_field(row, 'context').as_map()
	match text(row, 'operation') {
		'install_art' {
			runtime := arguments[1].str()
			for name in ['lib/ld-musl-aarch64.so.1', text(context, 'LIBART')] {
				path := runtime + '/' + name
				os.mkdir_all(os.dir(path))!
				os.write_file_array(path, elf(183, 0))!
			}
			return json2.Null{}
		}
		'run' {
			command := arguments[0].as_array().map(it.str())
			if command[0] == 'sh' { return json2.Any('fixture V compiler\n') }
			if command.len > 2 && command[1].ends_with('/compile-v-runtime.py') {
				os.write_file_array(command[2], elf(183, 0))!
			}
			if '-o' in command {
				os.write_file_array(command[command.index('-o') + 1], elf(183, 0))!
			}
			mut log := os.open_append(text(context, 'log'))!
			defer { log.close() }
			log.writeln(json2.encode(command))!
			return json2.Null{}
		}
		else { return error('Unknown ATL binding ' + text(row, 'operation')) }
	}
}

pub fn run_atl_guarded(selection string) ! { guarded(selection, '--child-atl')! }

pub fn run_atl(selection string) ! {
	gold := json2.decode[map[string]json2.Any](os.read_file(os.dir(@FILE) + '/atl-builders.json')!)!
	assert text(gold, 'original_source_sha256') == atl_original_source
	for item in map_field(gold, 'elf').as_array() {
		row := item.as_map()
		assert elf(u16(map_field(row, 'machine').int()), map_field(row, 'offset').int()).hex() == text(row, 'hex')
	}
	for item in map_field(gold, 'dex').as_array() {
		row := item.as_map()
		assert boot_dex('Landroid/os/Build;', u32(map_field(row, 'callsites').int())).hex() == text(row, 'hex')
	}
	cases := map[string]fn (mut AtlContext) !{
		'AtlTests.test_installs_one_coherent_native_framework_without_mutating_old_alias':           atl_installs_one_coherent_native_framework_without_mutating_old_alias
		'AtlTests.test_androidfw_pair_requires_exact_header_library_patch_and_api':                  atl_androidfw_pair_requires_exact_header_library_patch_and_api
		'AtlTests.test_rejects_wrong_source_builder_compiler_flags_or_inputs':                       atl_rejects_wrong_source_builder_compiler_flags_or_inputs
		'AtlTests.test_requires_every_framework_component':                                          atl_requires_every_framework_component
		'AtlTests.test_rejects_non_native_elf_or_mismatched_soname':                                 atl_rejects_non_native_elf_or_mismatched_soname
		'AtlTests.test_rejects_checksum_consistent_jar_with_bootstrap_calls_or_false_class_receipt': atl_rejects_checksum_consistent_jar_with_bootstrap_calls_or_false_class_receipt
		'AtlTests.test_rejects_incomplete_resource_apk_and_font_map':                                atl_rejects_incomplete_resource_apk_and_font_map
		'AtlTests.test_builder_stages_coherent_atl_and_rejects_stale_cached_framework':              atl_builder_stages_coherent_atl_and_rejects_stale_cached_framework
		'AtlTests.test_invalid_atl_input_does_not_replace_existing_staging':                         atl_invalid_atl_input_does_not_replace_existing_staging
	}
	assert selection == '' || selection in cases, 'Unknown native fixture ' + selection
	for name, test in cases {
		if selection != '' && selection != name { continue }
		atl_run_case(test)!
		println('PASS ' + name)
	}
}

fn atl_run_case(test fn (mut AtlContext) !) ! {
	mut c := atl_context()!
	defer { os.rmdir_all(c.root) or { panic(err) } }
	test(mut c)!
}
