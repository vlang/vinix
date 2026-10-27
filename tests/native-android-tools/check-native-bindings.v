// SPDX-License-Identifier: GPL-2.0-or-later
// Reject stale native bindings before compiling the complete JNI provider.
module main

import androidtools
import crypto.sha256
import os

fn rejects(spec string, smali string) bool {
	androidtools.native_ws_bindings(spec, smali) or { return true }
	return false
}

fn java_dispatch(source string, signature string, call string) bool {
	declaration := '.method public ' + signature + '\n'
	if !source.contains(declaration) || source.contains(' native ' + signature + '\n') { return false }
	return source.all_after(declaration).all_before('.end method').contains(call)
}

fn self_test() ! {
	work := os.join_path(os.temp_dir(), 'vinix-native-bindings-${os.getpid()}')
	if os.exists(work) { return error('fixture directory already exists: ' + work) }
	os.mkdir_all(work + '/android/widget')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/android/widget/Button.smali',
		'.class public Landroid/widget/Button;\n.super Landroid/widget/TextView;\n' +
		'.method protected native native_setText(JLjava/lang/String;)V\n.end method\n' +
		'.method public getText()Ljava/lang/CharSequence;\n.locals 1\n' +
		'invoke-super {p0}, Landroid/widget/TextView;->getText()Ljava/lang/CharSequence;\n' +
		'move-result-object v0\nreturn-object v0\n.end method\n')!
	good := 'android/widget/Button|native_setText|ws_set_text(e,this,p1)'
	generated := androidtools.native_ws_bindings(good, work)!
	assert generated.contains('Java_android_widget_Button_native_1setText__JLjava_lang_String_2')
	assert generated.contains('p0 i64, p1 voidptr')
	assert rejects(good + '\nandroid/widget/Button|getText|return nil', work)
	assert rejects('android/widget/Button|native_setText(I)V|return', work)
	assert rejects('android/widget/Missing|native_constructor|return 0', work)
	fixture := os.read_file(work + '/android/widget/Button.smali')!
	call := 'invoke-super {p0}, Landroid/widget/TextView;->getText()Ljava/lang/CharSequence;'
	assert java_dispatch(fixture, 'getText()Ljava/lang/CharSequence;', call)
	assert !java_dispatch(fixture.replace(call, 'const/4 v0, 0x0'), 'getText()Ljava/lang/CharSequence;', call)
	os.mkdir_all(work + '/android/atl')!
	task := '.class public final Landroid/atl/VinixBroadcast;\n.super Ljava/lang/Object;\n' +
		'.field public receiver:Landroid/content/BroadcastReceiver;\n' +
		'.field public context:Landroid/content/Context;\n.field public intent:Landroid/content/Intent;\n' +
		'.method static constructor <clinit>()V\n.locals 0\nreturn-void\n.end method\n' +
		'.method public constructor <init>()V\n.locals 0\nreturn-void\n.end method\n' +
		'.method public static getRegistrations()Ljava/util/List;\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method\n' +
		'.method public native run()V\n.end method\n'
	path := work + '/android/atl/VinixBroadcast.smali'
	binding := 'android/atl/VinixBroadcast|run|ws_broadcast_run(e,this)'
	os.write_file(path, task)!
	assert androidtools.native_ws_bindings(binding, work)!.contains('Java_android_atl_VinixBroadcast_run__')
	bridge := androidtools.framework_broadcast_run(task)!
	os.write_file(path, bridge)!
	assert !androidtools.native_ws_bindings(binding, work)!.contains('@[export:')
	os.write_file(path, bridge.replace('.locals 4', '.registers 5').replace('    iget-object', '\n    # disassembly whitespace\n    iget-object'))!
	assert !androidtools.native_ws_bindings(binding, work)!.contains('@[export:')
	assert rejects(binding.replace('ws_broadcast_run(e,this)', 'other(e,this)'), work)
	os.write_file(path, bridge.replace('const/4 v3, 0x1', 'const/4 v3, 0x0'))!
	assert rejects(binding, work)
	println('NATIVE-BINDINGS-SELF-PASS Java-dispatch-rejected exact-native-signature JNI-widths legacy-broadcast-export canonical-Java-bridge-only')
}

fn check(smali string, output string) ! {
	spec := os.read_file('build-support/android/nativews/bindings.txt')!
	mut failures := []string{}
	mut entries := 0
	for line in spec.split_into_lines() {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		entries++
		androidtools.native_ws_bindings(line, smali) or { failures << err.msg() }
	}
	if failures.len != 0 { return error(failures.join('\n')) }
	for name, signature in {'Button': 'getText()Ljava/lang/CharSequence;',
		'CompoundButton': 'getText()Ljava/lang/CharSequence;',
		'RadioButton': 'setText(Ljava/lang/CharSequence;)V'} {
		source := os.read_file(smali + '/android/widget/' + name + '.smali')!
		call := if name == 'RadioButton' {
			'invoke-virtual {p0, p1, v0}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;Landroid/widget/TextView$BufferType;)V'
		} else {
			'invoke-super {p0}, Landroid/widget/' + if name == 'Button' { 'TextView' } else { 'Button' } + ';->' + signature
		}
		assert java_dispatch(source, signature, call), 'Java text dispatch changed: ' + name
		assert !spec.contains('android/widget/' + name + '|' + signature.all_before('(') + '|')
	}
	generated := androidtools.native_ws_bindings(spec, smali)!
	if output != '' {
		if os.exists(output) { return error('output already exists: ' + output) }
		os.write_file(output, generated)!
	}
	println('NATIVE-BINDINGS-PASS entries=${entries} exports=${generated.count("\n@[export: ")}' +
		' spec_sha256=' + sha256.sum(spec.bytes()).hex() +
		' generated_sha256=' + sha256.sum(generated.bytes()).hex())
}

fn main() {
	if os.args.len > 3 {
		eprintln('usage: check-native-bindings [SMALI_DIR [GENERATED_V_OUTPUT]]')
		exit(2)
	}
	self_test() or { eprintln(err); exit(1) }
	if os.args.len > 1 {
		check(os.abs_path(os.args[1]), if os.args.len == 3 { os.abs_path(os.args[2]) } else { '' }) or {
			eprintln(err)
			exit(1)
		}
	}
}
