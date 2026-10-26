// SPDX-License-Identifier: GPL-2.0-or-later
// Host guards and DEX assembly; value behavior still requires actual ART.
module main

import androidtools
import os

fn method(source string, signature string) string {
	for block in source.split('.method ') {
		if block.all_before('\n').ends_with(' ' + signature) {
			return block.all_before('.end method')
		}
	}
	panic('missing method: ' + signature)
}

fn main() {
	assert os.args.len in [1, 4], 'usage: check-authenticator-descriptions [TOOLS JAVA FRESH-OUTPUT]'
	query := 'getAuthenticatorTypes()[Landroid/accounts/AuthenticatorDescription;'
	unrelated := '.method public unrelated()I\n.locals 1\nconst/4 v0, 0x7\nreturn v0\n.end method\n'
	base := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n' + unrelated
	native := '.method public native ' + query + '\n.end method'
	patched := androidtools.framework_authenticator_descriptions(base)!
	assert patched.count(native) == 1 && patched.contains(unrelated)
	assert androidtools.framework_authenticator_descriptions(patched)! == patched
	stub := '.method public ' + query + '\n.locals 1\nconst/4 v0, 0x0\nreturn-object v0\n.end method'
	assert androidtools.framework_authenticator_descriptions(base + stub)!.count(native) == 1
	for invalid in [base.replace(' Landroid/accounts/AccountManager;', ' Lwrong/Class;'),
		base + '.class public Landroid/accounts/AccountManager;\n', base + stub + '\n' + stub,
		base + '.method public ' + query + '\n.locals 0\n'] {
		mut rejected := false
		androidtools.framework_authenticator_descriptions(invalid) or { rejected = true }
		assert rejected
	}
	classes := androidtools.framework_authenticator_description_classes()
	assert classes.len == 2
	value := classes['android/accounts/AuthenticatorDescription']
	creator := classes['android/accounts/AuthenticatorDescription$Creator']
	assert value != '' && creator != ''
	for body in [value, creator] {
		assert body.count('.method ') == body.count('.end method')
		assert !body.contains(' native ') && !body.contains('Landroid/util/Log;')
		assert !body.contains('Ljava/lang/System;') && !body.contains('Ljava/io/PrintStream;')
	}
	for declaration in ['public final type:Ljava/lang/String;', 'public final packageName:Ljava/lang/String;',
		'public final labelId:I', 'public final iconId:I', 'public final smallIconId:I',
		'public final accountPreferencesId:I', 'public final customTokens:Z',
		'public static final CREATOR:Landroid/os/Parcelable$Creator;'] {
		assert value.count('.field ' + declaration + '\n') == 1
	}
	assert value.count('.field ') == 8
	full := method(value, '<init>(Ljava/lang/String;Ljava/lang/String;IIIIZ)V')
	assert full.contains('if-eqz p1, :bad_type') && full.contains('if-eqz p2, :bad_package')
	assert full.count('new-instance v0, Ljava/lang/IllegalArgumentException;') == 1
	assert full.contains(':throw_invalid\nnew-instance v0, Ljava/lang/IllegalArgumentException;')
	assert !full.contains('->length()I') // Empty strings are valid Android values.
	assert method(value, '<init>(Ljava/lang/String;Ljava/lang/String;IIII)V').contains('const/4 v7, 0x0\ninvoke-direct/range {v0 .. v7}')
	new_key := method(value, 'newKey(Ljava/lang/String;)Landroid/accounts/AuthenticatorDescription;')
	assert new_key.contains('if-nez p0, :valid')
	assert new_key.contains('const-string v1, "type cannot be null"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V')
	key := method(value, '<init>(Ljava/lang/String;)V')
	assert key.contains('iput-object v0, p0, Landroid/accounts/AuthenticatorDescription;->packageName:Ljava/lang/String;')
	for name in ['labelId', 'iconId', 'smallIconId', 'accountPreferencesId'] {
		assert key.contains('->' + name + ':I')
	}
	read := method(value, '<init>(Landroid/os/Parcel;)V')
	write := method(value, 'writeToParcel(Landroid/os/Parcel;I)V')
	mut last_read := -1
	mut last_write := -1
	for name in ['type:Ljava/lang/String;', 'packageName:Ljava/lang/String;', 'labelId:I', 'iconId:I',
		'smallIconId:I', 'accountPreferencesId:I', 'customTokens:Z'] {
		read_index := read.index('->' + name) or { panic('missing parcel read: ' + name) }
		write_index := write.index('->' + name) or { panic('missing parcel write: ' + name) }
		assert read_index > last_read && write_index > last_write
		last_read = read_index
		last_write = write_index
	}
	assert read.count('->readString()') == 2 && read.count('->readInt()') == 4 && read.count('->readByte()B') == 1
	assert write.count('->writeString(') == 2 && write.count('->writeInt(') == 4 && write.count('->writeByte(B)') == 1
	assert read.contains('const/4 v1, 0x1\nif-eq v0, v1, :custom\nconst/4 v1, 0x0')
	for signature in ['equals(Ljava/lang/Object;)Z', 'hashCode()I'] {
		body := method(value, signature)
		assert body.contains('->type:Ljava/lang/String;') && !body.contains('->packageName:')
	}
	assert method(value, 'equals(Ljava/lang/Object;)Z').contains('instance-of')
	assert method(value, 'toString()Ljava/lang/String;').contains('"AuthenticatorDescription {type="')
	assert creator.contains('public bridge synthetic createFromParcel') && creator.contains('public bridge synthetic newArray')
	println('AUTHENTICATOR-DESCRIPTIONS-PROVIDER-PASS native query, public value API, parcel order, invalid source rejection')
	if os.args.len == 4 {
		work := os.abs_path(os.args[3])
		assert !os.exists(work), 'assembly output must be fresh'
		os.mkdir_all(work + '/smali/android/accounts')!
		for name, source in classes { os.write_file(work + '/smali/' + name + '.smali', source)! }
		os.write_file(work + '/smali/android/accounts/AccountManager.smali', patched)!
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[1]), os.args[2])!
		result := os.exec([os.args[2], '-cp', os.real_path(os.args[1]) + '/*', 'org.jf.baksmali.Main', 'disassemble',
			'--jobs', '2', work + '/classes.dex', '-o', work + '/roundtrip'])
		os.write_file(work + '/disassemble.log', result.output)!
		assert result.exit_code == 0, result.output
		for name in ['AuthenticatorDescription', 'AuthenticatorDescription$Creator'] {
			roundtrip := os.read_file(work + '/roundtrip/android/accounts/' + name + '.smali')!
			assert roundtrip.count('.method ') == classes['android/accounts/' + name].count('.method ')
		}
		println('AUTHENTICATOR-DESCRIPTIONS-ASSEMBLY-PASS value, creator and native query round-trip DEX')
	}
}
