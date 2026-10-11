// SPDX-License-Identifier: GPL-2.0-or-later
module bundlehost

import bootpolicy
import os
import policyhost
import verityimage

fn invalid(message string) IError { return bootpolicy.InvalidBundle{message} }

pub struct Build {
pub:
	arch          string
	loader        string
	kernel        string
	initramfs     []string
	dtb           string
	output        string
	key           string
	certificate   string
	backend       string = 'sbsign'
	cmdline       string
	developer     bool
	verity_root   string
	verity_device string
	verity_count  u64
	verity_hash   string
}

pub fn sign(source string, destination string, key string, certificate string, backend string) ! {
	if backend == 'sbsign' {
		run(['sbsign', '--key', os.real_path(key), '--cert', os.real_path(certificate), '--output',
			destination, source])!
	} else if backend == 'osslsigncode' {
		run(['osslsigncode', 'sign', '-h', 'sha256', '-certs', os.real_path(certificate), '-key',
			os.real_path(key), '-in', source, '-out', destination])!
	} else {
		return invalid('invalid signing backend')
	}
}

pub fn verify_signature(loader string, certificate string, backend string) ! {
	if backend == 'sbsign' {
		run(['sbverify', '--cert', os.real_path(certificate), loader])!
	} else if backend == 'osslsigncode' {
		run(['osslsigncode', 'verify', '-CAfile', os.real_path(certificate), '-in', loader])!
	} else {
		return invalid('invalid signing backend')
	}
}

pub fn build(options Build) ! {
	architecture := bootpolicy.architecture(options.arch)!
	mut cmdline := bootpolicy.check_cmdline(options.cmdline, '')!
	mut token := ''
	fields := [options.verity_root != '', options.verity_device != '', options.verity_count != 0,
		options.verity_hash != '']
	if fields.any(it) {
		if fields.any(!it) {
			return invalid('verified block root requires --verity-root, --verity-device, --verity-data-blocks and --verity-root-hash')
		}
		token = verityimage.command_line(options.verity_device, options.verity_count, options.verity_hash) or { return invalid(err.msg()) }
		cmdline = bootpolicy.check_cmdline((cmdline + ' ' + token).trim_space(), token)!
	}
	output := absolute(options.output)
	if os.exists(output) || os.is_link(output) {
		return invalid('output already exists; choose a new bundle directory')
	}
	if !options.developer && (options.key == '' || options.certificate == '') {
		return invalid('signed mode requires --key and --certificate')
	}
	if options.developer && (options.key != '' || options.certificate != '') {
		return invalid('developer mode cannot also specify signing credentials')
	}
	if options.initramfs.len == 0 {
		return invalid('configuration is not a verified initramfs profile')
	}
	mut data := os.read_bytes(options.loader)!
	pe := bootpolicy.pe_info(data, options.arch)!
	if pe.signature_size != 0 {
		return invalid('loader input must be unsigned: enrollment must happen before signing')
	}
	staging := temporary(os.dir(output), '.vinix-verified-')!
	defer { retire(staging) }
	mkdirs(staging + '/boot')!
	mkdirs(staging + '/EFI/BOOT')!
	os.cp(options.kernel, staging + '/boot/vinix')!
	bootpolicy.check_kernel(staging + '/boot/vinix', options.arch)!
	mut hashes := []string{}
	for index, source in options.initramfs {
		path := staging + '/boot/root-' + index.str() + '.tar'
		os.cp(source, path)!
		hashes << bootpolicy.digest(path)!
	}
	if token != '' {
		os.cp(options.verity_root, staging + '/boot/verity-root.img')!
		verityimage.verify(staging + '/boot/verity-root.img', options.verity_count, options.verity_hash) or { return invalid(err.msg()) }
	}
	mut dtb_hash := ''
	if options.dtb != '' {
		os.cp(options.dtb, staging + '/boot/platform.dtb')!
		dtb_hash = bootpolicy.digest(staging + '/boot/platform.dtb')!
	}
	config := staging + '/boot/limine.conf'
	os.write_file(config, bootpolicy.config_text(bootpolicy.digest(staging + '/boot/vinix')!, hashes, cmdline, dtb_hash, token)!)!
	for index, byte in bootpolicy.digest(config)!.bytes() { data[int(pe.field) + index] = byte }
	loader := staging + '/EFI/BOOT/' + architecture.loader
	if options.developer {
		os.write_file_array(loader, data)!
	} else {
		unsigned := staging + '/enrolled.efi'
		os.write_file_array(unsigned, data)!
		sign(unsigned, loader, options.key, options.certificate, options.backend)!
		os.rm(unsigned)!
	}
	verify(staging, options.arch, options.certificate, options.backend, options.developer)!
	policyhost.command_checkpoint()!
	// Both paths share a parent, so a successful rename publishes the whole tree.
	if os.exists(output) || os.is_link(output) {
		return invalid('output already exists; choose a new bundle directory')
	}
	os.mv(staging, output)!
	println('Created ' + if options.developer {
		'UNAUTHENTICATED developer bundle: '
	} else {
		'signed UEFI bundle: '
	} + output)
	if !options.developer {
		println('Boot authentication requires UEFI Secure Boot enabled with this certificate trusted in firmware.')
	}
}

