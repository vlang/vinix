// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixturebuild

import hosttest
import json2
import os

pub fn existing(path string) string {
	return if os.exists(path) { path } else { path + '.pending' }
}

// Only source files are staged. The independent test bodies and shared model
// declarations keep their original contents apart from the module namespace.
pub struct TemplateFailure {
pub:
	fields map[string]json2.Any
}
pub fn (e TemplateFailure) msg() string { return e.fields['message'] or { json2.Any('Invalid replacement template') }.str() }
pub fn (e TemplateFailure) code() int { return 0 }

pub fn model_namespace(text string, name string, template []json2.Any) string {
	mut lines := text.split('\n')
	for index, line in lines {
		if line.starts_with('module ') && line.len > 7 && line[7..].runes().all(hosttest.module_word_rune(it)) {
			mut replacement := if template.len == 0 { 'module ' + name } else { '' }
			for value in template {
				row := value.as_map()
				replacement += if 'whole' in row { line } else { row['literal'] or { json2.Any('') }.str() }
			}
			lines[index] = replacement
			break
		}
	}
	return lines.join('\n')
}

pub fn generate(source string, output string, arch string, shared_model bool) !hosttest.Result {
	return generate_template(source, output, arch, shared_model, []json2.Any{}, map[string]json2.Any{})!
}

pub fn generate_template(source string, output string, arch string, shared_model bool, template []json2.Any, template_error map[string]json2.Any) !hosttest.Result {
	work := hosttest.work_dir('', 'vinix-v-host-')!
	result := generate_staged(work, source, output, arch, shared_model, template, template_error) or {
		// TemporaryDirectory cleanup can replace a preparation/compiler error.
		// Retire after the compiler has been reaped and propagate that error.
		failure := err
		hosttest.remove_work_dir(work)!
		return failure
	}
	hosttest.remove_work_dir(work)!
	return result
}

fn generate_staged(work string, source string, output string, arch string, shared_model bool, template []json2.Any, template_error map[string]json2.Any) !hosttest.Result {
	name := if source in ['.', '/', '//'] { '' } else { source.trim_right('/').all_after_last('/') }
	stage := if name == '' { work } else { work + '/' + name }
	os.mkdir(stage) or { return hosttest.ModuleFileError{stage, err.code(), err.msg()} }
	for item in os.ls(source) or { return hosttest.ModuleFileError{source, err.code(), err.msg()} } {
		path := source + '/' + item
		if os.is_file(path) && ((item.ends_with('.v') && item != '.v') || item.ends_with('.v.pending')) {
			filename := if item.ends_with('.pending') { item[..item.len - '.pending'.len] } else { item }
			hosttest.module_copy_file(path, stage + '/' + filename)!
		}
	}
	if shared_model {
		text := hosttest.module_read_text(existing(hosttest.root() + '/tests/linuxkpi/host_model_foreign.v'))!
		if template_error.len != 0 { return TemplateFailure{template_error} }
		hosttest.module_write_text(stage + '/model_foreign.v', model_namespace(text, name, template))!
	}
	return hosttest.generate_module_capture(stage, output, arch, ['nofloat'])!
}
