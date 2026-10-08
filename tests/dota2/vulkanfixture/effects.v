// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanfixture

import json2
import qemubuild

fn view(c Context) json2.Any {
	return json2.Any({
		'base':   json2.Any(c.base)
		'build':  json2.Any(c.build)
		'repo':   json2.Any(c.repo)
		'python': json2.Any(c.python)
	})
}

fn callback(name string, context json2.Any, result string) json2.Any {
	return json2.Any({
		'kind':    json2.Any('callback')
		'name':    json2.Any(name)
		'context': context
		'result':  json2.Any(result)
	})
}

fn run_stage(c Context, extra []string, expected []string) ! {
	set_member('lavapipe_bases', json2.Any([]json2.Any{}))!
	set_member('venus_bases', json2.Any([]json2.Any{}))!
	mut args := [attribute(global('_stage')!, '__file__')!.str(), '--steam-build', c.steam, '--build',
		c.build]
	args << extra
	patches := json2.Any([
		json2.Any([words(['sys', 'argv']), value(words(args))]),
		json2.Any([words(['stage', 'load_glibc_pin']), json2.Any({
			'kind': json2.Any('member')
			'name': json2.Any('pin')
		})]),
		json2.Any([words(['stage', 'subprocess']), json2.Any({
			'kind':       json2.Any('namespace')
			'name':       json2.Any('subprocess')
			'attributes': json2.Any({
				'run':          callback('compile_library', view(c), 'completed')
                'check_output': callback('compile_library', view(c), 'completed_stdout')
			})
		})]),
		json2.Any([words(['stage', 'build_lavapipe']), callback('build_lavapipe', view(c), 'path')]),
		json2.Any([words(['stage', 'build_venus']), callback('build_venus', view(c), 'paths')]),
		json2.Any([words(['stage', 'sys', 'platform']), value(json2.Any('linux'))]),
	])
	public('_invoke', [patches, json2.Any('main'), json2.Any([]json2.Any{}),
		if expected.len > 0 { words(expected) } else { json2.Any(json2.Null{}) }])!
	if expected.len == 0 { equal(stage('package_files', [path(c.source)])!, member('before')!)! }
}

pub fn effect(name string, c map[string]json2.Any, args []json2.Any, keywords map[string]json2.Any) !json2.Any {
	mut result := json2.Any(json2.Null{})
	mut observation := json2.Any(json2.Null{})
	base := c['base'] or { json2.Any('') }.str()
	build := c['build'] or { json2.Any('') }.str()
	repo := c['repo'] or { json2.Any('') }.str()
	python := c['python'] or { json2.Any('') }.str()
	if name == 'compile_library' {
		command := args[0].as_array().map(it.str())
		if command[0] == 'sh' {
			equal(words(command), words(['sh', '-c', '. "$1/build-support/find-v.sh"; "$V" -version',
				'find-v', repo]))!
			result = json2.Any('fixture V compiler\n')
		} else if command[0] == python {
			equal(json2.Any(command[1]), json2.Any(repo + '/build-support/dota2/compile-v-compat.py'))!
			unit('assertIn', [json2.Any(command[2]), json2.Any({
				'tuple': words(['early', 'mmap32'])
			})])!
			equal(words(command[4..]), words(['--bare']))!
			unit_write(command[3], 'generated V artifact')!
		} else {
			unit('assertEqual', [json2.Any(command[0]), json2.Any('clang'),
				json2.Any('cached fixture must never fetch the network')])!
			unit_write(command[command.index('-o') + 1], 'compiled private shim')!
		}
	} else if name in ['build_lavapipe', 'build_venus'] {
		root := decoded(args[0])!
		work := decoded(args[1])!
		mode := if name == 'build_lavapipe' { 'mesa' } else { 'venus' }
		libc := read_bytes(root + '/lib/x86_64-linux-gnu/libc.so.6')!
		public('_append_member', [
			json2.Any(if name == 'build_lavapipe' { 'lavapipe_bases' } else { 'venus_bases' }),
			libc,
		])!
		equal(path(work), path(qemubuild.resolve(build + '/' + mode)!))!
		observation = json2.Any({
			'kind': json2.Any(if name == 'build_lavapipe' { 'lavapipe' } else { 'venus' })
			'libc': libc
		})
		if name == 'build_lavapipe' {
			library := base + '/lavapipe/libvulkan_lvp.so'
			unit_write(library, 'patched Lavapipe')!
			result = json2.Any(library)
		} else {
			library := base + '/venus/libvulkan_virtio.so'
			manifest := base + '/venus/virtio_icd.json'
			unit_write(library, 'x86-64 Venus')!
			unit_write(manifest, json_dump(json2.Any({
				'file_format_version': json2.Any('1.0.0')
				'ICD':                 json2.Any({
					'library_path': json2.Any('/usr/lib/x86_64-linux-gnu/libvulkan_virtio.so')
					'api_version':  json2.Any('1.3.305')
				})
			}))!)!
			result = words([library, manifest])
		}
	} else if name == 'changed_digest' {
		filename := decoded(args[0])!
		if filename == c['target']!.str() {
			result = json2.Any(c['character']!.str().repeat(64))
		} else {
			result = request({
				'kind':      json2.Any('call')
				'target':    c['fallback']!
				'arguments': json2.Any(args)
			})!
		}
	} else {
		return error('Unknown Vulkan fixture effect: ' + name)
	}
	mut response := {
		'result': result
	}
	if observation !is json2.Null { response['observation'] = observation }
	return json2.Any(response)
}
