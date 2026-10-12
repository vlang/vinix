// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import boothost
import cachecli
import crypto.sha256
import hosttest
import json2
import os

pub struct PreparedBoot {
pub:
	jars string
	manifest ah.Value
}

fn replace_file(source string, destination string) ! {
	if C.rename(source.str, destination.str) != 0 { return os.error_posix() }
}

pub fn boot_download(record ah.Value, directory string) !string {
	row := record.object()
	target := directory + '/' + ah.field(row, 'filename').text()
	if !os.exists(target) {
		temporary := target + '.part'
		defer { if os.exists(temporary) { os.rm(temporary) or {} } }
		probe_command(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3', '--output', temporary, ah.field(row, 'url').text()], false, '')!
		if digest(temporary)! != ah.field(row, 'sha256').text() { return error('bootclasspath input checksum mismatch: ' + os.file_name(target)) }
		replace_file(temporary, target)!
	}
	if !os.is_file(target) || os.is_link(target) { return error('bootclasspath input checksum mismatch: ' + os.file_name(target)) }
	if digest(target)! != ah.field(row, 'sha256').text() { return error('bootclasspath input checksum mismatch: ' + os.file_name(target)) }
	return target
}

// A new native producer deliberately gets a new cache identity. Every source
// that can change its archive, subprocess or receipt behavior participates.
pub fn boot_cache_identity() !ah.Value {
	mut paths := ['tests/native-android-tools/main.v', 'build-support/compile-v-module', 'tests/linuxkpi/generate_module.v', 'build-support/find-v.sh']
	for directory in ['tests/native-android-tools/androidtools', 'build-support/android/boothost', 'build-support/android/androidhost', 'tests/native-generators/generators', 'tests/linuxkpi/hosttest', 'tools/sourcecommand', 'build-support/cachecli', 'build-support/cachekey', 'build-support/tarcore', 'build-support/tarstream'] { closure(directory, mut paths)! }
	paths.sort()
	mut data := 'vinix-native-android-bootclasspath-v1\x00'.bytes()
	data << ah.encode(boothost.constants()['INPUTS']!).bytes()
	mut records := []ah.Value{}
	for path in paths {
		contents := os.read_bytes(root() + '/' + path)!
		data << u8(0); data << path.bytes(); data << u8(0); data << contents.len.str().bytes(); data << u8(0); data << contents
		records << ah.Value({'path': ah.Value(path), 'size': ah.Value(contents.len), 'sha256': ah.Value(sha256.sum(contents).hex())})
	}
	return ah.Value({'key': ah.Value(sha256.sum(data).hex()), 'sources': ah.Value(records)})
}

pub fn prepare_boot(build_dir string, java string) !PreparedBoot {
	c := boothost.constants()
	os.mkdir_all(build_dir)!
	downloads := build_dir + '/downloads'
	os.mkdir_all(downloads)!
	mut archives := []string{}
	for record in c['INPUTS']!.items() { archives << boot_download(record, downloads)! }
	key := ah.field(boot_cache_identity()!.object(), 'key').text()
	cache := build_dir + '/bootclasspath-runtime-manifest.json'
	jars := build_dir + '/jars'
	if os.is_file(cache) {
		previous := cached_boot(jars, cache) or { ah.Value(json2.null) }
		if ah.field(previous.object(), 'input_key').text() == key { return PreparedBoot{jars, previous} }
	}
	work := build_dir + '/work'
	if os.exists(work) { hosttest.remove_work_dir(work)! }
	os.mkdir(work)!
	raw := work + '/core-all_classes.jar'
	extract_member(archives[1], c['JAVA_CLASS_JAR']!.text(), raw)!
	version := boothost.unicode_strip(probe_command([java, '-cp', archives[2], 'com.android.tools.r8.D8', '--version'], true, '')!)
	next := build_dir + '/jars.next'
	if os.exists(next) { hosttest.remove_work_dir(next)! }
	destination := next + '/' + c['BOOT_DIRECTORY']!.text()
	os.mkdir_all(destination)!
	mut files := []ah.Value{}
	for value in c['BOOT_JARS']!.items() {
		cachecli.checkpoint()!
		name := value.text()
		original := work + '/' + name
		extract_member(archives[0], c['BOOT_DIRECTORY']!.text() + '/' + name, original)!
		before := jar_info(original)!
		inputs := work + '/' + name + '.classes.jar'
		class_subset(raw, before.classes, inputs)!
		directory := work + '/' + name + '.dex'
		os.mkdir(directory)!
		mut arguments := [java, '-cp', archives[2], 'com.android.tools.r8.D8']
		arguments << c['COMPILER_ARGUMENTS']!.items().map(it.text())
		arguments << ['--lib', raw, '--output', directory, inputs]
		probe_command(arguments, false, '')!
		output := destination + '/' + name
		package_boot_jar(original, directory, output)!
		generated := jar_info(output)!
		if generated.callsites != 0 || before.classes.any(it !in generated.classes) { return error('desugared bootclasspath lost classes or retained bootstrap calls: ' + name) }
		files << ah.Value({'path': ah.Value(c['BOOT_DIRECTORY']!.text() + '/' + name), 'sha256': ah.Value(digest(output)!), 'size': ah.Value(os.stat(output)!.size), 'original_sha256': ah.Value(digest(original)!), 'classes_before': ah.Value(before.classes.len), 'classes_after': ah.Value(generated.classes.len), 'bootstrap_callsites_before': ah.Value(before.callsites), 'bootstrap_callsites_after': ah.Value(generated.callsites)})
	}
	manifest := ah.Value({'format': ah.Value(1), 'input_key': ah.Value(key), 'compiler': ah.Value(version), 'compiler_arguments': c['COMPILER_ARGUMENTS']!, 'inputs': c['INPUTS']!, 'files': ah.Value(files)})
	validate_boot_provenance(next, manifest, ah.Value(json2.null))!
	if os.exists(jars) { hosttest.remove_work_dir(jars)! }
	replace_file(next, jars)!
	os.write_file(cache + '.next', ah.encode(manifest) + '\n')!
	replace_file(cache + '.next', cache)!
	return PreparedBoot{jars, manifest}
}

fn cached_boot(jars string, cache string) !ah.Value {
	previous := read_value(cache)!
	validate_boot_provenance(jars, previous, ah.Value(json2.null))!
	return previous
}

pub fn stage_boot(build_dir string, overlay string, java string) !ah.Value {
	mut manifest := read_runtime(overlay, 'art')!.object()
	prepared := prepare_boot(build_dir, java)!
	provenance := prepared.manifest
	mut replaced := []string{}
	for record in ah.field(provenance.object(), 'files').items() { replaced << ah.field(record.object(), 'path').text() }
	mut records := []ah.Value{}
	for record in ah.field(manifest, 'files').items() { if ah.field(record.object(), 'path').text() !in replaced { records << record } }
	for value in ah.field(provenance.object(), 'files').items() {
		record := value.object()
		name := ah.field(record, 'path').text()
		target := ah.inside(overlay, ah.relative(ah.Value(name))!)!
		os.mkdir_all(os.dir(target))!
		// The private directory reserves a unique same-filesystem staging name.
		private := temporary_in(os.dir(target), '.vinix-art-java-')!
		defer { hosttest.remove_work_dir(private) or {} }
		temporary := private + '/payload'
		os.cp(prepared.jars + '/' + name, temporary)!
		if digest(temporary)! != ah.field(record, 'sha256').text() { return error('bootclasspath cache changed during staging: ' + name) }
		os.chmod(temporary, 0o644)!
		replace_file(temporary, target)!
		records << ah.Value({'path': ah.field(record, 'path'), 'sha256': ah.field(record, 'sha256'), 'size': ah.field(record, 'size')})
	}
	records.sort_with_compare(fn (a &ah.Value, b &ah.Value) int {
		left := ah.field(a.object(), 'path').text(); right := ah.field(b.object(), 'path').text()
		return if left < right { -1 } else if left > right { 1 } else { 0 }
	})
	manifest['files'] = ah.Value(records)
	manifest['bootclasspath'] = provenance
	target := overlay + '/art-runtime-manifest.json'
	os.write_file(target + '.next', ah.encode(ah.Value(manifest)) + '\n')!
	replace_file(target + '.next', target)!
	return read_runtime(overlay, 'art')!
}

fn archive_extension(directory string, output string, extension string, recursive bool) ! {
	mut paths := []string{}
	if recursive { paths = os.walk_ext(directory, extension) }
	else { for name in os.ls(directory)! { if name.ends_with(extension) { paths << directory + '/' + name } } }
	paths.sort_with_compare(fn (a &string, b &string) int {
		left := a.split('/'); right := b.split('/')
		for index in 0 .. if left.len < right.len { left.len } else { right.len } {
			if left[index] < right[index] { return -1 }; if left[index] > right[index] { return 1 }
		}
		return if left.len < right.len { -1 } else if left.len > right.len { 1 } else { 0 }
	})
	mut writer := ah.archive_writer(output)!
	defer { writer.close() or {} }
	for path in paths { writer.add(ah.ArchiveItem{name: if recursive { path[directory.trim_right('/').len + 1..] } else { os.file_name(path) }, data: os.read_bytes(path)!})! }
	writer.close()!
}

pub fn build_boot_probe(build_dir string, output string, java string, javac string) ! {
	prepare_boot(build_dir, java)!
	c := boothost.constants()
	directory := build_dir + '/probe'
	if os.exists(directory) { hosttest.remove_work_dir(directory)! }
	classes := directory + '/classes'; dex := directory + '/dex'
	os.mkdir_all(classes)!; os.mkdir(dex)!
	raw := directory + '/core-all_classes.jar'
	downloads := build_dir + '/downloads'
	extract_member(downloads + '/' + ah.field(c['INPUTS']!.items()[1].object(), 'filename').text(), c['JAVA_CLASS_JAR']!.text(), raw)!
	probe_command([javac, '--release', '8', '-d', classes, root() + '/tests/android/ArtBootProbe.java'], false, '')!
	inputs := directory + '/classes.jar'
	archive_extension(classes, inputs, '.class', true)!
	compiler := downloads + '/' + ah.field(c['INPUTS']!.items()[2].object(), 'filename').text()
	probe_command([java, '-cp', compiler, 'com.android.tools.r8.D8', '--release', '--min-api', '26', '--lib', raw, '--output', dex, inputs], false, '')!
	os.mkdir_all(os.dir(output))!
	archive_extension(dex, output, '.dex', false)!
	jar_info(output)!
}

pub fn boot_cli(argv []string) !int {
	args := parse_arguments(argv, ['--build-dir', '--art-runtime', '--java', '--build-probe', '--javac'], []string{}, []string{}, 0, 0, 'usage: art-bootclasspath --build-dir DIR --art-runtime OVERLAY [--java JAVA --build-probe JAR --javac JAVAC]')!
	build := hosttest.module_resolve(required_value(args, '--build-dir')!)!
	overlay := hosttest.module_resolve(required_value(args, '--art-runtime')!)!
	java := args.value('--java', os.getenv_opt('VINIX_ANDROID_BUILD_JAVA') or { 'java' })
	manifest := stage_boot(build, overlay, java)!
	if '--build-probe' in args.options { build_boot_probe(build, hosttest.module_resolve(args.value('--build-probe', ''))!, java, args.value('--javac', os.getenv_opt('VINIX_ANDROID_BUILD_JAVAC') or { 'javac' }))! }
	mut names := []string{}
	for record in ah.field(ah.field(manifest.object(), 'bootclasspath').object(), 'files').items() { names << ah.field(record.object(), 'path').text() }
	println('Desugared ART boot libraries; ' + names.join(', '))
	return 0
}
