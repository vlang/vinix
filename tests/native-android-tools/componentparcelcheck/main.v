// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const target = 'android/content/ComponentName.smali'
const creator = 'android/content/VinixComponentNameCreator.smali'

fn norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete methods required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn flow(source string) string {
	lines := norm(source).split_into_lines()
	mut labels := map[string]string{}
	mut position := 0
	for line in lines {
		if line.starts_with(':') {
			labels[line] = ':instruction_' + position.str()
		} else {
			position++
		}
	}
	mut result := []string{}
	for line in lines {
		if line in labels { continue }
		last := line.fields().last()
		if (line.starts_with('if-') || line.starts_with('goto')) && last in labels {
			result << line[..line.len - last.len] + labels[last]
		} else {
			result << line
		}
	}
	return result.join('\n')
}

fn metadata(source string) !string {
	mut rest := source
	for _, body in methods(source)! { rest = rest.replace(body, '') }
	lines := norm(rest).split_into_lines()
	return lines.filter(!it.starts_with('.field ')).join('\n') + '\n' + lines.filter(it.starts_with('.field ')).sorted().join('\n')
}

fn m(header string, registers int, body string) string {
	return '.method ' + header + '\n.registers ' + registers.str() + '\n' + body + '\n.end method'
}

fn expected_methods() map[string]string {
	return {
		'<clinit>()V':                                                        m('static constructor <clinit>()V', 1,
			'new-instance v0, Landroid/content/VinixComponentNameCreator;\ninvoke-direct {v0}, Landroid/content/VinixComponentNameCreator;-><init>()V\nsput-object v0, Landroid/content/ComponentName;->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
		'<init>(Landroid/os/Parcel;)V':                                       m('public constructor <init>(Landroid/os/Parcel;)V', 4,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;\nif-nez v0, :package_ok\nnew-instance v0, Ljava/lang/NullPointerException;\nconst-string v1, "package name is null"\ninvoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V\nthrow v0\n:package_ok\ninvoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;\nif-nez v0, :class_ok\nnew-instance v0, Ljava/lang/NullPointerException;\nconst-string v1, "class name is null"\ninvoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V\nthrow v0\n:class_ok\nreturn-void')
		'<init>(Ljava/lang/String;Landroid/os/Parcel;)V':                     m('private constructor <init>(Ljava/lang/String;Landroid/os/Parcel;)V', 4,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;\ninvoke-virtual {p2}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;\nreturn-void')
		'writeToParcel(Landroid/os/Parcel;I)V':                               m('public writeToParcel(Landroid/os/Parcel;I)V', 4,
			'iget-object v0, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\niget-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nreturn-void')
		'writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V': m('public static writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V', 3,
			'const/4 v0, 0x0\nif-eqz p0, :null\ninvoke-virtual {p0, p1, v0}, Landroid/content/ComponentName;->writeToParcel(Landroid/os/Parcel;I)V\nreturn-void\n:null\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nreturn-void')
		'readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;': m('public static readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;', 3,
			'invoke-virtual {p0}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\nif-nez v0, :present\nconst/4 v0, 0x0\nreturn-object v0\n:present\nnew-instance v1, Landroid/content/ComponentName;\ninvoke-direct {v1, v0, p0}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Landroid/os/Parcel;)V\nreturn-object v1')
	}
}

fn verify(before string, after string, raw bool) ! {
	old, changed := methods(before)!, methods(after)!
	additions := expected_methods()
	mut names := old.keys()
	names << additions.keys()
	if old.len != 23 || changed.len != 29 || changed.keys().sorted() != names.sorted() {
		return error('exact six additive ComponentName methods required')
	}
	for name, expected in additions {
		if name in old || flow(changed[name]) != flow(expected) {
			return error('ComponentName parcel method: ' + name)
		}
	}
	for name, body in old {
		same := if raw { changed[name] == body } else { norm(changed[name]) == norm(body) }
		if !same {
			return error('old ComponentName method changed: ' + name)
		}
	}
	if metadata(after)! != metadata(before + '\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;')! {
		return error('ComponentName old schema and final fields must remain intact')
	}
}

fn verify_creator(source string) ! {
	expected := {
		'<init>()V':                                               m('public constructor <init>()V', 1, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
		'createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;': m('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 3,
			'new-instance v0, Landroid/content/ComponentName;\ninvoke-direct {v0, p1}, Landroid/content/ComponentName;-><init>(Landroid/os/Parcel;)V\nreturn-object v0')
		'newArray(I)[Ljava/lang/Object;':                          m('public newArray(I)[Ljava/lang/Object;', 3,
			'new-array v0, p1, [Landroid/content/ComponentName;\nreturn-object v0')
	}
	actual := methods(source)!
	if actual.keys().sorted() != expected.keys().sorted()
		|| metadata(source)! != '.class final Landroid/content/VinixComponentNameCreator;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' {
		return error('exact fieldless ComponentName Creator required')
	}
	for name, method in expected {
		if flow(actual[name]) != flow(method) { return error('ComponentName creator: ' + name) }
	}
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := os.read_file(work + '/baseline-roundtrip/' + target)!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 2
			verify(before, os.read_file(work + '/' + directory + '/' + target)!, false)!
			verify_creator(os.read_file(work + '/' + directory + '/' + creator)!)!
		}
		for name in [target, creator] {
			assert os.read_file(work + '/patched-roundtrip/' + name)! == os.read_file(work + '/second-roundtrip/' + name)!
		}
		println('COMPONENT-PARCEL-ROUNDTRIP-PASS retained-23-methods exact-6-additions public-null-check-order nullable-helper-no-class-validation stable-second-DEX')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_component_parcel_source(before)!
	verify(before, after, true)!
	assert after.starts_with(before)
	invalids := [after, before.replace('.class public final ', '.class public '),
		before + '\n.class public final Landroid/content/ComponentName;\n',
		before.replace('.super Ljava/lang/Object;', '.super Landroid/view/View;'),
		before + '\n.super Ljava/lang/Object;\n',
		before + '\n.field private fakeStore:Ljava/lang/Object;\n',
		before.replace('.field private final mClass:', '.field private mClass:'),
		before.replace('.implements Landroid/os/Parcelable;', '.implements Ljava/lang/Runnable;'),
		before.replace('.end method', ''), before + '\n.end method\n',
		before + '\n.method\tpublic unrelated()V\n.end method\n',
		before + '\n' + (methods(before)!)['describeContents()I'],
		before + '\n' + expected_methods()['writeToParcel(Landroid/os/Parcel;I)V']]
	for invalid in invalids {
		assert invalid != before
		os.write_file(path, invalid)!
		mut refused := false
		androidtools.framework_component_parcel(work + '/proof') or { refused = true }
		assert refused && os.read_file(path)! == invalid && !os.exists(work + '/proof/' + creator), 'refusal before writes'
	}
	os.write_file(path, before)!
	creator_path := work + '/proof/' + creator
	for kind in ['file', 'directory', 'symlink'] {
		if kind == 'file' {
			os.write_file(creator_path, 'collision')!
		} else if kind == 'directory' {
			os.mkdir(creator_path)!
		} else {
			os.symlink('absent-component-helper', creator_path)!
		}
		mut refused := false
		androidtools.framework_component_parcel(work + '/proof') or { refused = true }
		assert refused && os.read_file(path)! == before
		if kind == 'directory' {
			assert os.is_dir(creator_path)
			os.rmdir(creator_path)!
		} else if kind == 'symlink' {
			assert os.readlink(creator_path)! == 'absent-component-helper'
			os.rm(creator_path)!
		} else {
			assert os.read_file(creator_path)! == 'collision'
			os.rm(creator_path)!
		}
	}
	androidtools.framework_component_parcel(work + '/proof')!
	assert os.read_file(path)! == after
	creator_source := os.read_file(creator_path)!
	verify_creator(creator_source)!
	mut controls := 0
	for change in [
		['<init>(Landroid/os/Parcel;)V', 'if-nez v0, :package_present', 'if-eqz v0, :package_present'],
		['<init>(Landroid/os/Parcel;)V', 'if-nez v0, :done', 'if-eqz v0, :done'],
		['<init>(Landroid/os/Parcel;)V', '"package name is null"', '"class name is null"'],
		['<init>(Landroid/os/Parcel;)V', 'throw v0', 'return-void'],
		['<init>(Landroid/os/Parcel;)V', 'if-nez v0, :package_present',
			'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nif-nez v0, :package_present'],
		['<init>(Ljava/lang/String;Landroid/os/Parcel;)V', 'return-void',
			'invoke-static {v0}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\nreturn-void'],
		['writeToParcel(Landroid/os/Parcel;I)V', '->mPackage:', '->mClass:'],
		['writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V', 'const/4 v0, 0x0',
			'const/4 v0, 0x1'],
		['writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V',
			'->writeString(Ljava/lang/String;)V', '->writeInt(I)V'],
		['readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;', 'if-nez v0, :present',
			'if-eqz v0, :present'],
		['readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;', 'return-object v0',
			'invoke-virtual {p0}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nreturn-object v0'],
		['readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;',
			'<init>(Ljava/lang/String;Landroid/os/Parcel;)V',
			'<init>(Ljava/lang/String;Ljava/lang/String;)V'],
		['getClassName()Ljava/lang/String;', '->mClass:', '->mPackage:'],
		['<init>(Ljava/lang/String;Ljava/lang/String;)V', '"package name is null"',
			'"wrong old constructor"'],
	] {
		old_method := (methods(after)!)[change[0]]
		broken_method := old_method.replace(change[1], change[2])
		assert broken_method != old_method
		mut refused := false
		verify(before, after.replace(old_method, broken_method), true) or { refused = true }
		assert refused, 'wire, cursor/order, validation or old method control escaped oracle'
		controls++
	}
	for broken in [
		after.replace('.field public static final CREATOR:', '.field public final CREATOR:'),
		after + '\n.field private fakeState:I\n',
	] {
		mut refused := false
		verify(before, broken, true) or { refused = true }
		assert refused
		controls++
	}
	for broken in [
		creator_source.replace('<init>(Landroid/os/Parcel;)V', 'readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;'),
		creator_source.replace('[Landroid/content/ComponentName;', '[Ljava/lang/Object;'),
		creator_source + '\n.field private fakeState:I\n',
	] {
		mut refused := false
		verify_creator(broken) or { refused = true }
		assert refused, 'Creator constructor, array component or state escaped oracle'
		controls++
	}
	assert os.walk_ext(work + '/proof', '.smali').len == 2
	println('COMPONENT-PARCEL-SOURCE-PASS refusals=' + (invalids.len + 3).str() + ' semantic-controls=' + controls.str() + ' retained-23-methods API28-null-cursor-contract')
}
