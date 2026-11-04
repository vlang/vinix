// SPDX-License-Identifier: GPL-2.0-or-later
// Independent source and DEX oracle for the Global String-write adapter.
module main

import androidtools
import os

const target = 'android/provider/Settings$Global.smali'
const signature = 'putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z'
const integer_signature = 'putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z'
const class_header = '.class public final Landroid/provider/Settings$Global;'
const super_header = '.super Landroid/provider/Settings$NameValueTable;'
const uri_field = '.field public static final CONTENT_URI:Landroid/net/Uri;'
const tag_field = '.field private static final TAG:Ljava/lang/String; = "Settings$Global"'

// This literal is independent of the provider under test. The registered
// provider owns validation, permission checks, replacement and persistence.
const expected = '.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z
.registers 6
new-instance v0, Landroid/content/ContentValues;
invoke-direct {v0}, Landroid/content/ContentValues;-><init>()V
const-string v1, "name"
invoke-virtual {v0, v1, p1}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "value"
invoke-virtual {v0, v1, p2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
sget-object v2, Landroid/provider/Settings$Global;->CONTENT_URI:Landroid/net/Uri;
:try_start
invoke-virtual {p0, v2, v0}, Landroid/content/ContentResolver;->insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;
move-result-object v0
:try_end
if-eqz v0, :failed
const/4 v0, 0x1
return v0
:database_error
move-exception v0
:failed
const/4 v0, 0x0
return v0
.catch Landroid/database/SQLException; {:try_start .. :try_end} :database_error
.end method'

// The earlier public method generator must retain its exact original bytes.
const expected_integer = '.method public static putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
    .locals 4
    new-instance v0, Landroid/content/ContentValues;
    invoke-direct {v0}, Landroid/content/ContentValues;-><init>()V
    const-string v1, "name"
    invoke-virtual {v0, v1, p1}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
    invoke-static {p2}, Ljava/lang/Integer;->toString(I)Ljava/lang/String;
    move-result-object v2
    const-string v1, "value"
    invoke-virtual {v0, v1, v2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
    sget-object v3, Landroid/provider/Settings$Global;->CONTENT_URI:Landroid/net/Uri;
    :try_start
    invoke-virtual {p0, v3, v0}, Landroid/content/ContentResolver;->insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;
    move-result-object v0
    :try_end
    if-eqz v0, :failed
    const/4 v0, 0x1
    return v0
    :database_error
    move-exception v0
    :failed
    const/4 v0, 0x0
    return v0
    .catch Landroid/database/SQLException; {:try_start .. :try_end} :database_error
.end method'

fn norm(text string) string {
	return text.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')).join('\n')
}

fn methods(text string) !map[string]string {
	mut result := map[string]string{}
	mut body := []string{}
	mut name := ''
	for line in text.split_into_lines() {
		parts := line.trim_space().fields()
		if parts.len == 0 || parts[0].starts_with('#') {
			if name != '' { body << line }
			continue
		}
		if parts[0] == '.method' {
			if name != '' || parts.len < 3 { return error('nested or malformed method') }
			name = parts.last()
			if !name.contains('(') || name in result { return error('unique method signature required') }
			body << line
		} else if parts.len >= 2 && parts[0] == '.end' && parts[1] == 'method' {
			if parts.len != 2 || name == '' { return error('stray or malformed method terminator') }
			body << line
			result[name] = body.join('\n')
			body = []string{}
			name = ''
		} else if name != '' {
			body << line
		}
	}
	if name != '' { return error('unterminated method') }
	return result
}

fn metadata(text string) !string {
	methods(text)!
	mut lines := []string{}
	mut active := false
	for line in text.split_into_lines() {
		parts := line.trim_space().fields()
		if parts.len > 0 && parts[0] == '.method' {
			active = true
		} else if parts.len >= 2 && parts[0] == '.end' && parts[1] == 'method' {
			active = false
		} else if !active {
			lines << line
		}
	}
	return norm(lines.join('\n'))
}

// Compare instruction positions for branches and the typed catch range and
// handler. Canonical disassembly can rename labels and move catch directives.
fn control_flow(text string) !string {
	lines := norm(text).split_into_lines()
	mut mapping := map[string]string{}
	mut position := 0
	for line in lines {
		if line.starts_with(':') {
			if line in mapping || line.fields().len != 1 { return error('unique labels required') }
			mapping[line] = ':instruction_' + position.str()
		} else if !line.starts_with('.catch ') {
			position++
		}
	}
	mut result := []string{}
	mut catches := []string{}
	for line in lines {
		if line in mapping { continue }
		if line.starts_with('.catch ') {
			parts := line.fields()
			if parts.len != 6 { return error('canonical typed catch required') }
			start, end, handler := parts[2].trim_left('{'), parts[4].trim_right('}'), parts[5]
			if start !in mapping || end !in mapping || handler !in mapping { return error('catch labels absent') }
			catches << '.catch ' + parts[1] + ' {' + mapping[start] + ' .. ' + mapping[end] + '} ' + mapping[handler]
			continue
		}
		last := line.fields().last()
		if line.starts_with('if-') || line.starts_with('goto') {
			if last !in mapping { return error('branch label absent') }
			result << line[..line.len - last.len] + mapping[last]
		} else {
			result << line
		}
	}
	return result.join('\n') + '\n' + catches.sorted().join('\n')
}

fn verify(before string, after string) ! {
	old, changed := methods(before)!, methods(after)!
	if old.len != 11 || changed.len != 12 || signature in old || signature !in changed
		|| integer_signature !in old || control_flow(changed[signature])! != control_flow(expected)! {
		return error('one exact Global String adapter and eleven retained methods required')
	}
	for name, body in old {
		if name !in changed || norm(body) != norm(changed[name]) { return error('retained Global method changed') }
	}
	if metadata(before)! != metadata(after)! { return error('Global class, fields or annotations changed') }
}

fn verify_raw(before string, after string) ! {
	verify(before, after)!
	if after != before + '\n' + expected + '\n' { return error('raw predecessor bytes must remain an exact prefix') }
	old, changed := methods(before)!, methods(after)!
	for name, body in old {
		if changed[name]! != body { return error('raw old method bytes changed') }
	}
}

fn reversed_fields(source string) string {
	assert source.count(uri_field) == 1 && source.count(tag_field) == 1
	marker := '# GLOBAL-STRING-CHECK-TEMPORARY-FIELD-MARKER'
	assert !source.contains(marker)
	return source.replace(uri_field, marker).replace(tag_field, uri_field).replace(marker, tag_field)
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	assert control_flow(':start\n:alias\nnop\n:end\nreturn-void\n:handler\nthrow v0\n.catch Landroid/database/SQLException; {:start .. :end} :handler')! ==
		control_flow(':a\nnop\n:b\n.catch Landroid/database/SQLException; {:a .. :b} :c\nreturn-void\n:c\nthrow v0')!
	assert control_flow(expected)! != control_flow(expected.replace('{:try_start .. :try_end}', '{:try_start .. :failed}'))!
	assert control_flow(expected)! != control_flow(expected.replace('} :database_error', '} :failed'))!
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		assert os.walk_ext(work + '/baseline-roundtrip', '.smali').len == 1
		before := os.read_file(work + '/baseline-roundtrip/' + target)!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 1
			verify(before, os.read_file(work + '/' + directory + '/' + target)!)!
		}
		assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		println('GLOBAL-SETTINGS-STRING-ROUNDTRIP-PASS one-class eleven-retained-methods exact-String-values Global-URI SQL-only-span-handler stable-second-DEX')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_settings_global_put_string_source(before)!
	verify_raw(before, after)!
	assert androidtools.framework_settings_global_put_string_method() == expected
	assert androidtools.framework_settings_global_put_int_method() == expected_integer
	old := methods(before)!
	assert old.len == 11 && integer_signature in old
	invalids := [after, before.replace(class_header, '.class public Landroid/provider/Settings$Global;'),
		before + '\n' + class_header + '\n', before.replace(super_header, '.super Ljava/lang/Object;'),
		before + '\n' + super_header + '\n', before.replace(uri_field, '.field private CONTENT_URI:Landroid/net/Uri;'),
		before.replace(tag_field, '.field private static final TAG:Ljava/lang/String; = "Wrong"'),
		before + '\n.field private fakeStore:Ljava/util/Map;\n', before + '\n' + uri_field + '\n',
		before.replace(uri_field, ''), before + '\n.end method\n', before.replace('.end method', ''),
		before + '\n' + old['<init>()V']!, before.replace('.method public static getUriFor(', '.method public getUriFor('),
		before.replace('.method public static getString(', '.method public static bogusString('),
		before + '\n.implements Ljava/lang/Runnable;\n', before + '\nnop\n', before + '\x00',
		'.source "before-class.java"\n' + before,
		'.annotation system Lbefore/Class;\nvalue = "invalid-position"\n.end annotation\n' + before,
		before.replace(super_header, '.source "before-super.java"\n' + super_header),
		before.replace(super_header, '.annotation runtime Lbefore/Super;\n.end annotation\n' + super_header),
		before + '\n.end annotation\n', before + '\n.annotation runtime Lunfinished/Annotation;\n',
		before.replace('.end annotation', '.end annotation extra'),
		before + '\n.method\tpublic static ' + signature + '\n.registers 3\nreturn p0\n.end method\n',
		before + '\n.methodpublic static malformed()V\n.end method\n', before + '\n.end packed-switch\n']
	for invalid in invalids {
		assert invalid != before, 'inactive pure-transform refusal case'
		mut rejected := false
		androidtools.framework_settings_global_put_string_source(invalid) or { rejected = true }
		assert rejected, 'malformed or already extended predecessor accepted'
	}
	whitespace := before.replace('.class ', '.class\t').replace('.super ', '.super\t')
		.replace('.field ', '.field\t').replace('.method ', '.method\t').replace('.end method', '.end\tmethod')
		.replace('.annotation ', '.annotation\t')
	reversed := reversed_fields(before)
	positives := [before, before.replace('\n', '\r\n'), before.split_into_lines().map('\t' + it).join('\n'),
		whitespace, reversed, reversed.replace('\n', '\r\n'), whitespace.replace('\n', '\r\n'),
		'# preserved formatting positive\n' + reversed.split_into_lines().map('  ' + it).join('\n')]
	for positive in positives {
		patched := androidtools.framework_settings_global_put_string_source(positive)!
		verify_raw(positive, patched)!
	}
	mutations := [
		after.replace(expected, expected.replace('{v0, v1, p1}', '{v0, v1, p2}')),
		after.replace(expected, expected.replace('{v0, v1, p2}', '{v0, v1, p1}')),
		after.replace(expected, expected.replace('const-string v1, "name"', 'const-string v1, "wrong-name"')),
		after.replace(expected, expected.replace('const-string v1, "value"', 'const-string v1, "wrong-value"')),
		after.replace(expected, expected.replace('put(Ljava/lang/String;Ljava/lang/String;)V', 'put(Ljava/lang/String;Ljava/lang/Integer;)V')),
		after.replace(expected, expected.replace('Settings$Global;->CONTENT_URI', 'Settings$Secure;->CONTENT_URI')),
		after.replace(expected, expected.replace('.method public static ', '.method public ')),
		after.replace(expected, expected.replace('.method public static ', '.method private static ')),
		after.replace(expected, expected.replace('.registers 6', '.registers 7')),
		after.replace(expected, expected.replace('invoke-virtual {p0, v2, v0}', 'invoke-direct {p0, v2, v0}')),
		after.replace(expected, expected.replace('invoke-virtual {p0, v2, v0}', 'invoke-virtual {p1, v2, v0}')),
		after.replace(expected, expected.replace('invoke-virtual {p0, v2, v0}', 'invoke-virtual {p0, v0, v2}')),
		after.replace(expected, expected.replace('if-eqz v0, :failed', 'if-nez v0, :failed')),
		after.replace(expected, expected.replace('const/4 v0, 0x1', 'const/4 v0, 0x0')),
		after.replace(expected, expected.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
		after.replace(expected, expected.replace('.catch Landroid/database/SQLException;', '.catch Ljava/lang/RuntimeException;')),
		after.replace(expected, expected.replace('.catch Landroid/database/SQLException; {:try_start .. :try_end} :database_error', '')),
		after.replace(expected, expected.replace('{:try_start .. :try_end}', '{:try_start .. :failed}')),
		after.replace(expected, expected.replace('} :database_error', '} :failed')),
		after.replace(expected, expected.replace(':failed\nconst/4', ':failed\n.catchall {:try_start .. :try_end} :failed\nconst/4')),
		after.replace('Landroid/provider/Settings$NameValueTable;-><init>()V', 'Ljava/lang/Object;-><init>()V'),
		after.replace('Ljava/lang/Integer;->toString(I)', 'Ljava/lang/Integer;->toHexString(I)'),
		after.replace(tag_field, '.field private static final TAG:Ljava/lang/String; = "Wrong"'),
		after.replace(super_header, '.super Ljava/lang/Object;'),
		after.replace('name = "Global"', 'name = "Wrong"'), after + '\n.field private fakeStore:Ljava/util/Map;\n']
	for broken in mutations {
		assert broken != after, 'inactive semantic or preservation mutation'
		mut rejected := false
		verify(before, broken) or { rejected = true }
		assert rejected, 'argument, URI, result, SQL boundary or predecessor mutation escaped oracle'
	}
	// Exercise the actual private ordinary integration through the driver's thin
	// module adapter. This ten-method input predates the existing putInt helper.
	ten := before.replace(old[integer_signature]!, '')
	assert methods(ten)!.len == 10
	with_integer := androidtools.framework_settings_global_put_int(ten)!
	assert with_integer == ten + '\n' + expected_integer + '\n'
	combined := androidtools.framework_settings_global_put_string_source(with_integer)!
	verify_raw(with_integer, combined)!
	integration := work + '/integration'
	integration_path := integration + '/' + target
	os.mkdir_all(os.dir(integration_path))!
	assert !os.exists(integration_path) && !os.is_link(integration_path), 'fresh integration fixture required'
	between_stage_invalids := ['.source "before-class.java"\n' + ten,
		'.annotation system Lbefore/Class;\nvalue = "invalid-position"\n.end annotation\n' + ten,
		ten + '\x00']
	for invalid in between_stage_invalids {
		// The old helper admits these shapes, so rejection must happen in the
		// second pure stage, before the private integration writes anything.
		androidtools.framework_settings_global_put_int(invalid)!
	}
	integration_invalids := [before, after, ten.replace(class_header, '.class public Landroid/provider/Settings$Global;'),
		ten.replace(super_header, '.super Ljava/lang/Object;'), ten + '\n' + uri_field + '\n',
		ten.replace('.end method', ''), ten + '\n.end method\n',
		ten + '\n.method public static bogus()V\n.registers 0\nreturn-void\n.end method\n',
		between_stage_invalids[0], between_stage_invalids[1], between_stage_invalids[2]]
	for invalid in integration_invalids {
		os.write_file(integration_path, invalid)!
		mut rejected := false
		androidtools.global_settings_string_check_apply(integration) or { rejected = true }
		assert rejected && os.read_file(integration_path)! == invalid, 'integration refusal must precede every write'
	}
	os.write_file(integration_path, ten)!
	androidtools.global_settings_string_check_apply(integration)!
	assert os.read_file(integration_path)! == combined
	os.write_file(path, before)!
	assert os.read_file(path)! == before
	os.write_file(path, after)!
	assert os.read_file(path)! == after && os.walk_ext(work + '/proof', '.smali').len == 1
	println('GLOBAL-SETTINGS-STRING-SOURCE-PASS pure-refusals=' + invalids.len.str()
		+ ' integration-atomic-refusals=' + integration_invalids.len.str() + ' semantic-controls=' + mutations.len.str()
		+ ' formatting-positives=' + positives.len.str()
		+ ' retained-eleven-methods two-fields annotations raw-prefix old-putInt-unchanged actual-private-integration String-values Global-URI SQL-only-span-handler')
}
