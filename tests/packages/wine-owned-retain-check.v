// SPDX-License-Identifier: GPL-2.0-or-later
// Disposable controls: detach every mutated file before writing it.
module main
import os
import json2
import crypto.sha256
import tests.packages.wineheaders

$if macos {
	#include <sys/clonefile.h>
	fn C.clonefile(&char, &char, i32) i32
}
fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }
fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn replace(path string, data string) ! {
	if os.exists(path) || os.is_link(path) { os.rm(path)! }
	os.write_file(path, data)!
}
fn clone_tree(source string, destination string, prepared bool) ! {
	os.mkdir_all(destination)!
	for path in os.walk_ext(source, '', hidden: true) {
		if !os.is_file(path) { continue }
		to := destination + path[source.len..]
		os.mkdir_all(os.dir(to))!
		if prepared || path.ends_with('/sources-before.txt') || path.ends_with('/sources-built.txt')
			|| path.ends_with('/clang-headers.json') || path.ends_with('/clang-resource.log')
			|| path.ends_with('/clang-resource.log.argv.json') || path.ends_with('/cc.log.argv.json') {
			$if macos {
				if C.clonefile(path.str, to.str, 0) == 0 { continue }
			}
			os.cp(path, to)!
		} else { os.symlink(path, to)! }
	}
}
fn remap(run string, prepared string, copied string) ! {
	mut declaration := read_map(run + '/declaration.json')!
	declaration['prepared'] = copied
	replace(run + '/declaration.json', json2.encode(declaration))!
	for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] {
		old := read_map(run + '/' + name)!
		mut mapped := map[string]string{}
		for path, hash in old { mapped[if path.starts_with(prepared + '/') { copied + path[prepared.len..] } else { path }] = hash }
		replace(run + '/' + name, json2.encode(mapped))!
	}
}
fn reseal(run string, prepared string, changed []string) ! {
	mut outputs := read_map(prepared + '/outputs.json')!
	for name in changed { outputs[name] = digest(prepared + '/' + name)! }
	replace(prepared + '/outputs.json', json2.encode(outputs))!
	for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] {
		mut inputs := read_map(run + '/' + name)!
		for file in [...changed, 'outputs.json'] { inputs[prepared + '/' + file] = digest(prepared + '/' + file)! }
		replace(run + '/' + name, json2.encode(inputs))!
	}
}

