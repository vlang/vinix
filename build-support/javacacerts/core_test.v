// SPDX-License-Identifier: GPL-2.0-or-later
module javacacerts

import crypto.sha256
import encoding.base64
import encoding.hex
import hosttest
import os

fn test_pem_decoder_padding_ignored_bytes_and_all_octets() {
	for input, expected in {
		'':                     ''
		'====':                 ''
		'YWJj':                 'abc'
		'YQ==':                 'a'
		'YQ===ignored':         'a'
		'Y=Q==':                'a'
		'YWI=':                 'ab'
		'YW=I=':                'ab'
		'YWJ=j':                'ab'
		'YWJj====':             'abc'
		'\x00Y !W\tJ\r\nj\xff': 'abc'
	} {
		assert decode_pem(input.bytes())! == expected.bytes(), input
	}
	for input in ['A', 'A===', 'AB', 'AB=', 'ABC', 'YWJjA', 'YQ=!', 'YWI'] {
		decode_pem(input.bytes()) or { continue }
		assert false, 'accepted incomplete base64: ${input}'
	}
	for length in 0 .. 1025 {
		payload := []u8{len: length, init: u8(index * 37)}
		assert decode_pem(base64.encode(payload).bytes())! == payload
	}
}

fn test_pem_blocks_empty_duplicates_and_unmatched_markers() {
	assert parse_pem('prefix\n${pem_begin}\nYWJj\n${pem_end}\n${pem_begin}${pem_end}${pem_begin}YQ==${pem_end}\n${pem_begin}YWI='.bytes())! == [
		'abc'.bytes(),
		[]u8{},
		'a'.bytes(),
	]
	assert parse_pem('${pem_end}\n${pem_begin}'.bytes())! == [][]u8{}
	assert parse_pem('${pem_begin}YQ==${pem_end}${pem_begin}YQ==${pem_end}'.bytes())! == [
		'a'.bytes(),
		'a'.bytes(),
	]
	parse_pem('${pem_begin}A${pem_end}'.bytes()) or { return }
	assert false, 'invalid certificate was accepted'
}

fn test_password_utf16_including_astral_characters_and_invalid_utf8() {
	assert password_bytes('Aé猫💩𝄞\x00')!.hex() == '004100e9732bd83ddca9d834dd1e0000'
	assert password_bytes('\U00010000\U0010ffff')!.hex() == 'd800dc00dbffdfff'
	assert password_bytes('')! == []u8{}
	for invalid in ['\xff', '\xed\xa0\x80', '\xed\xbf\xbf', '\xc0\x80', '\xf4\x90\x80\x80', '\xe2\x82'] {
		password_bytes(invalid) or { continue }
		assert false, 'invalid password encoding was accepted'
	}
}

