// SPDX-License-Identifier: GPL-2.0-or-later
// Independent source and API-28 DEX oracle for the unmonitored activity hint.
module main

import androidtools
import os

const target = 'android/net/ConnectivityManager.smali'
const signature = 'isDefaultNetworkActive()Z'
const class_header = '.class public Landroid/net/ConnectivityManager;'
const super_header = '.super Ljava/lang/Object;'
const disabled_field = '.field public static final RESTRICT_BACKGROUND_STATUS_DISABLED:I = 0x1'
const enabled_field = '.field public static final RESTRICT_BACKGROUND_STATUS_ENABLED:I = 0x3'
const whitelisted_field = '.field public static final RESTRICT_BACKGROUND_STATUS_WHITELISTED:I = 0x2'
const callback_field = '.field private static callbacks:Ljava/util/concurrent/ConcurrentHashMap;'

// This is an independent literal, not the provider's emitted method. Android's
// no-idle-monitor case is an activity scheduling hint, not network validation.
const expected = '.method public isDefaultNetworkActive()Z
.registers 2
const/4 v0, 0x1
return v0
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

fn native_methods(text string) !map[string]string {
	mut selected := map[string]string{}
	for name, body in methods(text)! {
		if body.split_into_lines()[0].fields().contains('native') { selected[name] = norm(body) }
	}
	return selected
}

