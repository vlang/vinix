// SPDX-License-Identifier: GPL-2.0-or-later
module main

import io
import json2
import os
import strconv
import tarcore
import tarstream
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const config = 'etc/vinix-packages/config.json'
const declaration = 'usr/share/vinix-packages/applications.json'
const repositories = 'usr/share/vinix-packages/repositories'

fn command(argv []string) (int, string) {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn checked(argv []string) ! {
	code, output := command(argv)
	if code != 0 { return error(argv[0] + ': ' + output) }
}

fn repair_checksum(mut header []u8) {
	for index in 148 .. 156 { header[index] = ` ` }
	mut sum := i64(0)
	for byte in header { sum += i64(byte) }
	text := strconv.format_int(sum, 8)
	for index in 148 .. 154 { header[index] = `0` }
	for index, byte in text { header[154 - text.len + index] = byte }
	header[154] = 0
}

fn rewrite_archive(archive string, scenario string) ! {
	mut reader := tarstream.open_plain(archive)!
	defer { reader.close() }
	changed := archive + '.changed'
	mut writer := tarcore.create_stream(changed)!
	defer { writer.close() }
	mut parent := tarcore.Member{}
	for {
		mut member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name == './etc/vinix-packages' && scenario in ['missing-parent', 'late-parent']! {
			parent = member
			continue
		}
		if member.name == './' + config {
			match scenario {
				'legacy-file' { member.kind = 0 }
				'contiguous-file' { member.kind = `7` }
				'pax-path' {
					field := ' path=${member.name}\n'
					line := (field.len + 2).str() + field
					writer.add(tarcore.Member{name: 'extended', kind: `x`, size: line.len}, line.bytes())!
					member.name = './ignored-config.json'
				}
				else {}
			}
		}
		mut header := tarcore.header(member)!
		if member.name == './' + config && scenario in ['non-ustar-header', 'spaced-size']! {
			if scenario == 'non-ustar-header' { header[257] = 0 }
			else { header[124] = ` ` }
			repair_checksum(mut header)
		}
		writer.write(header)!
		reader.copy_to(mut writer)!
		writer.padding(member.size)!
	}
	if scenario == 'late-parent' { writer.add(parent, []u8{})! }
	writer.finish()!
	writer.close_checked()!
	os.rename(changed, archive)!
}

fn copy_gzip_bytes(source string, destination string, mode string, count i64) ! {
	mut input := os.open(source)!
	defer { input.close() }
	mut output := os.open_file(destination, mode)!
	defer { output.close() }
	io.copy_n(mut output, mut input, count)!
}

fn change_gzip(path string, scenario string) ! {
	match scenario {
		'concatenated-gzip-prefix', 'concatenated-gzip-suffix' {
			extra := path + '.extra'
			prefix := scenario == 'concatenated-gzip-prefix'
			os.write_file(extra, if prefix { '' } else { 'second gzip member' })!
			checked(['gzip', '-n', extra])!
			second := extra + '.gz'
			input_path := if prefix { path } else { second }
			copy_gzip_bytes(input_path, if prefix { second } else { path }, 'a',
				i64(os.file_size(input_path)))!
			if prefix { os.rename(second, path)! } else { os.rm(second)! }
		}
		'trailing-gzip-bytes' {
			mut file := os.open_file(path, 'a')!
			defer { file.close() }
			file.write_string('trailing bytes')!
		}
		'bad-gzip-crc', 'bad-gzip-size' {
			offset := if scenario == 'bad-gzip-crc' { i64(-8) } else { i64(-4) }
			mut file := os.open_file(path, 'r+')!
			defer { file.close() }
			file.seek(offset, .end)!
			mut byte := []u8{len: 1}
			if file.read(mut byte)! != 1 { return error('cannot read gzip fixture trailer') }
			byte[0] ^= 1
			file.seek(offset, .end)!
			if file.write(byte)! != 1 { return error('cannot change gzip fixture trailer') }
		}
		'truncated-gzip-trailer' {
			short := path + '.short'
			copy_gzip_bytes(path, short, 'w', i64(os.file_size(path)) - 4)!
			os.rename(short, path)!
		}
		else {}
	}
}

fn append_case_shadow(archive string, root string, work string, scenario string) ! {
	publisher := os.ls(root + '/' + repositories)!
	if publisher.len != 1 { return error('case-shadow fixture requires one signed repository') }
	repository := repositories + '/' + publisher[0]
	mut original := repository + '/index.json'
	mut shadow := repository + '/Index.json'
	if scenario == 'case-shadow-object' {
		objects := os.ls(root + '/' + repository + '/objects')!
		hash := objects.filter(it != it.to_upper())[0] or {
			return error('case-shadow fixture requires an object digest with letters')
		}
		original = repository + '/objects/' + hash
		shadow = repository + '/objects/' + hash.to_upper()
	}
	// A separate source directory keeps the two tar spellings distinct even
	// when the filesystem used to assemble the fixture folds case.
	aliases := work + '/aliases'
	path := aliases + '/' + shadow
	os.mkdir_all(os.dir(path))!
	os.cp(root + '/' + original, path)!
	os.chmod(path, 0o644)!
	checked(['tar', '-rf', archive, '-C', aliases, './' + shadow])!
}

fn make_iso(root string, work string, scenario string) !string {
	tree := work + '/iso'
	os.mkdir_all(tree + '/boot')!
	archive := work + '/initramfs.tar'
	checked(['tar', '--format=ustar', '-cf', archive, '-C', root, '.'])!
	if scenario == 'duplicate' { checked(['tar', '-rf', archive, '-C', root, config])! }
	if scenario in ['case-shadow-index', 'case-shadow-object']! {
		append_case_shadow(archive, root, work, scenario)!
	}
	if scenario in ['missing-parent', 'late-parent', 'legacy-file', 'contiguous-file', 'pax-path',
		'non-ustar-header', 'spaced-size']! { rewrite_archive(archive, scenario)! }
	if scenario == 'wrong-compression' { checked(['bzip2', '-z', archive])! }
	else { checked(['gzip', '-n', archive])! }
	if scenario == 'nested-compression' {
		os.rename(archive + '.gz', archive)!
		checked(['gzip', '-n', archive])!
	}
	change_gzip(archive + '.gz', scenario)!
	suffix := if scenario == 'wrong-compression' { '.bz2' } else { '.gz' }
	os.rename(archive + suffix, tree + '/boot/initramfs.tar.gz')!
	iso := work + '/image.iso'
	checked(['xorriso', '-as', 'mkisofs', '-R', '-o', iso, tree])!
	return iso
}

fn prepare_fixture(architecture string, out string) ! {
	if architecture !in ['aarch64', 'x86_64']! { return error('unsupported fixture architecture') }
	os.mkdir(out, mode: 0o700)!
	root := out + '/staged'
	os.mkdir(root, mode: 0o755)!
	os.mkdir(out + '/bundle', mode: 0o755)!
	os.mkdir_all(out + '/payload/bin')!
	os.write_file(out + '/payload/bin/fixture', 'structural package fixture\n')!
	os.chmod(out + '/payload/bin/fixture', 0o755)!
	manifest := out + '/manifest.json'
	os.write_file(manifest, json2.encode(pkgcore.Package{id: 'receipt-fixture', version: '1.0.0',
		architecture: architecture, kind: 'native', name: 'Receipt fixture', license: 'MIT',
		entrypoint: 'bin/fixture'}))!
	pkgcore.pack(manifest, out + '/payload', out + '/publisher')!
	seed := out + '/fixture-seed'
	key := pkgcore.keygen(seed)!
	defer { os.rm(seed) or {} }
	mut release := pkgcore.publish_release(out + '/publisher', 'fixture', seed, 1,
		time.now().unix() + 86_400, out + '/bundle/fixture')!
	defer { release.close() }
	input := out + '/config.json'
	os.write_file(input, json2.encode(pkgcore.Config{architecture: architecture,
		repositories: [pkgcore.Repository{id: 'fixture', public_key: key, url: 'file:///' + repositories + '/fixture'}]}))!
	mut configuration := pkgcore.prepare_image_configuration(root, architecture, input)!
	defer { configuration.close() }
	mut bundle := configuration.prepare_repositories_in(out + '/bundle', out)!
	defer { bundle.close() }
	mut applications := configuration.prepare_applications(&bundle, ['receipt-fixture'])!
	defer { applications.close() }
	bundle.publish()!
	configuration.publish()!
	applications.publish(&bundle)!
	bundle.retire()!
}

fn run() ! {
	if os.args.len == 4 && os.args[1] == 'fixture' {
		return prepare_fixture(os.args[2], os.abs_path(os.args[3]))
	}
	if os.args.len != 5 {
		return error('usage: iso-package-receipt-check fixture ARCH NEW_INPUTS | RECEIPT_TOOL STAGED_PACKAGE_ROOT PLAN.json NEW_WORK')
	}
	tool := os.abs_path(os.args[1])
	source := os.abs_path(os.args[2])
	plan := os.abs_path(os.args[3])
	out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('expected a new output directory') }
	os.mkdir(out, mode: 0o700)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	for scenario in ['match', 'wrong-configuration', 'missing-declaration', 'wrong-object', 'wrong-signature', 'stale-index',
		'alias', 'duplicate', 'blocked-parent', 'search-only-parent', 'missing-parent', 'late-parent', 'legacy-file',
		'contiguous-file', 'pax-path', 'non-ustar-header', 'spaced-size', 'wrong-compression', 'nested-compression',
		'concatenated-gzip-prefix', 'concatenated-gzip-suffix', 'trailing-gzip-bytes', 'bad-gzip-crc',
		'bad-gzip-size', 'truncated-gzip-trailer', 'case-shadow-index', 'case-shadow-object']! {
		work := out + '/' + scenario
		root := work + '/root'
		os.mkdir_all(root)!
		checked(['cp', '-Rp', source + '/.', root])!
		bundle := root + '/' + repositories
		ids := os.ls(bundle)!
		if ids.len != 1 { return error('fixture requires one signed repository') }
		repository := bundle + '/' + ids[0]
		mut selection := plan
		mut diagnostic := ''
		match scenario {
			'wrong-configuration' {
				value := json2.decode[pkgcore.Config](os.read_file(root + '/' + config)!)!
				os.write_file(root + '/' + config, json2.encode(pkgcore.Config{...value, launch_user: 'receipt-check'}))!
				diagnostic = 'configuration differs'
			}
			'missing-declaration' {
				os.rm(root + '/' + declaration)!
				diagnostic = 'application declaration differs'
			}
			'wrong-object' {
				objects := os.ls(repository + '/objects')!
				if objects.len == 0 { return error('test release has no payloads') }
				os.write_file(repository + '/objects/' + objects[0], 'changed fixture object')!
				diagnostic = 'object'
			}
			'wrong-signature' {
				os.write_file(repository + '/index.sig', '0'.repeat(128) + '\n')!
				diagnostic = 'signature'
			}
			'stale-index' {
				mut record := json2.decode[json2.Any](os.read_file(plan)!)!.as_map()
				mut publisher := record['publishers']!.as_array()[0].as_map()
				publisher['sequence'] = json2.Any(publisher['sequence']!.int() + 1)
				record['publishers'] = json2.Any([json2.Any(publisher)])
				selection = work + '/stale-plan.json'
				os.write_file(selection, json2.encode(record))!
				diagnostic = 'signed repositories differ'
			}
			'alias' {
				original := root + '/' + config
				os.rename(original, original + '.saved')!
				os.symlink('config.json.saved', original)!
				diagnostic = 'invalid ISO package file'
			}
			'duplicate' { diagnostic = 'duplicate ISO package member' }
			'blocked-parent' {
				os.chmod(root + '/etc/vinix-packages', 0o700)!
				diagnostic = 'invalid ISO package directory'
			}
			'search-only-parent' {
				os.chmod(root + '/usr/share/vinix-packages', 0o711)!
				diagnostic = 'invalid ISO package directory'
			}
			'missing-parent', 'late-parent' { diagnostic = 'ISO package directory must precede its members' }
			'legacy-file', 'contiguous-file', 'pax-path' { diagnostic = 'unsupported boot USTAR member type' }
			'non-ustar-header' { diagnostic = 'ISO initramfs requires POSIX USTAR headers' }
			'spaced-size' { diagnostic = 'invalid boot USTAR mode or size' }
			'wrong-compression' { diagnostic = 'ISO initramfs must be gzip-compressed' }
			'nested-compression' { diagnostic = 'ISO initramfs requires POSIX USTAR headers' }
			'concatenated-gzip-prefix', 'concatenated-gzip-suffix', 'trailing-gzip-bytes' {
				diagnostic = 'data follows the ISO initramfs gzip member'
			}
			'bad-gzip-crc', 'bad-gzip-size' { diagnostic = 'invalid ISO initramfs gzip stream' }
			'truncated-gzip-trailer' { diagnostic = 'truncated ISO initramfs gzip stream' }
			'case-shadow-index', 'case-shadow-object' { diagnostic = 'invalid ISO repository member' }
			else {}
		}
		iso := make_iso(root, work, scenario)!
		code, output := command([tool, 'verify', iso, selection])
		os.write_file(work + '/verifier.log', output)!
		if scenario == 'match' {
			if code != 0 { return error('matching ISO refused: ' + output) }
			report := json2.decode[json2.Any](output)!.as_map()
			mut document := pkgprotocol.decode_deployment_document(os.read_file(root + '/' + declaration)!)!
			defer { document.close() }
			if report['iso_sha256']!.str() != pkgcore.hash_file(iso)!
				|| report['architecture']!.str() != document.architecture
				|| report['applications']!.as_array().map(it.str()) != document.packages
				|| report['publishers']!.as_array().len != 1 {
				return error('ISO receipt differs from the embedded inputs')
			}
			receipt := work + '/receipt.json'
			os.write_file(receipt, output)!
			arch := if document.architecture == 'aarch64' { 'arm64' } else { 'amd64' }
			checksums := '${pkgcore.hash_file(iso)!}  vinix-${arch}.iso\n' +
				'${pkgcore.hash_file(receipt)!}  vinix-packages-${arch}.json\n'
			check_code, check_output := command([tool, 'checksums', receipt])
			if check_code != 0 || check_output != checksums {
				return error('release checksums differ from the verified ISO and receipt: ' + check_output)
			}
		} else if code == 0 || !output.contains(diagnostic) {
			return error('unexpected ISO verification outcome for ${scenario}: ${output}')
		}
		println('ISO package receipt ${scenario} PASS')
	}
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