fn test_jks_wire_format_and_independent_openssl_digest() {
	work := hosttest.work_dir('', 'vinix-java-wire-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	store := build_jks(['abc'.bytes(), []u8{}], 'Aé猫💩')!
	assert store[..12].hex() == 'feedfeed0000000200000002'
	assert store[12..18].hex() == '000000020040'
	assert store[18..82].bytestr() == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
	assert store[82..101].hex() == '00000000000000000005582e35303900000003'
	assert store[101..104].bytestr() == 'abc'
	assert store[110..174].bytestr() == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
	assert store.len == 213
	// The digest prefix is specified independently of the writer. OpenSSL
	// supplies the SHA-1 implementation used to verify the JKS checksum.
	mut digest_input := hex.decode('004100e9732bd83ddca9')!
	digest_input << 'Mighty Aphrodite'.bytes()
	digest_input << store[..store.len - 20]
	os.write_file_array(work + '/input', digest_input)!
	result := hosttest.capture(['openssl', 'dgst', '-sha1', '-binary', '-out', work + '/digest',
		work + '/input'], '', 30, os.environ())!
	assert result.code == 0, result.stderr
	assert store[store.len - 20..] == os.read_bytes(work + '/digest')!
	assert build_jks([][]u8{}, 'changeit')!.len == 32
	mut encoded := []u8{}
	append_utf(mut encoded, 'x'.repeat(65535))!
	assert encoded[..2] == [u8(255), 255]
	append_utf(mut encoded, 'x'.repeat(65536)) or { return }
	assert false, 'oversized JKS string was accepted'
}

fn test_directory_sorting_file_filter_symlinks_and_read_errors() {
	work := hosttest.work_dir('', 'vinix-java-pem-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for name, payload in {
		'z.crt':       'YWJj'
		'a.crt':       'YQ=='
		'.hidden.crt': 'YWI='
		'ignored.CRT': 'A'
		'not.pem':     'A'
	} {
		os.write_file(work + '/' + name, '${pem_begin}\n${payload}\n${pem_end}')!
	}
	os.symlink(work + '/a.crt', work + '/b.crt')!
	assert read_certificates(work)! == ['ab'.bytes(), 'a'.bytes(), 'a'.bytes(), 'abc'.bytes()]
	os.mkdir(work + '/directory.crt')!
	read_certificates(work) or {
		os.rmdir(work + '/directory.crt')!
		os.mkdir(work + '/empty')!
		for directory in [work + '/empty', work + '/missing', work + '/not.pem'] {
			read_certificates(directory) or {
				assert err.msg() == 'no PEM certificates found in ${directory}'
				continue
			}
			assert false, 'empty input was accepted'
		}
		return
	}
	assert false, 'directory matching *.crt was accepted'
}

fn test_cli_arguments_errors_and_output_preservation() {
	tool := os.getenv('VINIX_JAVA_CACERTS_TOOL')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-java-cli-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	os.mkdir(work + '/certificates')!
	os.write_file(work + '/certificates/one.crt', '${pem_begin}\nYWJj\n${pem_end}\n')!
	for arguments in [
		[work + '/certificates', work + '/nested/result'],
		['--password', '💩', work + '/certificates', work + '/nested/result'],
		[work + '/certificates', '--pass=💩', work + '/nested/result'],
		['--password=💩', '--', work + '/certificates', work + '/nested/result'],
		['--password=x', '--password=💩', work + '/certificates', work + '/nested/result'],
	] {
		mut argv := [tool]
		argv << arguments
		result := hosttest.capture(argv, '', 30, os.environ())!
		assert result.code == 0 && result.stderr == '', result.stderr
		assert result.stdout == 'wrote 1 certificates to ${work}/nested/result\n'
		assert os.read_bytes(work + '/nested/result')! == build_jks(['abc'.bytes()], if arguments.len == 2 {
			'changeit'
		} else {
			'💩'
		})!
	}
	for arguments in [[]string{}, ['x'], ['x', 'y', 'z'], ['--password'], ['--unknown'], ['--=x'],
		['--password', '--help']] {
		mut argv := [tool]
		argv << arguments
		result := hosttest.capture(argv, '', 30, os.environ())!
		assert result.code == 2 && result.stdout == '' && result.stderr != ''
	}
	for flag in ['--help', '-h'] {
		result := hosttest.capture([tool, flag], '', 30, os.environ())!
		assert result.code == 0 && result.stdout.contains('Usage: java-cacerts') && result.stderr == ''
	}
	for password in ['-1', '-.5', '-1.25', '-'] {
		result := hosttest.capture([tool, work + '/certificates', work + '/nested/result', '--password',
			password], '', 30, os.environ())!
		assert result.code == 0 && result.stderr == ''
		assert os.read_bytes(work + '/nested/result')! == build_jks(['abc'.bytes()], password)!
	}
	os.write_file(work + '/certificates/one.crt', '${pem_begin}A${pem_end}')!
	os.write_file(work + '/sentinel', 'preserve')!
	for input in [work + '/certificates', work + '/missing'] {
		result := hosttest.capture([tool, input, work + '/sentinel'], '', 30, os.environ())!
		assert result.code == 1 && result.stdout == '' && result.stderr != ''
		assert os.read_file(work + '/sentinel')! == 'preserve'
	}
	result := hosttest.capture([tool, work + '/certificates', work + '/uncreated/result'], '', 30, os.environ())!
	assert result.code == 1 && !os.exists(work + '/uncreated')
}

fn test_guest_staging_rejects_wrong_target_and_cleans_failed_publication() {
	tool := os.getenv('VINIX_JAVA_STAGE_TOOL')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-java-stage-check-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for arguments in [['--arch', 'aarch64', '--staging', '/'],
		['--arch', 'invalid', '--staging', work], ['--arch', 'aarch64', '--staging', work + '/absent'],
		['--arch', 'aarch64', '--staging', work, '--arch', 'x86_64']] {
		mut argv := [tool]
		argv << arguments
		result := hosttest.capture(argv, '', 30, os.environ())!
		assert result.code == 2 && result.stdout == '' && result.stderr != ''
	}
	directory := work + '/usr/libexec/vinix-minecraft'
	os.mkdir_all(directory + '/java-cacerts')!
	os.write_file(directory + '/java-cacerts/sentinel', 'preserve')!
	os.write_file(directory + '/java-cacerts.py', 'retired wrapper')!
	wrong := hosttest.capture([tool, '--arch', 'aarch64', '--staging', work, '--cc',
		'x86_64-linux-musl-gcc'], '', 60, os.environ())!
	assert wrong.code == 1 && wrong.stdout == '' && wrong.stderr.contains('expected a aarch64')
	failed := hosttest.capture([tool, '--arch', 'aarch64', '--staging', work], '', 120, os.environ())!
	assert failed.code == 1 && failed.stdout == '' && failed.stderr.contains('cannot publish')
	assert os.read_file(directory + '/java-cacerts/sentinel')! == 'preserve'
	assert os.read_file(directory + '/java-cacerts.py')! == 'retired wrapper'
	assert os.ls(directory)!.sorted() == ['java-cacerts', 'java-cacerts.py']
}

fn test_frozen_production_store_and_java_password_verification() {
	root := os.getenv('VINIX_JAVA_REPO')
	if root == '' { return }
	certificates := read_certificates(root + '/build-aarch64-java/staging/usr/share/ca-certificates/mozilla')!
	assert certificates.len == 119
	store := build_jks(certificates, 'changeit')!
	assert sha256.sum(store).hex() == 'a25f4464a74cfba595a04f135b3ee2f6927479161baac152feef2161cc893bad'
	assert store == os.read_bytes(root + '/build-aarch64-java/staging/etc/ssl/certs/java/cacerts')!
	keytool := os.getenv('VINIX_JAVA_KEYTOOL')
	if keytool == '' { return }
	work := hosttest.work_dir('', 'vinix-java-keytool-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for password in ['changeit', 'Aé猫💩𝄞'] {
		os.write_file_array(work + '/cacerts', build_jks(certificates, password)!)!
		result := hosttest.capture([keytool, '-list', '-keystore', work + '/cacerts', '-storetype',
			'JKS', '-storepass', password], '', 90, os.environ())!
		assert result.code == 0 && result.stdout.contains('119 entries'), result.stderr
		wrong := hosttest.capture([keytool, '-list', '-keystore', work + '/cacerts', '-storetype',
			'JKS', '-storepass', 'wrong password'], '', 90, os.environ())!
		assert wrong.code != 0 && (wrong.stderr + wrong.stdout).contains('password was incorrect')
	}
}