fn verify(before string, after string) ! {
	old, changed := methods(before)!, methods(after)!
	if old.len != 28 || changed.len != 29 || signature in old || signature !in changed
		|| norm(changed[signature]) != norm(expected) {
		return error('one exact public instance activity hint and 28 retained methods required')
	}
	for name, body in old {
		if name !in changed || norm(body) != norm(changed[name]) { return error('retained connectivity method changed') }
	}
	if metadata(before)! != metadata(after)! { return error('connectivity class, fields or annotations changed') }
	if native_methods(before)! != native_methods(after)!
		|| native_methods(after)!.keys().sorted() != ['nativeGetNetworkAvailable()Z', 'nativeGetNetworkState()I'] {
		return error('the two native query declarations must remain exact')
	}
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
	first := if source.contains(disabled_field) { disabled_field } else { disabled_field.replace('0x1', '1') }
	assert source.count(first) == 1 && source.count(callback_field) == 1
	marker := '# DEFAULT-NETWORK-ACTIVE-CHECK-TEMPORARY-FIELD-MARKER'
	assert !source.contains(marker)
	return source.replace(first, marker).replace(callback_field, first).replace(marker, callback_field)
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		for prefix in ['', 'ordinary-'] {
			assert os.walk_ext(work + '/' + prefix + 'baseline-roundtrip', '.smali').len == 1
			before := os.read_file(work + '/' + prefix + 'baseline-roundtrip/' + target)!
			for directory in ['patched-roundtrip', 'second-roundtrip'] {
				assert os.walk_ext(work + '/' + prefix + directory, '.smali').len == 1
				verify(before, os.read_file(work + '/' + prefix + directory + '/' + target)!)!
			}
			assert os.read_file(work + '/' + prefix + 'patched-roundtrip/' + target)! == os.read_file(work + '/' + prefix + 'second-roundtrip/' + target)!
		}
		println('DEFAULT-NETWORK-ACTIVE-ROUNDTRIP-PASS canonical-and-ordinary-CM one-class 28-retained-methods four-fields two-native-declarations public-instance constant-true both-second-DEX-stable')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_default_network_active_source(before)!
	verify_raw(before, after)!
	assert androidtools.framework_default_network_active_method() == expected
	old := methods(before)!
	assert old.len == 28 && native_methods(before)!.len == 2
	assert norm(before).split_into_lines().filter(it.starts_with('.field ')).len == 4
	decimal := before.replace(disabled_field, disabled_field.replace('0x1', '1'))
		.replace(enabled_field, enabled_field.replace('0x3', '3'))
		.replace(whitelisted_field, whitelisted_field.replace('0x2', '2'))
	mixed := before.replace(disabled_field, disabled_field.replace('0x1', '1'))
	invalids := [after,
		before.replace(class_header, '.class public final Landroid/net/ConnectivityManager;'),
		before.replace(class_header, '.class private Landroid/net/ConnectivityManager;'),
		before + '\n' + class_header + '\n', before.replace(super_header, '.super Landroid/content/Context;'),
		before + '\n' + super_header + '\n',
		before.replace(disabled_field, '.field public static final RESTRICT_BACKGROUND_STATUS_DISABLED:I = 0x0'),
		before.replace(callback_field, '.field public static callbacks:Ljava/util/concurrent/ConcurrentHashMap;'),
		before.replace(callback_field, '.field private static callbacks:Ljava/util/Map;'),
		before + '\n.field private networkActive:Z\n', before + '\n' + callback_field + '\n',
		before.replace(callback_field, ''), before + '\n.end method\n', before.replace('.end method', ''),
		before + '\n' + old['<init>()V']!,
		before.replace('.method public getActiveNetwork()', '.method public static getActiveNetwork()'),
		before.replace('.method public getBackgroundDataSetting()', '.method public bogusBackgroundDataSetting()'),
		before.replace('.method protected native nativeGetNetworkState()', '.method public native nativeGetNetworkState()'),
		before.replace(old['nativeGetNetworkState()I']!, ''),
		before + '\n.method protected native nativeGetNetworkActive()Z\n.end method\n',
		before + '\n.implements Ljava/lang/Runnable;\n', before + '\nnop\n', before + '\x00',
		'.source "before-class.java"\n' + before,
		'.annotation system Lbefore/Class;\nvalue = "invalid-position"\n.end annotation\n' + before,
		before.replace(super_header, '.source "before-super.java"\n' + super_header),
		before.replace(super_header, '.annotation runtime Lbefore/Super;\n.end annotation\n' + super_header),
		before + '\n.end annotation\n', before + '\n.annotation runtime Lunfinished/Annotation;\n',
		before + '\n.method\tpublic static ' + signature + '\n.registers 1\nconst/4 v0, 0x1\nreturn v0\n.end method\n',
		before + '\n.methodpublic malformed()V\n.end method\n', before + '\n.end packed-switch\n',
		decimal.replace(disabled_field.replace('0x1', '1'), disabled_field.replace('0x1', '0')),
		decimal.replace(disabled_field.replace('0x1', '1'), disabled_field.replace('0x1', '2')),
		decimal.replace(enabled_field.replace('0x3', '3'), enabled_field.replace('0x3', '2')),
		decimal.replace(whitelisted_field.replace('0x2', '2'), whitelisted_field.replace('0x2', '3')),
		decimal.replace(disabled_field.replace('0x1', '1'), disabled_field.replace('0x1', '01')),
		decimal.replace(disabled_field.replace('0x1', '1'), disabled_field.replace('0x1', '+1')),
		decimal.replace(enabled_field.replace('0x3', '3'), enabled_field.replace('0x3', '3L')),
		decimal.replace(whitelisted_field.replace('0x2', '2'), whitelisted_field.replace('0x2', '2 invalid'))]
	for invalid in invalids {
		assert invalid != before, 'inactive pure-transform refusal case'
		mut rejected := false
		androidtools.framework_default_network_active_source(invalid) or { rejected = true }
		assert rejected, 'malformed or already extended predecessor accepted'
	}
	whitespace := before.replace('.class ', '.class\t').replace('.super ', '.super\t')
		.replace('.field ', '.field\t').replace('.method ', '.method\t').replace('.end method', '.end\tmethod')
	reversed := reversed_fields(before)
	positives := [before, before.replace('\n', '\r\n'), before.split_into_lines().map('\t' + it).join('\n'),
		whitespace, reversed, reversed.replace('\n', '\r\n'), whitespace.replace('\n', '\r\n'),
		'# preserved formatting positive\n' + reversed.split_into_lines().map('  ' + it).join('\n'),
		decimal, mixed, reversed_fields(decimal)]
	for positive in positives {
		patched := androidtools.framework_default_network_active_source(positive)!
		verify_raw(positive, patched)!
	}
	mutations := [
		after.replace(expected, expected.replace('.method public ', '.method public static ')),
		after.replace(expected, expected.replace('.method public ', '.method private ')),
		after.replace(expected, expected.replace('.method public ', '.method public final ')),
		after.replace(expected, expected.replace('.method public ', '.method public native ')),
		after.replace(expected, expected.replace(signature, 'isDefaultNetworkActive()I')),
		after.replace(expected, expected.replace(signature, 'isDefaultNetworkActive(I)Z')),
		after.replace(expected, expected.replace('.registers 2', '.registers 1')),
		after.replace(expected, expected.replace('.registers 2', '.registers 3')),
		after.replace(expected, expected.replace('const/4 v0, 0x1', 'const/4 v0, 0x0')),
		after.replace(expected, expected.replace('const/4 v0, 0x1', 'const/4 v0, -0x1')),
		after.replace(expected, expected.replace('return v0', 'return p0')),
		after.replace(expected, expected.replace('return v0', 'return-object v0')),
		after.replace(expected, expected.replace('return v0', 'nop\nreturn v0')),
		after.replace(expected, expected.replace('const/4 v0, 0x1', 'invoke-virtual {p0}, Landroid/net/ConnectivityManager;->nativeGetNetworkState()I\nmove-result v0')),
		after.replace(expected, expected.replace('const/4 v0, 0x1', 'invoke-virtual {p0}, Landroid/net/ConnectivityManager;->nativeGetNetworkAvailable()Z\nmove-result v0')),
		after.replace(expected, expected.replace('const/4 v0, 0x1', 'sget-object v0, Landroid/net/ConnectivityManager;->callbacks:Ljava/util/concurrent/ConcurrentHashMap;')),
		after.replace(expected, expected.replace('return v0', 'throw v0')),
		after.replace(expected, ''), after + '\n' + expected + '\n',
		after.replace(old['<init>()V']!, old['<init>()V']!.replace('invoke-direct', 'invoke-virtual')),
		after.replace(old['isActiveNetworkMetered()Z']!, old['isActiveNetworkMetered()Z']!.replace('0x1', '0x0')),
		after.replace(old['nativeGetNetworkState()I']!, old['nativeGetNetworkState()I']!.replace('protected native', 'public native')),
		after.replace(old['nativeGetNetworkAvailable()Z']!, ''),
		after.replace(disabled_field, '.field public static final RESTRICT_BACKGROUND_STATUS_DISABLED:I = 0x0'),
		after.replace(callback_field, '.field private callbacks:Ljava/util/concurrent/ConcurrentHashMap;'),
		after.replace(super_header, '.super Landroid/content/Context;'),
		after.replace(class_header, '.class public final Landroid/net/ConnectivityManager;'),
		after + '\n.field private networkActive:Z\n']
	for broken in mutations {
		assert broken != after, 'inactive semantic or preservation mutation'
		mut rejected := false
		verify(before, broken) or { rejected = true }
		assert rejected, 'activity policy, API shape or predecessor mutation escaped oracle'
	}
	// Call the actual private directory adapter through the driver's thin module
	// bridge, proving malformed input is rejected before its single file write.
	integration := work + '/integration'
	integration_path := integration + '/' + target
	os.mkdir_all(os.dir(integration_path))!
	assert !os.exists(integration_path) && !os.is_link(integration_path), 'fresh integration fixture required'
	for invalid in invalids {
		os.write_file(integration_path, invalid)!
		mut rejected := false
		androidtools.default_network_active_check_apply(integration) or { rejected = true }
		assert rejected && os.read_file(integration_path)! == invalid, 'directory refusal must precede its file write'
	}
	os.write_file(integration_path, before)!
	androidtools.default_network_active_check_apply(integration)!
	assert os.read_file(integration_path)! == after
	// Exercise the real ConnectivityManager writer and method-replacement
	// helper, with NetworkInfo supplied only as its unrelated generator input.
	// These outputs do not execute the complete ordinary SDK pipeline.
	generation := work + '/ordinary-generation'
	info_relative := 'android/net/NetworkInfo.smali'
	info_input := work + '/generator-input/' + info_relative
	info_output := generation + '/' + info_relative
	os.mkdir_all(os.dir(info_output))!
	os.mkdir_all(generation + '/android/atl')!
	assert !os.exists(info_output) && !os.is_link(info_output)
	assert !os.exists(generation + '/' + target) && !os.is_link(generation + '/' + target)
	os.cp(info_input, info_output)!
	androidtools.default_network_active_check_generate(generation)!
	generated := os.read_file(generation + '/' + target)!
	for row in [[disabled_field, '0x1', '1'], [enabled_field, '0x3', '3'], [whitelisted_field, '0x2', '2']] {
		assert generated.count(row[0].replace(row[1], row[2]) + '\n') == 1,
			'the actual upstream writer must expose its decimal field spelling'
	}
	assert methods(generated)!.len == 28 && signature !in methods(generated)!
	ordinary_baseline := work + '/ordinary-baseline/' + target
	os.mkdir_all(os.dir(ordinary_baseline))!
	assert !os.exists(ordinary_baseline) && !os.is_link(ordinary_baseline)
	os.write_file(ordinary_baseline, generated)!
	androidtools.default_network_active_check_apply(generation)!
	generated_patched := os.read_file(generation + '/' + target)!
	verify_raw(generated, generated_patched)!
	ordinary_proof := work + '/ordinary-proof/' + target
	os.mkdir_all(os.dir(ordinary_proof))!
	assert !os.exists(ordinary_proof) && !os.is_link(ordinary_proof)
	os.write_file(ordinary_proof, generated_patched)!
	assert os.walk_ext(work + '/ordinary-baseline', '.smali').len == 1
		&& os.walk_ext(work + '/ordinary-proof', '.smali').len == 1,
		'only ConnectivityManager enters the ordinary-generation DEX controls'
	os.write_file(path, after)!
	assert os.read_file(path)! == after && os.walk_ext(work + '/proof', '.smali').len == 1
	println('DEFAULT-NETWORK-ACTIVE-SOURCE-PASS pure-refusals=' + invalids.len.str()
		+ ' directory-atomic-refusals=' + invalids.len.str() + ' semantic-controls=' + mutations.len.str()
		+ ' formatting-positives=' + positives.len.str()
		+ ' actual-ConnectivityManager-writer decimal-and-hex-fields retained-28-methods four-fields two-native-declarations raw-prefix public-instance constant-true no-native-query no-connectivity-claim')
}
