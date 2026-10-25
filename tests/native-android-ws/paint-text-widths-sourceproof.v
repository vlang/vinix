// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve exact Maps DEX/native API references and the primary AOSP contract.
module main

import crypto.sha256
import json2
import net.http
import os

const maps_hash = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
const aosp_revision = '1cdfff555f4a21f71ccc978290e2e212e2f8b168'

struct Receipt {
	args      []string
	exit_code int
	output    string
}

fn hash(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn checked(out string, name string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/' + name + '-receipt.json', json2.encode(Receipt{args, r.exit_code, r.output},
		prettify: true
	) + '\n') or { panic(err) }
	assert r.exit_code == 0, r.output
	return r.output
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 2, 'OUTPUT (fresh external directory)'
	out := os.abs_path(os.args[1])
	assert !os.exists(out), out
	os.mkdir_all(out + '/entries')!
	os.cp('tests/native-android-ws/paint-text-widths-sourceproof.v', out + '/author.v')!
	apk := os.abs_path('build/android-maps/GoogleMaps.apk')
	assert hash(apk) == maps_hash
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	objdump := '/opt/homebrew/opt/llvm/bin/llvm-objdump'
	unzip := '/usr/bin/unzip'
	tools_root := os.abs_path('build/android-framework/tools')
	mut jars := os.ls(tools_root)!.filter(it.ends_with('.jar'))
	jars.sort()
	assert jars.len > 0
	mut tools := map[string]string{}
	for path in [java, objdump, unzip] { tools[path] = hash(path) }
	for jar in jars { tools[tools_root + '/' + jar] = hash(tools_root + '/' + jar) }
	os.write_file(out + '/tools-before.json', json2.encode(tools, prettify: true) + '\n')!
	entries := {
		'classes2.dex':                '3754f7430a6083bdac5202b97965d55e16f1c31b44bdaf023472bdc61ee1efed'
		'classes3.dex':                'ff22b298e6a0730667aeb06dc52fc874e4eb4c6cf0e1f412f9578b603619c232'
		'lib/arm64-v8a/libgoogle3.so': '0fe77b9783e74f583be6df4a99914ff09899dfed185a33a968d09fdfa9719e33'
	}
	for entry, pin in entries {
		checked(out, 'extract-' + os.base(entry), [unzip, '-q', '-j', apk, entry, '-d',
			out + '/entries'])
		assert hash(out + '/entries/' + os.base(entry)) == pin, entry
	}
	for index, class_name in ['bkmg', 'bvsf'] {
		checked(out, 'disassemble-' + class_name, [java, '-cp', tools_root + '/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes', 'L' + class_name + ';', '-o',
			out + '/smali', out + '/entries/classes${index + 2}.dex'])
		text := os.read_file(out + '/smali/' + class_name + '.smali')!
		assert text.contains('Landroid/graphics/Paint;->getTextWidths(Ljava/lang/String;[F)I')
		if class_name == 'bvsf' {
			assert text.contains('Landroid/graphics/Paint;->getTextWidths([CII[F)I')
		}
	}
	native_path := out + '/entries/libgoogle3.so'
	native := os.read_bytes(native_path)!
	assert native[0xbfa3e..0xbfa3e + 14].bytestr() == 'getTextWidths\x00'
	assert native[0x12ea02..0x12ea02 + 23].bytestr() == '(Ljava/lang/String;[F)I'
	disassembly := checked(out, 'native-method-lookup', [objdump, '-d', '--no-show-raw-insn',
		'--start-address=0x1a1d450', '--stop-address=0x1a1d5d0', native_path])
	assert disassembly.contains('1a1d5a4:') && disassembly.contains('#0xa3e')
	assert disassembly.contains('1a1d5ac:') && disassembly.contains('#0xa02')
	os.write_file(out + '/native-method-lookup.txt', disassembly)!
	os.write_file(out + '/native-method-lookup.json', json2.encode({
		'name_vma':        '0xbfa3e'
		'name':            'getTextWidths'
		'descriptor_vma':  '0x12ea02'
		'descriptor':      '(Ljava/lang/String;[F)I'
		'xref_name':       '0x1a1d5a0-0x1a1d5a4'
		'xref_descriptor': '0x1a1d5a8-0x1a1d5ac'
		'resolver_call':   '0x1a1d5b0 -> 0x124f4b8'
	}, prettify: true) + '\n')!
	url := 'https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/' + aosp_revision + '/graphics/java/android/graphics/Paint.java'
	response := http.get(url)!
	assert response.status_code == 200
	source := response.body
	os.write_file(out + '/AOSP-Paint.java', source)!
	declarations := source.fields().join(' ')
	for signature in [
		'getTextWidths(char[] text, int index, int count, float[] widths)',
		'getTextWidths(CharSequence text, int start, int end, float[] widths)',
		'getTextWidths(String text, int start, int end, float[] widths)',
		'getTextWidths(String text, float[] widths)',
	] {
		assert declarations.contains(signature), signature
	}
	os.write_file(out + '/inputs.json', json2.encode({
		'apk':                apk
		'apk_sha256':         maps_hash
		'aosp_url':           url
		'aosp_revision':      aosp_revision
		'aosp_source_sha256': hash(out + '/AOSP-Paint.java')
	}, prettify: true) + '\n')!
	assert hash(apk) == maps_hash
	mut after_jars := os.ls(tools_root)!.filter(it.ends_with('.jar'))
	after_jars.sort()
	assert jars == after_jars
	for path, pin in tools {
		assert hash(path) == pin, path
	}
	os.write_file(out + '/tools-after.json', json2.encode(tools, prettify: true) + '\n')!
	mut pins := map[string]string{}
	for path in os.walk_ext(out, '') {
		if os.is_file(path) { pins[path.all_after(out + '/')] = hash(path) }
	}
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println(out + ' ' + hash(out + '/sha256.json'))
}
