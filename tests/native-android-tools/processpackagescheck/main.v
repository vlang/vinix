// SPDX-License-Identifier: GPL-2.0-or-later
// Independent preservation oracle for the actual field-only provider helper.
module main

import androidtools
import os

const target = 'android/app/ActivityManager$RunningAppProcessInfo.smali'
const added_field = '.field public pkgList:[Ljava/lang/String;'
const constructors = ['<init>()V', '<init>(ILjava/lang/String;)V',
	'<init>(ILjava/lang/String;Landroid/app/ActivityManager$1;)V']

struct Parts {
	metadata string
	methods map[string]string
}

fn flat(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn parts(source string) !Parts {
	mut methods := map[string]string{}
	mut metadata := source
	mut signature := ''
	mut start := 0
	mut offset := 0
	for line in source.split('\n') {
		trimmed := line.trim_space()
		if trimmed.starts_with('.method ') {
			if signature != '' { return error('unterminated method') }
			signature = trimmed.all_after_last(' ')
			if !signature.contains('(') || signature in methods { return error('unique method required') }
			start = offset
		} else if trimmed == '.end method' {
			if signature == '' { return error('unexpected method end') }
			body := source[start..offset + line.len]
			methods[signature] = body
			metadata = metadata.replace(body, '')
			signature = ''
		}
		offset += line.len + 1
	}
	if signature != '' { return error('unterminated method') }
	return Parts{metadata, methods}
}

fn verify(before string, after string, raw bool) ! {
	old, updated := parts(before)!, parts(after)!
	if old.methods.keys().sorted() != constructors.sorted()
		|| updated.methods.keys().sorted() != constructors.sorted() {
		return error('exact original three constructors required; no new methods')
	}
	old_fields := flat(old.metadata).split_into_lines().filter(it.starts_with('.field '))
	new_fields := flat(updated.metadata).split_into_lines().filter(it.starts_with('.field '))
	if old_fields.len != 11 || old_fields.any(it.contains('pkgList:'))
		|| new_fields.sorted() != [...old_fields, added_field].sorted() {
		return error('exact original eleven fields plus one public mutable instance String array required')
	}
	if flat(old.metadata) != flat(updated.metadata.replace(added_field, '')) {
		return error('all original class metadata and fields must remain unchanged')
	}
	for name, body in old.methods {
		if body != updated.methods[name]! { return error('original constructor changed: ' + name) }
	}
	if raw && after != before + '\n' + added_field + '\n' {
		return error('raw source must be exactly the original plus one appended field')
	}
}

fn refuse(original string, invalid string) ! {
	if original == invalid { return error('inactive input control') }
	if _ := androidtools.framework_process_packages_source(invalid) { return error('malformed helper input accepted') }
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		for directory in ['baseline-roundtrip', 'patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 1
		}
		before := os.read_file(work + '/baseline-roundtrip/' + target)!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			verify(before, os.read_file(work + '/' + directory + '/' + target)!, false)!
		}
		assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		println('PROCESS-PACKAGES-ROUNDTRIP-PASS exact-one-class field-only original-eleven-fields-three-constructors stable-second-DEX')
		return
	}
	before := os.read_file(work + '/baseline/' + target)!
	after := androidtools.framework_process_packages_source(before)!
	verify(before, after, true)!
	old := parts(before)!
	empty := old.methods[constructors[0]]!
	private_ctor := old.methods[constructors[1]]!
	synthetic := old.methods[constructors[2]]!
	mut locals := before
	for signature in constructors {
		body := old.methods[signature]!
		registers := if signature == constructors[0] { '1' } else if signature == constructors[1] { '3' } else { '4' }
		locals = locals.replace(body, body.replace('.registers ' + registers, '.locals 0'))
	}
	mut decimal := before
	for value in ['0x190:400', '0x64:100', '0x7d:125', '0x3e8:1000', '0xe6:230', '0x12c:300', '0xc8:200'] {
		pair := value.split(':')
		decimal = decimal.replace(' = ' + pair[0], ' = ' + pair[1])
	}
	mut positives := 0
	for variant in [before.trim_right('\n'), locals, decimal,
		before.replace(empty, empty.replace('    return-void', '    # .end method\n    return-void')),
		before.replace(private_ctor, private_ctor.replace('    return-void', '    # .end method\n    return-void')),
		before.replace(synthetic, synthetic.replace('    return-void', '    # preserved constructor comment\n    return-void')),
		before + '\n# preserved class metadata comment\n',
		before.replace('.field public importance:I', '.field public importance:I # preserved field comment')] {
		assert variant != before, 'inactive format control'
		verify(variant, androidtools.framework_process_packages_source(variant)!, true)!
		positives++
	}
	mut refusals := 0
	for invalid in [after,
		before.replace('.class public ', '.class private '),
		before + '\n.class public Landroid/app/ActivityManager$RunningAppProcessInfo;\n',
		before.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Thread;'),
		before + '\n.super Ljava/lang/Object;\n',
		before.replace('.field public pid:I', ''), before + '\n.field public pid:I\n',
		before + '\n.field private injected:I\n',
		before.replace('.field public uid:I', '.field public uid:J'),
		before.replace('.field public uid:I', '.field private uid:I'),
		before.replace('.field public uid:I', '.field public static uid:I'),
		before.replace('.field public uid:I', '.field public final uid:I'),
		before.replace('.field public uid:I', '.field public uid:I = -1'),
		before.replace('IMPORTANCE_FOREGROUND:I = 0x64', 'IMPORTANCE_FOREGROUND:I = 0x65'),
		before.replace(empty, ''), before + '\n' + empty + '\n',
		before.replace(empty, empty.replace('.end method', '')),
		before + '\n.end method\n',
		before.replace(empty, empty.replace('.end method', private_ctor)),
		before.replace(empty, empty.replace('.method public constructor', '.method private constructor')),
		before.replace(private_ctor, private_ctor.replace('.method private constructor', '.method public constructor')),
		before.replace(synthetic, synthetic.replace('.method synthetic constructor', '.method public constructor')),
		before.replace(empty, empty.replace('.registers 1', '.registers 2')),
		before.replace(private_ctor, private_ctor.replace('->pid:I', '->uid:I')),
		before.replace(private_ctor, private_ctor.replace('iput-object p2', 'iput-object p1')),
		before.replace(synthetic, synthetic.replace('{p0, p1, p2}', '{p0, p2, p1}')),
		before.replace(empty, empty.replace('return-void', 'const/4 v0, 0\nreturn-void')),
		before + '\n.method public unexpected()V\n.locals 0\nreturn-void\n.end method\n'] {
		refuse(before, invalid)!
		refusals++
	}
	mut mutations := 0
	for invalid in [after.replace(added_field, ''),
		after.replace(added_field, added_field.replace('public', 'private')),
		after.replace(added_field, added_field.replace('public ', 'public static ')),
		after.replace(added_field, added_field.replace('public ', 'public final ')),
		after.replace(added_field, added_field.replace('[Ljava/lang/String;', 'Ljava/lang/String;')),
		after.replace(added_field, added_field + ' = null'),
		after + '\n' + added_field + '\n',
		after + '\n.field private injected:I\n',
		after.replace('.field public pid:I', '.field private pid:I'),
		after.replace('IMPORTANCE_FOREGROUND:I = 0x64', 'IMPORTANCE_FOREGROUND:I = 0x65'),
		after.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Thread;'),
		after.replace('accessFlags = 0x9', 'accessFlags = 0x1'),
		after.replace(empty, empty.replace('return-void', 'const/4 v0, 0\nreturn-void')),
		after.replace(private_ctor, private_ctor.replace('->pid:I', '->uid:I')),
		after.replace(synthetic, synthetic.replace('{p0, p1, p2}', '{p0, p2, p1}')),
		after.replace(empty, ''), after + '\n' + empty + '\n',
		after + '\n.method public constructor <init>(Ljava/lang/String;I[Ljava/lang/String;)V\n.locals 0\nreturn-void\n.end method\n'] {
		assert invalid != after, 'inactive preservation mutation'
		if _ := verify(before, invalid, true) { panic('raw oracle accepted field/constructor/metadata mutation') }
		if _ := verify(before, invalid, false) { panic('canonical oracle accepted field/constructor/metadata mutation') }
		mutations++
	}
	os.write_file(work + '/proof/' + target, after)!
	println('PROCESS-PACKAGES-SOURCE-PASS input-refusals=' + refusals.str() + ' preservation-controls=' + mutations.str()
		+ ' format-positives=' + positives.str() + ' one-public-mutable-instance-array original-eleven-fields-three-constructors default-null field-only-no-process-enumeration-claim')
}
