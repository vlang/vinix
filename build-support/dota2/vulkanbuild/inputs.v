// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanbuild

import json2
import os
import qemubuild

pub fn compatibility_inputs(repo string, module_name string, header string, extra json2.Any) !json2.Any {
	directory := join(repo + '/build-support/dota2', module_name)
	mut names := os.ls(directory) or { []string{} }
	names = names.filter(it.ends_with('.v'))
	names.sort()
	mut files := names.map(directory + '/' + it)
	files << join(repo + '/build-support/dota2', header)
	for value in request({
		'kind':   json2.Any('keys')
		'target': extra
	})!.as_array() {
		files << path(value)!
	}
	files << [repo + '/build-support/dota2/compile-v-compat.py',
		repo + '/build-support/compile-v-module.py', repo + '/build-support/find-v.sh']
	mut result := map[string]json2.Any{}
	for filename in files {
		relative := path(method(paths(filename), 'relative_to', [paths(repo)])!)!
		result[relative] = json2.Any(digest(filename)!)
	}
	version := command('check_output', ['sh', '-c', '. "$1/build-support/find-v.sh"; "$V" -version',
		'find-v', repo], {
		'text': json2.Any(true)
	})!.str()
	result['v_compiler'] = json2.Any(strip_space(version))
	return json2.Any(result)
}

pub fn build_compat(repo string, python string, destination string, artifacts string, early bool) ! {
	qemubuild.mkdir(artifacts, true, true)!
	generated := artifacts + '/' + if early { 'early-client-v.c' } else { 'mmap32-v.c' }
	command('run', [python, repo + '/build-support/dota2/compile-v-compat.py',
		if early { 'early' } else { 'mmap32' }, generated, '--bare'], {
		'check': json2.Any(true)
	})!
	mut flags := global(if early { 'EARLY_CLIENT_COMPILE' } else { 'MMAP32_COMPILE' })!.as_array().map(it.str())
	flags << [generated, '-o', destination]
	command('run', flags, {
		'check': json2.Any(true)
	})!
}

pub fn lavapipe_inputs() !json2.Any {
	builder := public('load_mesa_builder', [])!
	inputs := method(builder, 'load_inputs', [])!.as_map()
	support := path(attribute(builder, 'SUPPORT')!)!
	mut patches := map[string]json2.Any{}
	for name in inputs['patches']!.as_map().keys() {
		patches[name] = json2.Any(digest(support + '/' + name)!)
	}
	return json2.Any({
		'debian_version': inputs['debian_version']!
		'builder':        json2.Any(digest(path(global('MESA_BUILDER')!)!)!)
		'inputs':         json2.Any(digest(support + '/inputs.json')!)
		'patches':        json2.Any(patches)
	})
}

pub fn venus_inputs() !json2.Any {
	builder := public('load_venus_builder', [])!
	mut patches := map[string]json2.Any{}
	patch_values := attribute(builder, 'PATCHES')!
	for value in request({
		'kind':   json2.Any('keys')
		'target': patch_values
	})!.as_array() {
		filename := path(value)!
		patches[qemubuild.basename(filename)] = json2.Any(digest(filename)!)
	}
	return json2.Any({
		'version': attribute(builder, 'VERSION')!
		'source':  attribute(builder, 'SOURCE_SHA256')!
		'builder': json2.Any(digest(path(global('VENUS_BUILDER')!)!)!)
		'patches': json2.Any(patches)
	})
}