fn inventory(directory string, relative string, mut files map[string]bool) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		label := if relative == '' { name } else { relative + '/' + name }
		if os.is_link(path) { return invalid('bundle contains a symlink or special file: ' + path) }
		state := os.stat(path)!
		match state.get_filetype() {
			.directory { inventory(path, label, mut files)! }
			.regular { files[label] = true }
			else { return invalid('bundle contains a symlink or special file: ' + path) }
		}
	}
}

fn hash_text(value string) bool {
	return value.len == 128 && value.bytes().all(it.is_digit() || (it >= `a` && it <= `f`))
}

pub fn verify(bundle_arg string, arch string, certificate string, backend string, developer bool) ! {
	bundle := os.real_path(bundle_arg)
	mut files := map[string]bool{}
	inventory(bundle, '', mut files)!
	loader_relative := 'EFI/BOOT/' + bootpolicy.architecture(arch)!.loader
	loader := bootpolicy.regular_file(bundle + '/' + loader_relative)!
	data := os.read_bytes(loader)!
	pe := bootpolicy.pe_info(data, arch)!
	if developer {
		if pe.signature_size != 0 {
			return invalid('developer bundle unexpectedly contains a PE signature')
		}
	} else {
		if certificate == '' || pe.signature_size == 0 {
			return invalid('signed mode requires a signature and a separately trusted certificate')
		}
		verify_signature(loader, certificate, backend)!
	}
	config := bootpolicy.regular_file(bundle + '/boot/limine.conf')!
	if data[int(pe.field)..int(pe.field) + 128].bytestr().to_lower() != bootpolicy.digest(config)! {
		return invalid('configuration differs from the hash enrolled in the loader')
	}
	content := os.read_file(config)!
	mut kernel_hash := ''
	mut hashes := []string{}
	mut cmdline := ''
	mut cmdline_found := false
	mut dtb_hash := ''
	for line in content.split('\n') {
		if line.starts_with('    path: boot():/boot/vinix#') {
			kernel_hash = line.all_after('#')
		} else if line.starts_with('    module_path: boot():/boot/root-') {
			tail := line.all_after('    module_path: boot():/boot/root-')
			if !tail.contains('.tar#') || tail.all_before('.tar#') != hashes.len.str() {
				return invalid('initramfs modules must have consecutive indexes')
			}
			hashes << tail.all_after('.tar#')
		} else if line.starts_with('    cmdline: ') {
			cmdline = line['    cmdline: '.len..]
			cmdline_found = true
		} else if line.starts_with('    dtb_path: boot():/boot/platform.dtb#') {
			dtb_hash = line.all_after('#')
		}
	}
	if !hash_text(kernel_hash) || hashes.len == 0 || hashes.any(!hash_text(it)) || !cmdline_found || (dtb_hash != '' && !hash_text(dtb_hash)) {
		return invalid('configuration is not a verified initramfs profile')
	}
	tokens := cmdline.split_any(' \t\r\n').filter(it.starts_with(verityimage.token_prefix))
	if tokens.len > 1 { return invalid('duplicate verified-root command-line policy') }
	token := if tokens.len == 1 { tokens[0] } else { '' }
	if content != bootpolicy.config_text(kernel_hash, hashes, cmdline, dtb_hash, token)! {
		return invalid('unexpected configuration directive or command line')
	}
	mut expected := {
		loader_relative:    true
		'boot/limine.conf': true
		'boot/vinix':       true
	}
	mut artifacts := {
		'boot/vinix': kernel_hash
	}
	for index, hash in hashes {
		path := 'boot/root-' + index.str() + '.tar'
		expected[path] = true
		artifacts[path] = hash
	}
	if dtb_hash != '' {
		expected['boot/platform.dtb'] = true
		artifacts['boot/platform.dtb'] = dtb_hash
	}
	if token != '' { expected['boot/verity-root.img'] = true }
	if files != expected { return invalid('bundle contains missing or unexpected boot files') }
	bootpolicy.check_kernel(bundle + '/boot/vinix', arch)!
	for path, hash in artifacts {
		if bootpolicy.digest(bootpolicy.regular_file(bundle + '/' + path)!)! != hash {
			return invalid('boot artifact checksum mismatch: ' + path)
		}
	}
	if token != '' {
		policy := verityimage.parse_command_line(token) or { return invalid(err.msg()) }
		verityimage.verify(bootpolicy.regular_file(bundle + '/boot/verity-root.img')!, policy.data_blocks, policy.digest) or { return invalid(err.msg()) }
	}
}
