// SPDX-License-Identifier: GPL-2.0-or-later
// Import a prepared native OpenJDK and its runtime closure without installing it.
module main

import devcore
import json2
import os
import sourcecommand
import tests.development.referencecore

struct Receipt {
	schema int = 1
	architecture string
	overlay_source string
	jdk_source string
	readelf devcore.Pin
mut:
	files map[string]devcore.Pin
	links map[string]string
	cacerts_source devcore.Pin
	jdk_import_sha256 string
	sdk_sha256 string
	complete bool
}

fn copy_java(source string, target string, overlay string, jdk string, mut receipt Receipt) ! {
	if source.ends_with('.py') || source.ends_with('.pyc') || source.ends_with('.pyo') { return }
	st := os.lstat(source)!
	if st.mode & 0o6000 != 0 { return error('set-ID input refused: ' + source) }
	match st.get_filetype() {
		.directory {
			os.mkdir(target, mode: 0o700)!
			for name in os.ls(source)! { copy_java(source + '/' + name, target + '/' + name, overlay, jdk, mut receipt)! }
			os.chmod(target, int(st.mode & 0o777))!
		}
		.regular {
			os.cp(source, target)!
			os.chmod(target, int(st.mode & 0o777))!
			hash := devcore.file_hash(target)!
			if devcore.file_hash(source)! != hash { return error('Java input changed during copy') }
			receipt.files[source.all_after(overlay + '/')] = devcore.Pin{source, hash}
		}
		.symbolic_link {
			link := os.readlink(source)!
			receipt.links[source] = link
			// Alpine's standard trust-store alias is materialized from the
			// supplied overlay, never from the host's absolute /etc path.
			if source == jdk + '/lib/security/cacerts' && link == '/etc/ssl/certs/java/cacerts' {
				certs := overlay + link
				if os.lstat(certs)!.get_filetype() != .regular || !os.real_path(certs).starts_with(overlay + '/') {
					return error('Java trust store must be a contained ordinary file')
				}
				copy_java(certs, target, overlay, jdk, mut receipt)!
				receipt.cacerts_source = devcore.Pin{certs, devcore.file_hash(target)!}
			} else {
				resolved := os.real_path(source)
				if link.starts_with('/') || !os.exists(source) || (resolved != jdk && !resolved.starts_with(jdk + '/')) {
					return error('Java input link escapes its installation: ' + source)
				}
				os.symlink(link, target)!
			}
		}
		else { return error('unsupported Java input type: ' + source) }
	}
}

fn elf(path string) bool {
	mut file := os.open(path) or { return false }
	defer { file.close() }
	mut header := []u8{len: 4}
	return file.read(mut header) or { 0 } == 4 && header == [u8(0x7f), `E`, `L`, `F`]
}

fn stage() ! {
	if os.args.len == 2 && os.args[1] == '--help' {
		println('Usage: v run stage-java.v aarch64|x86_64 PREPARED-JAVA-OVERLAY JDK-DIRECTORY-NAME FRESH-STAGING')
		return
	}
	if os.args.len != 5 || os.args[1] !in ['aarch64', 'x86_64'] { return error('invalid arguments; use --help') }
	arch := os.args[1]
	if os.is_link(os.args[2]) || !os.is_dir(os.args[2]) { return error('Java overlay must be an ordinary directory') }
	name := os.args[3]
	if name == '' || name in ['.', '..'] || name.contains('/') || name.contains('\x00') { return error('JDK name must be one directory component') }
	overlay := os.real_path(os.args[2])
	if overlay == '/' { return error('the host filesystem root is not a prepared Java overlay') }
	jdk := overlay + '/usr/lib/jvm/' + name
	if os.is_link(jdk) || !os.is_dir(jdk) || !os.real_path(jdk).starts_with(overlay + '/') {
		return error('missing contained ordinary JDK installation')
	}
	requested := os.abs_path(os.args[4])
	out := os.real_path(os.dir(requested)) + '/' + os.base(requested)
	if out == overlay || out.starts_with(overlay + '/') { return error('staging must be outside its input closure') }
	runtime := overlay + '/lib/ld-musl-' + arch + '.so.1'
	if os.lstat(runtime)!.get_filetype() != .regular || !os.real_path(runtime).starts_with(overlay + '/') {
		return error('musl runtime must be a contained ordinary file')
	}
	readelf := os.find_abs_path_of_executable(arch + '-linux-musl-readelf')!
	devcore.fresh_directory(out)!
	mut receipt := Receipt{architecture: arch, overlay_source: overlay, jdk_source: jdk,
		readelf: devcore.Pin{readelf, devcore.file_hash(readelf)!}}
	manifest := out + '/reference-sdk.json'
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	root := out + '/sdk'
	for directory in [root, root + '/bin', root + '/lib', root + '/share'] { os.mkdir(directory, mode: 0o755)! }
	copy_java(jdk, root + '/share/jdk', overlay, jdk, mut receipt)!
	copy_java(runtime, root + '/lib/libc.so', overlay, jdk, mut receipt)!
	os.symlink('libc.so', root + '/lib/libc.musl-' + arch + '.so.1')!
	for tool in ['java', 'javac', 'jar'] { os.symlink('../share/jdk/bin/' + tool, root + '/bin/' + tool)! }
	// Inspect every JDK ELF, including libraries loaded by HotSpot at runtime.
	jdk_files := os.walk_ext(root + '/share/jdk', '', hidden: true)
	mut pending := jdk_files.filter(os.is_file(it) && !os.is_link(it) && elf(it))
	mut seen := map[string]bool{}
	for pending.len > 0 {
		path := pending.pop()
		result := sourcecommand.capture([readelf, '-d', path], devcore.environment(0), 30, 65536, unsafe { nil })!
		if result.status != 0 { return error('Java library inspection failed: ' + result.stderr) }
		for line in result.stdout.split_into_lines().filter(it.contains('(NEEDED)')) {
			library := line.all_after('[').all_before(']')
			if library == '' || library.contains('/') || library.contains('\x00') { return error('invalid runtime library name') }
			if seen[library] { continue }
			seen[library] = true
			if library == 'libc.so' || library == 'libc.musl-' + arch + '.so.1' { continue }
			// A library already inside the JDK stays at its original relative path.
			if jdk_files.any(os.base(it) == library && os.is_file(it)) { continue }
			mut source := ''
			for directory in [overlay + '/usr/lib', overlay + '/lib'] {
				candidate := directory + '/' + library
				if os.is_file(candidate) { source = os.real_path(candidate); break }
			}
			if source == '' || !source.starts_with(overlay + '/') { return error('missing contained Java runtime library: ' + library) }
			target := root + '/lib/' + library
			copy_java(source, target, overlay, jdk, mut receipt)!
			pending << target
		}
	}
	referencecore.options(root, 'java', arch)!
	for _, pin in receipt.files { devcore.verify(pin)! }
	for source, link in receipt.links { if os.readlink(source)! != link { return error('Java input alias changed during preparation') } }
	devcore.verify(receipt.readelf)!
	receipt.jdk_import_sha256 = devcore.tree_hash(root + '/share/jdk')!
	receipt.sdk_sha256 = devcore.tree_hash(root)!
	receipt.complete = true
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	println('Prepared Java reference SDK: ' + root)
}

fn main() { stage() or { eprintln(err); exit(1) } }
