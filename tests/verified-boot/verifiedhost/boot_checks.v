// SPDX-License-Identifier: GPL-2.0-or-later
module verifiedhost

import bootpolicy
import bundlehost as bh
import hosttest
import os
import verityimage

fn boot_test(args []string) ! {
	mut specs := options(['--x86_64-loader', '--aarch64-loader'])
	specs << hosttest.Option{ name: '--backend', value: true, choices: ['sbsign', 'osslsigncode'] }
	parsed := bh.parse(args, specs, [], 0, 'Usage: test [--x86_64-loader EFI] [--aarch64-loader EFI] [--backend sbsign|osslsigncode]')!
	bh.run([bh.root() + '/build-support/run-v-tool.sh',
		bh.root() + '/tools/verified-boot/bootpolicy/core_test.v'])!
	work := temporary('vinix-boot-policy-')!
	defer { bh.retire(work) }
	for arch in ['x86_64', 'aarch64'] { bundle_regressions(work + '/' + arch, arch)! }
	println('PASS native bundle policy: both architectures, all artifacts, symlinks, root geometry and every hash level')
	if parsed.has('--x86_64-loader') || parsed.has('--aarch64-loader') {
		signature_integration(work, parsed)!
	} else {
		println('Real PE-signature integration skipped: supply --x86_64-loader and/or --aarch64-loader.')
	}
}

pub fn bundle_regressions(work string, arch string) ! {
	bh.mkdirs(work)!
	os.write_file_array(work + '/loader', pe(arch)!)!
	os.write_file_array(work + '/kernel', elf(arch)!)!
	os.write_file(work + '/root', 'first archive')!
	os.write_file(work + '/overlay', 'second archive')!
	output := work + '/bundle'
	original := bh.Build{
		arch:      arch
		loader:    work + '/loader'
		kernel:    work + '/kernel'
		initramfs: [
			work + '/root',
			work + '/overlay',
		]
		output:    output
		cmdline:   'quiet'
		developer: true
	}
	bh.build(original)!
	bh.verify(output, arch, '', 'sbsign', true)!
	require_invalid(fn [output, arch] () ! { bh.verify(output, arch, '', 'sbsign', false)! })!
	require_invalid(fn [original] () ! { bh.build(original)! })!
	for filename in ['boot/vinix', 'boot/root-0.tar', 'boot/root-1.tar', 'boot/limine.conf'] {
		path := output + '/' + filename
		bytes := os.read_bytes(path)!
		os.write_file_array(path, bytes_joined(bytes, 'tamper'.bytes()))!
		require_invalid(fn [output, arch] () ! { bh.verify(output, arch, '', 'sbsign', true)! })!
		os.write_file_array(path, bytes)!
	}
	os.write_file(output + '/EFI/BOOT/extra.efi', 'unexpected loader')!
	require_invalid(fn [output, arch] () ! { bh.verify(output, arch, '', 'sbsign', true)! })!
	os.rm(output + '/EFI/BOOT/extra.efi')!
	os.rm(output + '/boot/root-1.tar')!
	os.symlink(work + '/overlay', output + '/boot/root-1.tar')!
	require_invalid(fn [output, arch] () ! { bh.verify(output, arch, '', 'sbsign', true)! })!
	os.rm(output + '/boot/root-1.tar')!
	os.cp(work + '/overlay', output + '/boot/root-1.tar')!
	os.write_file_array(work + '/data', []u8{len: 129 * 4096, init: `x`})!
	metadata := verityimage.build(work + '/data', work + '/root-image', false)!
	block := bh.Build{ ...original, output: work + '/block-bundle', initramfs: [work + '/root'], verity_root: work + '/root-image', verity_device: '/dev/vda', verity_count: metadata.data_blocks, verity_hash: metadata.root_hash }
	bh.build(block)!
	bh.verify(block.output, arch, '', 'sbsign', true)!
	token := verityimage.command_line('/dev/vda', 129, metadata.root_hash)!
	assert os.read_file(block.output + '/boot/limine.conf')!.contains('cmdline: quiet ' + token + '\n')
	path := block.output + '/boot/verity-root.img'
	bytes := os.read_bytes(path)!
	for offset in [0, 129 * 4096, 130 * 4096, bytes.len - 1] {
		mut changed := bytes.clone()
		changed[offset] ^= 1
		os.write_file_array(path, changed)!
		require_invalid(fn [block, arch] () ! { bh.verify(block.output, arch, '', 'sbsign', true)! })!
	}
	os.write_file_array(path, bytes[..bytes.len - 1])!
	require_invalid(fn [block, arch] () ! { bh.verify(block.output, arch, '', 'sbsign', true)! })!
	os.write_file_array(path, bytes)!
	for missing in 0 .. 4 {
		incomplete := bh.Build{
			...block
			output:        work + '/incomplete'
			verity_root:   if missing == 0 {
				''
			} else {
				block.verity_root
			}
			verity_device: if missing == 1 { '' } else { block.verity_device }
			verity_count:  if missing == 2 {
				u64(0)
			} else {
				block.verity_count
			}
			verity_hash:   if missing == 3 { '' } else { block.verity_hash }
		}
		require_invalid(fn [incomplete] () ! { bh.build(incomplete)! })!
		assert !os.exists(incomplete.output)
	}
	for wrong in [
		bh.Build{ ...block, output: work + '/wrong-count', verity_count: 128 },
		bh.Build{ ...block, output: work + '/wrong-root', verity_hash: '0'.repeat(64) },
	] {
		require_invalid(fn [wrong] () ! { bh.build(wrong)! })!
		assert !os.exists(wrong.output)
	}
	for cmdline in [token + ' ' + token, 'x=' + token + ' ' + token, token + ' quiet'] {
		require_invalid(fn [cmdline, token] () ! { bootpolicy.check_cmdline(cmdline, token)! })!
	}
}

