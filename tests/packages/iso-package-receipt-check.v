// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
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

fn make_iso(root string, work string, duplicate bool) !string {
	tree := work + '/iso'
	os.mkdir_all(tree + '/boot')!
	archive := work + '/initramfs.tar'
	checked(['tar', '--format=ustar', '-cf', archive, '-C', root, '.'])!
	if duplicate { checked(['tar', '-rf', archive, '-C', root, config])! }
	checked(['gzip', '-n', archive])!
	os.rename(archive + '.gz', tree + '/boot/initramfs.tar.gz')!
	iso := work + '/image.iso'
	checked(['xorriso', '-as', 'mkisofs', '-R', '-o', iso, tree])!
	return iso
}

fn run() ! {
	if os.args.len != 5 { return error('usage: iso-package-receipt-check RECEIPT_TOOL STAGED_PACKAGE_ROOT PLAN.json NEW_WORK') }
	tool := os.abs_path(os.args[1])
	source := os.abs_path(os.args[2])
	plan := os.abs_path(os.args[3])
	out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('expected a new output directory') }
	os.mkdir(out, mode: 0o700)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	for scenario in ['match', 'wrong-configuration', 'missing-declaration', 'wrong-object', 'wrong-signature', 'stale-index',
		'alias', 'duplicate']! {
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
			else {}
		}
		iso := make_iso(root, work, scenario == 'duplicate')!
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
