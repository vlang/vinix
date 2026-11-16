// SPDX-License-Identifier: GPL-2.0-or-later
// Disposable controls: detach every mutated file before writing it.
module main
import os
import json2
import crypto.sha256
import tests.packages.wineheaders
import tests.packages.winecsource
import tests.packages.winehostimages

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
			|| path.ends_with('/clang-resource.log.argv.json') || path.ends_with('/cc.log.argv.json')
			|| path.ends_with('/cc.log') || path.ends_with('/c-discover.log')
			|| path.ends_with('/c-discover.log.argv.json') || path.ends_with('/c-inputs-before.json')
			|| path.ends_with('/c-inputs-verified.json') || path.contains('/link-replay/')
			|| path.ends_with('/link-inputs.tar') || path.ends_with('/link-proof.json')
			|| path.ends_with('/link-version.log') || path.ends_with('/link-version.log.argv.json')
			|| path.ends_with('/link-replay.log.argv.json') || path.ends_with('.images.json')
			|| path.ends_with('.environment.json') || path.ends_with('.dyld.log')
			|| path.ends_with('/host-images-before.json') || path.ends_with('/host-clang-version.log')
			|| path.ends_with('/host-linker-version.log') || path.ends_with('/host-clang-version.log.argv.json')
			|| path.ends_with('/host-linker-version.log.argv.json') || path.ends_with('/v-host-images-before.json')
			|| path.ends_with('/host-v-version.log') || path.ends_with('/host-v-version.log.argv.json')
			|| path.ends_with('/discover.log.argv.json') || path.ends_with('/v.log.argv.json') || path.ends_with('/host-controller.json') {
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
	if os.args.len !in [5, 6] || (os.args.len == 6 && os.args[5] !in ['--host-link-only', '--host-sdk-only', '--host-sdk-denied-only', '--host-read-only', '--partition=0/4', '--partition=1/4', '--partition=2/4', '--partition=3/4']) {
		return error('usage: CHECK RETAINER RUN PREPARED FRESH_OUTPUT [--host-link-only|--host-sdk-only|--host-sdk-denied-only|--host-read-only|--partition=N/4]')
	}
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
	cases << ['bridge-c-trace', 'bridge-c-manifest', 'guest-c-pin', 'package-c-command', 'guest-c-linked']
	cases << ['bridge-link-proof', 'bridge-link-response', 'bridge-link-linked', 'guest-link-output', 'package-link-argv']
	cases << ['bridge-host-baseline', 'bridge-host-environment', 'guest-host-trace', 'package-host-pin', 'guest-host-linked']
	cases << ['bridge-v-host-baseline', 'bridge-v-host-environment', 'guest-v-host-trace', 'package-v-host-pin', 'guest-v-host-linked']
	cases << ['bridge-host-binding', 'bridge-host-input', 'controller-host-binding', 'controller-host-input', 'controller-host-linked']
	link_cases := ['bridge-host-link-input', 'controller-host-link-input']
	sdk_cases := ['bridge-host-sdk-input', 'controller-host-sdk-input']
	denied_cases := ['bridge-host-sdk-denied-input', 'controller-host-sdk-denied-input']
	read_cases := ['bridge-host-read-input', 'controller-host-read-input']
	directory_cases := ['bridge-host-directory-input', 'controller-host-directory-input']
	metadata_cases := ['bridge-host-metadata-input', 'controller-host-metadata-input']
	query_cases := ['bridge-host-query-input', 'controller-host-query-input']
	if os.args.len == 6 && os.args[5] == '--host-link-only' { cases = link_cases.clone() }
	else if os.args.len == 6 && os.args[5] == '--host-sdk-only' { cases = sdk_cases.clone() }
	else if os.args.len == 6 && os.args[5] == '--host-sdk-denied-only' { cases = denied_cases.clone() }
	else if os.args.len == 6 && os.args[5] == '--host-read-only' { cases = read_cases.clone() }
	else {
		cases << link_cases
		cases << sdk_cases
		cases << denied_cases
		cases << read_cases
		cases << directory_cases
		cases << metadata_cases
		cases << query_cases
		// Four disjoint partitions cover the full fixed list. Every invocation
		// still requires both baselines and its original named refusal gates.
		if os.args.len == 6 {
			partition := os.args[5].all_after('=').all_before('/').int()
			mut selected := []string{}
			for index, name in cases { if index % 4 == partition { selected << name } }
			cases = selected.clone()
		}
	}
	for name in cases {
		dir := out + '/' + name
		clone_tree(run, dir, false)!
		mut selected := prepared
		mut expected := ''
		if name in ['linked-mode', 'hidden-import'] || name.starts_with('resource-') || name == 'linked-resource' || name.starts_with('bridge-c-') || name.starts_with('bridge-link-') || name.starts_with('bridge-host-') || name.starts_with('bridge-v-host-') {
			selected = dir + '/prepared'
			clone_tree(prepared, selected, true)!; remap(dir, prepared, selected)!
		}
		v_host := name.contains('-v-host-')
		if name in ['bridge-host-binding', 'controller-host-binding'] {
			file := if name.starts_with('bridge-') { selected + '/host-producer.json' } else { dir + '/host-controller.json' }
			mut binding := read_map(file)!
			binding['proof_sha256'] = 'bad'
			replace(file, json2.encode(binding))!
			if name.starts_with('bridge-') { reseal(dir, selected, ['host-producer.json'])! }
			else {
				mut generated := read_map(dir + '/generated-before-boot.json')!
				generated['host-controller.json'] = digest(file)!
				replace(dir + '/generated-before-boot.json', json2.encode(generated))!
			}
			expected = 'host build binding record differs'
		} else if name in ['bridge-host-input', 'controller-host-input', 'bridge-host-link-input', 'controller-host-link-input', 'bridge-host-sdk-input', 'controller-host-sdk-input', 'bridge-host-sdk-denied-input', 'controller-host-sdk-denied-input', 'bridge-host-read-input', 'controller-host-read-input', 'bridge-host-directory-input', 'controller-host-directory-input', 'bridge-host-metadata-input', 'controller-host-metadata-input', 'bridge-host-query-input', 'controller-host-query-input'] {
			bridge := name.starts_with('bridge-')
			binding := read_map(if bridge { selected + '/host-producer.json' } else { dir + '/host-controller.json' })!
			for file in if bridge { ['inputs-before-build.json', 'inputs-verified.json'] } else { ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] } {
				path := (if bridge { selected } else { dir }) + '/' + file
				mut inputs := read_map(path)!
				artifact := if name.ends_with('-link-input') {
					if bridge { '/host-link.json' } else { '/link-inputs.tar' }
				} else if name.ends_with('-query-input') { '/read-closed/query.json'
				} else if name.ends_with('-metadata-input') { '/read-closed/metadata-aliases.json'
				} else if name.ends_with('-directory-input') { '/read-closed/policy.sb'
				} else if name.ends_with('-read-input') { '/read-closed/receipt.json'
				} else if name.ends_with('-sdk-denied-input') { '/sdk-denied/receipt.json'
				} else if name.ends_with('-sdk-input') { '/sdk-graph.json' } else { '/host-build.json' }
				if binding['directory'] + artifact !in inputs { return error('host artifact omission fixture absent') }
				inputs.delete(binding['directory'] + artifact)
				replace(path, json2.encode(inputs))!
			}
			if bridge { reseal(dir, selected, ['inputs-before-build.json', 'inputs-verified.json'])! }
			expected = 'host build artifact input absent or changed'
		} else if name == 'controller-host-linked' {
			file := dir + '/host-controller.json'
			os.rename(file, file + '-original')!; os.symlink(file + '-original', file)!
			expected = 'host build evidence must be bounded and ordinary'
		} else if name in ['bridge-host-baseline', 'bridge-v-host-baseline'] {
			file := 'logs/' + if v_host { 'v-host-images-before.json' } else { 'host-images-before.json' }
			before := json2.decode[winehostimages.Baseline](os.read_file(selected + '/' + file)!)!
			replace(selected + '/' + file, json2.encode(winehostimages.Baseline{recorded_directory: before.recorded_directory, images: before.images[1..]}))!
			reseal(dir, selected, [file])!
			expected = if v_host { 'V host before-command receipts differ' } else { 'host image before-command receipts differ' }
		} else if name in ['bridge-host-environment', 'bridge-v-host-environment'] {
			file := 'logs/' + if v_host { 'v.log.environment.json' } else { 'cc.log.environment.json' }
			mut env := read_map(selected + '/' + file)!
			env[if v_host { 'VFLAGS' } else { 'CPATH' }] = '/unrecorded'
			replace(selected + '/' + file, json2.encode(env))!
			reseal(dir, selected, [file])!
			expected = 'host tool environment differs'
		} else if name in ['guest-host-linked', 'guest-v-host-linked'] {
			file := dir + '/build-guest/' + if v_host { 'v-host-images-before.json' } else { 'host-images-before.json' }
			os.rename(file, file + '-original')!
			os.symlink(file + '-original', file)!
			expected = 'host image evidence must be a bounded ordinary file'
		} else if name in ['guest-host-trace', 'package-host-pin', 'guest-v-host-trace', 'package-v-host-pin'] {
			is_trace := name.ends_with('-trace')
			file := if is_trace { 'build-guest/' } else { 'build-package/' } + if v_host { 'v.log' } else { 'cc.log' } + if is_trace { '.dyld.log' } else { '.images.json' }
			if is_trace {
				text := os.read_file(dir + '/' + file)!
				observed := winehostimages.trace(text)!
				path := observed[0].path
				lines := text.split_into_lines().filter(!it.ends_with(' ' + path) && !it.ends_with(': ' + os.file_name(path)))
				replace(dir + '/' + file, lines.join('\n') + '\n')!
				expected = 'host image observations differ'
			} else {
				mut images := json2.decode[[]winehostimages.Image](os.read_file(dir + '/' + file)!)!
				for index, image in images {
					if image.sha256 != '' { images[index] = winehostimages.Image{path: image.path, uuid: image.uuid, sha256: 'bad'}; break }
				}
				replace(dir + '/' + file, json2.encode(images))!
				expected = 'host image absent or changed from before-command probes'
			}
			mut generated := read_map(dir + '/generated-before-boot.json')!
			generated[file] = digest(dir + '/' + file)!
			replace(dir + '/generated-before-boot.json', json2.encode(generated))!
		} else if name.starts_with('bridge-link-') {
			if name == 'bridge-link-proof' {
				mut proof := json2.decode[map[string]json2.Any](os.read_file(selected + '/link-proof.json')!)!
				proof['archive_sha256'] = json2.Any('bad')
				replace(selected + '/link-proof.json', json2.encode(proof))!
				reseal(dir, selected, ['link-proof.json'])!
				expected = 'link proof binding differs'
			} else if name == 'bridge-link-response' {
				file := 'link-replay/link-inputs/response.txt'
				replace(selected + '/' + file, os.read_file(selected + '/' + file)! + '--plugin unrecorded\n')!
				reseal(dir, selected, [file])!
				expected = 'link replay input differs'
			} else {
				os.rm(selected + '/link-inputs.tar')!
				os.symlink(prepared + '/link-inputs.tar', selected + '/link-inputs.tar')!
				expected = 'link evidence must be a bounded ordinary file'
			}
		} else if name == 'guest-link-output' || name == 'package-link-argv' {
			file := if name == 'guest-link-output' { 'build-guest/link-replay/link-inputs/guest' } else { 'build-package/link-replay.log.argv.json' }
			if name == 'guest-link-output' {
				replace(dir + '/' + file, 'changed link output')!
				expected = 'link replay executable differs'
			} else {
				replace(dir + '/' + file, '["/opt/homebrew/bin/ld.lld","@different.txt"]')!
				expected = 'link replay argv or version differs'
			}
			mut generated := read_map(dir + '/generated-before-boot.json')!
			generated[file] = digest(dir + '/' + file)!
			replace(dir + '/generated-before-boot.json', json2.encode(generated))!
		} else if name.starts_with('bridge-c-') {
			if name == 'bridge-c-trace' {
				text := os.read_file(selected + '/logs/cc.log')!
				observed := winecsource.trace(text)!
				mut lines := text.split_into_lines()
				mut removed := false
				for index, line in lines {
					if !removed && line.starts_with('.') && line.ends_with(' ' + observed[0]) { lines[index] = 'omitted include'; removed = true }
				}
				if !removed { return error('baseline include observation missing') }
				replace(selected + '/logs/cc.log', lines.join('\n') + '\n')!
				reseal(dir, selected, ['logs/cc.log'])!
			} else {
				proof := json2.decode[winecsource.Proof](os.read_file(selected + '/c-inputs-before.json')!)!
				changed := winecsource.Proof{sources: proof.sources, includes: proof.includes[1..]}
				for file in ['c-inputs-before.json', 'c-inputs-verified.json'] { replace(selected + '/' + file, json2.encode(changed))! }
				reseal(dir, selected, ['c-inputs-before.json', 'c-inputs-verified.json'])!
			}
			expected = 'C closure include observations differ'
		} else if name == 'guest-c-pin' {
			proof := json2.decode[winecsource.Proof](os.read_file(dir + '/build-guest/c-inputs-before.json')!)!
			mut includes := proof.includes.clone()
			file := includes[0]
			includes[0] = winecsource.File{path: file.path, resolved: file.resolved, sha256: 'bad'}
			changed := winecsource.Proof{sources: proof.sources, includes: includes}
			mut generated := read_map(dir + '/generated-before-boot.json')!
			for receipt in ['c-inputs-before.json', 'c-inputs-verified.json'] {
				path := 'build-guest/' + receipt
				replace(dir + '/' + path, json2.encode(changed))!
				generated[path] = digest(dir + '/' + path)!
			}
			replace(dir + '/generated-before-boot.json', json2.encode(generated))!
			expected = 'C closure input target or bytes changed'
		} else if name == 'package-c-command' {
			file := 'build-package/c-discover.log.argv.json'
			mut args := json2.decode[[]string](os.read_file(dir + '/' + file)!)!
			args.insert(1, '-DUNRECORDED_INPUT=1')
			replace(dir + '/' + file, json2.encode(args))!
			mut generated := read_map(dir + '/generated-before-boot.json')!
			generated[file] = digest(dir + '/' + file)!
			replace(dir + '/generated-before-boot.json', json2.encode(generated))!
			expected = 'C closure discovery argv differs'
		} else if name == 'guest-c-linked' {
			file := dir + '/build-guest/c-inputs-before.json'
			os.rename(file, file + '-original')!
			os.symlink(file + '-original', file)!
			expected = 'C closure evidence must be a bounded ordinary file'
		} else if name.starts_with('guest-resource-') || name.starts_with('package-resource-') {
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
	println('WINE OWNED RETENTION CONTROLS PASS real baseline copied baseline ' + if os.args.len == 6 {
		if os.args[5] == '--host-link-only' { 'two host-link exact refusals' }
		else if os.args[5] == '--host-sdk-only' { 'two host-SDK exact refusals' }
		else { os.args[5] + ' exact refusals=' + cases.len.str() }
	} else { 'fifty-three exact refusals' })
}
fn main() { check() or { eprintln(err); exit(1) } }