fn native_resource(run string, program string, kind string) !string {
	directory := run + '/build-' + program
	mut changed := ''
	mut expected := ''
	if kind == 'manifest' {
		snapshot := json2.decode[wineheaders.Snapshot](os.read_file(directory + '/clang-headers.json')!)!
		mut files := snapshot.files.clone()
		files.delete(files.keys()[0])
		replace(directory + '/clang-headers.json', json2.encode(wineheaders.Snapshot{directory: snapshot.directory, directories: snapshot.directories, files: files}))!
		changed = 'clang-headers.json'
		expected = 'Clang resource header tree changed'
	} else if kind == 'input' {
		snapshot := json2.decode[wineheaders.Snapshot](os.read_file(directory + '/clang-headers.json')!)!
		for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] {
			mut inputs := read_map(run + '/' + name)!
			inputs.delete(snapshot.files.keys()[0])
			replace(run + '/' + name, json2.encode(inputs))!
		}
		expected = 'Clang resource header input absent or changed'
	} else if kind == 'query' {
		replace(directory + '/clang-resource.log', os.read_file(directory + '/clang-resource.log')! + '\n')!
		changed = 'clang-resource.log'
		expected = 'invalid Clang resource directory response'
	} else if kind == 'flag' {
		mut args := json2.decode[[]string](os.read_file(directory + '/cc.log.argv.json')!)!
		for index, arg in args { if arg.starts_with('-resource-dir=') { args[index] = '-resource-dir=/other' } }
		replace(directory + '/cc.log.argv.json', json2.encode(args))!
		changed = 'cc.log.argv.json'
		expected = 'Clang resource compile selection differs'
	} else if kind == 'linked' {
		os.rename(directory + '/clang-headers.json', directory + '/manifest-original.json')!
		os.symlink(directory + '/manifest-original.json', directory + '/clang-headers.json')!
		expected = 'Clang resource evidence must be a bounded ordinary file'
	} else { return error('unknown native resource control') }
	if changed != '' {
		mut generated := read_map(run + '/generated-before-boot.json')!
		generated['build-' + program + '/' + changed] = digest(directory + '/' + changed)!
		replace(run + '/generated-before-boot.json', json2.encode(generated))!
	}
	return expected
}
fn admit(retainer string, run string, prepared string, out string, log string) !int {
	mut child := os.new_process(retainer)
	defer { child.close() }
	child.set_args([run, prepared, 'x86_64', out, '--owned-holder-death'])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	return child.code
}
fn check() ! {
	if os.args.len != 5 { return error('usage: CHECK RETAINER RUN PREPARED FRESH_OUTPUT') }
	retainer := os.real_path(os.args[1]); run := os.real_path(os.args[2]); prepared := os.real_path(os.args[3]); out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('fresh output required') }
	os.mkdir_all(out)!
	if admit(retainer, run, prepared, out + '/baseline', out + '/baseline.log')! != 0 { return error('owned baseline refused') }
	copy := out + '/copied'
	clone_tree(run, copy, false)!; clone_tree(prepared, copy + '/prepared', true)!; remap(copy, prepared, copy + '/prepared')!
	if admit(retainer, copy, copy + '/prepared', out + '/copied-retained', out + '/copied.log')! != 0 { return error('owned copied baseline refused') }
	mut refused := []string{}
	mut cases := ['package-flag', 'linked-mode', 'hidden-import', 'raw-outcome', 'deadline', 'missing-marker', 'duplicate-marker', 'marker-cr', 'vm-memory',
		'resource-manifest', 'resource-input', 'resource-query', 'resource-flag', 'linked-resource']
	for program in ['guest', 'package']! {
		for kind in ['manifest', 'input', 'query', 'flag', 'linked']! { cases << program + '-resource-' + kind }
	}
	for name in cases {
		dir := out + '/' + name
		clone_tree(run, dir, false)!
		mut selected := prepared
		mut expected := ''
		if name in ['linked-mode', 'hidden-import'] || name.starts_with('resource-') || name == 'linked-resource' {
			selected = dir + '/prepared'
			clone_tree(prepared, selected, true)!; remap(dir, prepared, selected)!
		}
		if name.starts_with('guest-resource-') || name.starts_with('package-resource-') {
			parts := name.split('-')
			expected = native_resource(dir, parts[0], parts[2])!
		} else if name == 'package-flag' {
			file := 'build-package/v.log.argv.json'
			mut args := json2.decode[[]string](os.read_file(dir + '/' + file)!)!
			at := args.index('wine_kernel_lease')
			if at < 1 { return error('baseline kernel flag missing') }
			args.delete_many(at - 1, 2)
			replace(dir + '/' + file, json2.encode(args))!
			mut generated := read_map(dir + '/generated-before-boot.json')!
			generated[file] = digest(dir + '/' + file)!
			replace(dir + '/generated-before-boot.json', json2.encode(generated))!
			expected = 'V producer argv differs'
		} else if name == 'linked-mode' {
			os.rm(selected + '/owned-manager.json')!
			os.symlink(prepared + '/owned-manager.json', selected + '/owned-manager.json')!
			expected = 'owned Wine receipt requires captured ordinary files'
		} else if name == 'hidden-import' {
			mut before := read_map(selected + '/inputs-before-build.json')!
			keys := before.keys().filter(it.ends_with('/SDKSettings.json'))
			if keys.len != 1 { return error('baseline hidden SDK input missing') }
			before.delete(keys[0])
			for file in ['inputs-before-build.json', 'inputs-verified.json'] { replace(selected + '/' + file, json2.encode(before))! }
			reseal(dir, selected, ['inputs-before-build.json', 'inputs-verified.json'])!
			expected = 'compiler source input is absent or changed'
		} else if name == 'resource-manifest' {
			snapshot := json2.decode[wineheaders.Snapshot](os.read_file(selected + '/clang-headers.json')!)!
			mut files := snapshot.files.clone()
			files.delete(files.keys()[0])
			replace(selected + '/clang-headers.json', json2.encode(wineheaders.Snapshot{directory: snapshot.directory, directories: snapshot.directories, files: files}))!
			reseal(dir, selected, ['clang-headers.json'])!
			expected = 'Clang resource header tree changed'
		} else if name == 'resource-input' {
			snapshot := json2.decode[wineheaders.Snapshot](os.read_file(selected + '/clang-headers.json')!)!
			mut before := read_map(selected + '/inputs-before-build.json')!
			before.delete(snapshot.files.keys()[0])
			for file in ['inputs-before-build.json', 'inputs-verified.json'] { replace(selected + '/' + file, json2.encode(before))! }
			reseal(dir, selected, ['inputs-before-build.json', 'inputs-verified.json'])!
			expected = 'Clang resource header input absent or changed'
		} else if name == 'resource-query' {
			file := 'logs/clang-resource.log'
			replace(selected + '/' + file, os.read_file(selected + '/' + file)! + '\n')!
			reseal(dir, selected, [file])!
			expected = 'invalid Clang resource directory response'
		} else if name == 'resource-flag' {
			file := 'logs/cc.log.argv.json'
			mut args := json2.decode[[]string](os.read_file(selected + '/' + file)!)!
			for index, arg in args { if arg.starts_with('-resource-dir=') { args[index] = '-resource-dir=/other' } }
			replace(selected + '/' + file, json2.encode(args))!
			reseal(dir, selected, [file])!
			expected = 'Clang resource compile selection differs'
		} else if name == 'linked-resource' {
			os.rm(selected + '/clang-headers.json')!
			os.symlink(prepared + '/clang-headers.json', selected + '/clang-headers.json')!
			expected = 'Clang resource evidence must be a bounded ordinary file'
		} else if name == 'deadline' {
			for file in ['guest-outcome.json', 'result.json'] {
				mut result := json2.decode[map[string]json2.Any](os.read_file(dir + '/' + file)!)!
				result['seconds'] = json2.Any(600)
				replace(dir + '/' + file, json2.encode(result))!
			}
			expected = 'owned holder raw/final outcome or deadline differs'
		} else if name == 'raw-outcome' {
			mut raw := json2.decode[map[string]json2.Any](os.read_file(dir + '/guest-outcome.json')!)!
			raw['passed'] = json2.Any(false)
			replace(dir + '/guest-outcome.json', json2.encode(raw))!
			expected = 'owned holder raw/final outcome or deadline differs'
		} else if name == 'vm-memory' {
			mut args := json2.decode[[]string](os.read_file(dir + '/boot/qemu-0.argv.json')!)!
			at := args.index('-m'); args[at + 1] = '1024'
			replace(dir + '/boot/qemu-0.argv.json', json2.encode(args))!
			expected = 'Wine guest memory command differs'
		} else {
			marker := 'HWTEST INFO Wine holder-SIGKILL reaped9 manager-adopted kernel-lease-busy PASS'
			text := os.read_file(dir + '/boot/serial.log')!
			changed := if name == 'missing-marker' { text.replace(marker, 'omitted holder marker') }
				else if name == 'duplicate-marker' { text + '\n' + marker + '\n' }
				else { text.replace(marker, marker.replace('holder-SIGKILL', 'holder-\rSIGKILL')) }
			replace(dir + '/boot/serial.log', changed)!
			expected = 'missing or duplicated exact marker'
		}
		status := admit(retainer, dir, selected, out + '/retained-' + name, out + '/' + name + '.log')!
		if status == 0 || os.exists(out + '/retained-' + name) || !os.read_file(out + '/' + name + '.log')!.contains(expected) { return error('owned control failed at wrong gate: ' + name) }
		refused << name
	}
	os.write_file(out + '/result.json', json2.encode({'baseline': json2.Any(true), 'copied_baseline': true, 'refused': refused}))!
	println('WINE OWNED RETENTION CONTROLS PASS real baseline copied baseline twenty-four exact refusals')
}
fn main() { check() or { eprintln(err); exit(1) } }
