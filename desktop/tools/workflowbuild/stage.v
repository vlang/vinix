// SPDX-License-Identifier: GPL-2.0-or-later
module workflowbuild

import os
import strings
import hosttest

pub fn run(program string, args []string) ! {
	mut p := os.new_process(program)
	defer { p.close() }
	p.set_args(args)
	p.run()
	p.wait()
	if p.code != 0 { return error('${program} failed (${p.code})') }
}

pub fn test(v string, args []string, work string, name string) ! {
	mut generate := args.clone()
	generate.insert(generate.len - 1, ['-o', '${work}/test.c'])
	run(v, generate)!
	mut source := os.read_file('${work}/test.c')!
	source = source.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')
	$if macos { source = source.replace('ptrdiff_t offset);', 'int64_t offset);') }
	os.write_file('${work}/test.c', source)!
	mut cflags := ['-w', '-O0', '-I', work]
	$if macos { cflags << ['-x', 'objective-c', '-framework', 'Cocoa', '-framework', 'QuartzCore'] }
	cflags << ['${work}/test.c']
	$if macos { cflags << ['-x', 'none'] }
	cflags << ['${work}/presenter.o', '-lpthread', '-lm', '-o', '${work}/test']
	run('clang', cflags)!
	println('Running ${name}')
	run('${work}/test', [])!
}

fn literal(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + "'"
}

pub fn stage(root string, ui string, dest string, cross bool) ! {
	if os.exists(dest) { os.rmdir_all(dest)! }
	os.mkdir_all(dest)!
	if os.is_dir('${root}/desktop/workflowcore') {
		os.mkdir_all('${dest}/modules/desktop')!
		os.cp_all('${root}/desktop/workflowcore', '${dest}/modules/desktop/workflowcore', true)!
	}
	for name in os.ls('${root}/desktop')! {
		path := '${root}/desktop/${name}'
		if !os.is_file(path) || (!name.ends_with('.v') && !name.ends_with('.vml') && !name.ends_with('.h')) { continue }
		mut source := os.read_file(path)!
		if source.starts_with('// Copyright (c) ') {
			if end := source.index('// SPDX-License-Identifier:') { source = source[end..] }
		}
		os.write_file('${dest}/${name}', source)!
	}
	os.write_file('${dest}/v.mod', "Module { name: 'desktop_workflows' }\n")!
	os.mkdir_all('${dest}/modules/ui2')!
	os.write_file('${dest}/modules/ui2/v.mod', os.read_file('${ui}/v.mod')!.replace("'appkit',", ''))!
	for directory in ['ui', 'linux', 'uikit', 'windows', 'assets'] {
		os.cp_all('${ui}/${directory}', '${dest}/modules/ui2/${directory}', true)!
		for name in os.ls('${dest}/modules/ui2/${directory}')! {
			if name.ends_with('_tmp.v') { os.rm('${dest}/modules/ui2/${directory}/${name}')! }
		}
	}
	os.cp('${root}/desktop/tools/ui2_headless_bounds.v', '${dest}/modules/ui2/ui/vinix_headless_backend.v')!
	bridge := '${dest}/modules/ui2/ui/vinix_headless_backend.v'
	os.write_file(bridge, os.read_file(bridge)!.replace('(linux || vinix) && ui2_headless ?', 'ui2_headless ?'))!
	vml := '${dest}/modules/ui2/ui/vml_embed.v'
	if os.exists(vml) {
		mut source := os.read_file(vml)!.replace('(mut app VmlApp[T])', '(mut vml_app VmlApp[T])').replace('(app &VmlApp[T])', '(vml_app &VmlApp[T])')
		for member in ['control_text', 'control_value', 'events', 'model', 'template', 'text_of', 'value_of'] { source = source.replace('app.${member}', 'vml_app.${member}') }
		os.write_file(vml, source)!
	}
	for directory in ['ui', 'linux'] {
		for name in ['file_dialog_linux.v', 'message_box_linux.v'] {
			path := '${dest}/modules/ui2/${directory}/${name}'
			if os.exists(path) { os.write_file(path, os.read_file(path)!.replace('os.execute(command)', "os.exec(['/bin/sh', '-c', command])"))! }
		}
	}
	calculator := os.read_file('${ui}/examples/calculator/main.v')!
	end := calculator.index('\nfn main()') or { return error('calculator entry point missing') }
	os.write_file('${dest}/app_calculator.v', calculator[..end])!
	for name in os.ls('${ui}/examples/calculator')! {
		if !name.ends_with('.v') && os.is_file('${ui}/examples/calculator/${name}') { os.cp('${ui}/examples/calculator/${name}', '${dest}/${name}')! }
	}
	mut translations := "module main\nconst desktop_translation_files = {\n"
	for name in os.ls('${root}/desktop/translations')! {
		if name.ends_with('.tr') { translations += "'${name}': " + literal(os.read_file('${root}/desktop/translations/${name}')!) + ',\n' }
	}
	os.write_file('${dest}/translations_data.v', translations + '}\n')!
	mut icons := strings.new_builder(1024 * 1024)
	icons.write_string('#include <string.h>\n#include <stddef.h>\n')
	mut entries := []string{}
	for name in os.ls('${root}/desktop/assets')! {
		if !name.ends_with('.qoi') { continue }
		stem := name[..name.len - 4]
		data := os.read_bytes('${root}/desktop/assets/${name}')!
		icons.write_string('static const unsigned char icon_${stem}[] = {')
		for byte in data { icons.write_string('${byte},') }
		icons.write_string('};\n')
		entries << 'if (strcmp(name, "${stem}") == 0) { *size = sizeof(icon_${stem}); return (void*)icon_${stem}; }'
	}
	icons.write_string('static void* vinix_app_icon_data(const char* name, size_t* size) {\n' + entries.join('\n') + '\n*size = 0; return NULL; }\n')
	icons.write_string('static size_t vinix_app_icon_size(const char* name) { size_t size = 0; vinix_app_icon_data(name, &size); return size; }\n')
	os.write_file('${dest}/app_icon_data.h', icons.str())!
	hosttest.generate_module('${root}/desktop/gpucore', '${dest}/presenter.c', 'arm64', [])!
	hosttest.emit_module_header('${root}/desktop/gpucore', '${dest}/presenter.c', '${dest}/gpu_present.h')!
	if cross {
		hosttest.generate_module('${root}/desktop/execinfocore', '${dest}/execinfo.c', 'arm64', [])!
	} else {
		run('clang', ['-O2', '-c', '${dest}/presenter.c', '-o', '${dest}/presenter.o'])!
		os.write_file('${dest}/presenter_flags.v', 'module main\n#flag @VMODROOT/presenter.o\n')!
	}
}