fn signature_integration(work string, parsed bh.Options) ! {
	for identity in ['trusted', 'other'] {
		bh.quiet(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256',
			'-subj', '/CN=Vinix test ' + identity, '-days', '1', '-addext',
			'extendedKeyUsage=codeSigning', '-keyout', work + '/' + identity + '.key', '-out',
			work + '/' + identity + '.crt'])!
	}
	backend := parsed.value('--backend', 'sbsign')
	for arch in ['x86_64', 'aarch64'] {
		if !parsed.has('--' + arch + '-loader') { continue }
		base := work + '/real-' + arch
		bh.mkdirs(base)!
		os.write_file_array(base + '/kernel', elf(arch)!)!
		os.write_file(base + '/root', 'root archive bytes authenticated before unpacking')!
		options := bh.Build{ arch: arch, loader: parsed.value('--' + arch + '-loader', ''), kernel: base + '/kernel', initramfs: [base + '/root'], output: base + '/bundle', cmdline: 'quiet', key: work + '/trusted.key', certificate: work + '/trusted.crt', backend: backend }
		bh.build(options)!
		require_failed(fn [options, work] () ! {
			bh.verify(options.output, options.arch, work + '/other.crt', options.backend, false)!
		})!
		path := options.output + '/EFI/BOOT/' + bootpolicy.architecture(arch)!.loader
		data := os.read_bytes(path)!
		field := int(bootpolicy.pe_info(data, arch)!.field)
		mut corrupt := data.clone()
		corrupt[field] = if corrupt[field] != `a` { `a` } else { `b` }
		os.write_file_array(path, corrupt)!
		require_failed(fn [options] () ! {
			bh.verify(options.output, options.arch, options.certificate, options.backend, false)!
		})!
		os.write_file_array(path, data)!
		for filename in ['boot/limine.conf', 'boot/vinix', 'boot/root-0.tar'] {
			artifact := options.output + '/' + filename
			saved := os.read_bytes(artifact)!
			os.write_file_array(artifact, bytes_joined(saved, 'tamper'.bytes()))!
			require_invalid(fn [options] () ! {
				bh.verify(options.output, options.arch, options.certificate, options.backend, false)!
			})!
			os.write_file_array(artifact, saved)!
		}
		bh.verify(options.output, arch, options.certificate, backend, false)!
		println('PASS ' + arch + ': real PE signature, wrong certificate, signed-field/config/kernel/initramfs tampering')
		mut block := []u8{len: 8192}
		for i, b in 'verified block contents'.bytes() { block[i] = b }
		os.write_file_array(base + '/block-data', block)!
		metadata := verityimage.build(base + '/block-data', base + '/block-image', false)!
		rooted := bh.Build{ ...options, output: base + '/block-root', verity_root: base + '/block-image', verity_device: '/dev/vda', verity_count: metadata.data_blocks, verity_hash: metadata.root_hash }
		bh.build(rooted)!
		root_image := rooted.output + '/boot/verity-root.img'
		saved := os.read_bytes(root_image)!
		mut changed := saved.clone()
		changed[0] ^= 1
		os.write_file_array(root_image, changed)!
		require_invalid(fn [rooted] () ! {
			bh.verify(rooted.output, rooted.arch, rooted.certificate, rooted.backend, false)!
		})!
		os.write_file_array(root_image, saved)!
		bh.verify(rooted.output, arch, rooted.certificate, backend, false)!
		println('PASS ' + arch + ': real PE signature binds block geometry and root; tampered block image rejected')
	}
}
