// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const target = 'android/provider/Settings$Secure.smali'
const signature = 'putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z'
const tile = 'android/service/quicksettings/TileService.smali'
const expected = '.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z
.registers 6
new-instance v0, Landroid/content/ContentValues;
invoke-direct {v0}, Landroid/content/ContentValues;-><init>()V
const-string v1, "name"
invoke-virtual {v0, v1, p1}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "value"
invoke-virtual {v0, v1, p2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
sget-object v2, Landroid/provider/Settings$Secure;->CONTENT_URI:Landroid/net/Uri;
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

fn norm(text string) string {
	return text.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn methods(text string) !map[string]string {
	mut result := map[string]string{}
	for block in text.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete methods required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

// Compare branch and typed exception span/handler instruction positions. Catch
// directives may move beside the try-end label during canonical disassembly.
fn control_flow(text string) !string {
	lines := norm(text).split_into_lines()
	mut mapping := map[string]string{}
	mut position := 0
	for line in lines {
		if line.starts_with(':') {
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
			if start !in mapping || end !in mapping || handler !in mapping {
				return error('catch labels absent')
			}
			catches << '.catch ' + parts[1] + ' {' + mapping[start] + ' .. ' + mapping[end] + '} ' + mapping[handler]
			continue
		}
		last := line.fields().last()
		if (line.starts_with('if-') || line.starts_with('goto')) && last in mapping {
			result << line[..line.len - last.len] + mapping[last]
		} else {
			result << line
		}
	}
	return result.join('\n') + '\n' + catches.sorted().join('\n')
}

fn verify(before string, after string) ! {
	old, changed := methods(before)!, methods(after)!
	if old.len != 10 || changed.len != 11 || signature in old || signature !in changed
		|| control_flow(changed[signature])! != control_flow(expected)! {
		return error('exact String insertion and database-only failure boundary required')
	}
	for name, body in old {
		if name !in changed || norm(body) != norm(changed[name]) {
			return error('retained Settings.Secure method changed')
		}
	}
	if norm(after.replace(changed[signature], '')) != norm(before) {
		return error('Settings.Secure metadata changed')
	}
}

fn verify_tile(source string) ! {
	parts := methods(source)!
	expected_methods := {
		'<init>()V':                                                                        '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void\n.end method'
		'onBind(Landroid/content/Intent;)Landroid/os/IBinder;':                             '.method public onBind(Landroid/content/Intent;)Landroid/os/IBinder;\n.registers 3\nconst/4 v0, 0x0\nreturn-object v0\n.end method'
		'requestListeningState(Landroid/content/Context;Landroid/content/ComponentName;)V': '.method public static final requestListeningState(Landroid/content/Context;Landroid/content/ComponentName;)V
.registers 4
new-instance v0, Landroid/content/Intent;
const-string v1, "android.service.quicksettings.action.REQUEST_LISTENING"
invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v1, "android.intent.extra.COMPONENT_NAME"
invoke-virtual {v0, v1, p1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;
const-string v1, "com.android.systemui"
invoke-virtual {v0, v1}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "android.permission.BIND_QUICK_SETTINGS_TILE"
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V
return-void
.end method'
	}
	if parts.keys().sorted() != expected_methods.keys().sorted() {
		return error('exact TileService surface required')
	}
	mut metadata := source
	for name, body in parts {
		if control_flow(body)! != control_flow(expected_methods[name])! {
			return error('TileService request, constructor or absent binder differs')
		}
		metadata = metadata.replace(body, '')
	}
	if norm(metadata) != '.class public Landroid/service/quicksettings/TileService;\n.super Landroid/app/Service;' {
		return error('fieldless concrete TileService with Service superclass required')
	}
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	assert control_flow(':start\n:alias\nnop\n:end\nreturn-void\n:handler\nthrow v0\n.catch Landroid/database/SQLException; {:start .. :end} :handler')! ==
		control_flow(':a\nnop\n:b\n.catch Landroid/database/SQLException; {:a .. :b} :c\nreturn-void\n:c\nthrow v0')!
	assert control_flow(expected)! != control_flow(expected.replace('{:try_start .. :try_end}', '{:try_start .. :failed}'))!
	assert control_flow(expected)! != control_flow(expected.replace('} :database_error', '} :failed'))!
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := os.read_file(work + '/baseline-roundtrip/' + target)!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 2
			verify(before, os.read_file(work + '/' + directory + '/' + target)!)!
			verify_tile(os.read_file(work + '/' + directory + '/' + tile)!)!
		}
		for name in [target, tile] {
			assert os.read_file(work + '/patched-roundtrip/' + name)! == os.read_file(work + '/second-roundtrip/' + name)!
		}
		println('SECURE-SETTINGS-ROUNDTRIP-PASS two-classes retained-ten-methods insert-String-values exact-catch-span-handler API28-tile-broadcast stable-second-DEX')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_settings_secure_source(before)!
	verify(before, after)!
	assert after == before + '\n' + expected + '\n'
	invalids := [after,
		before.replace('.class public final Landroid/provider/Settings$Secure;', '.class public Landroid/provider/Settings$Secure;'),
		before + '\n.class public final Landroid/provider/Settings$Secure;\n',
		before.replace('.super Landroid/provider/Settings$NameValueTable;', '.super Ljava/lang/Object;'),
		before + '\n.super Landroid/provider/Settings$NameValueTable;\n',
		before + '\n.field private fakeStore:Ljava/util/Map;\n',
		before.replace('TAG:Ljava/lang/String; = "Settings$Secure"', 'TAG:Ljava/lang/String; = "Wrong"'),
		before + '\n.end method\n', before + '\n.method\tpublic unrelated()V\n.end method\n',
		before.replace('.end method', ''), before + '\n' + (methods(before)!)['<init>()V'],
		before.replace('.method public static getUriFor(', '.method public getUriFor(')]
	for invalid in invalids {
		assert invalid != before
		os.write_file(path, invalid)!
		mut rejected := false
		androidtools.framework_settings_secure(work + '/proof') or { rejected = true }
		assert rejected && os.read_file(path)! == invalid, 'refusal must precede writes'
	}
	for broken in [
		after.replace(expected, expected.replace('{v0, v1, p2}', '{v0, v1, p1}')),
		after.replace(expected, expected.replace('Settings$Secure;->CONTENT_URI', 'Settings$Global;->CONTENT_URI')),
		after.replace(expected, expected.replace('if-eqz v0, :failed', 'if-nez v0, :failed')),
		after.replace(expected, expected.replace('.catch Landroid/database/SQLException;', '.catch Ljava/lang/RuntimeException;')),
		after.replace(expected, expected.replace('invoke-virtual {p0, v2, v0}', 'invoke-direct {p0, v2, v0}')),
		after.replace(expected, expected.replace('{:try_start .. :try_end}', '{:try_start .. :failed}')),
		after.replace(expected, expected.replace('} :database_error', '} :failed')),
		after + '\n.field private fakeStore:Ljava/util/Map;\n',
	] {
		mut rejected := false
		verify(before, broken) or { rejected = true }
		assert rejected, 'broken argument, URI, return or exception boundary escaped oracle'
	}
	os.write_file(path, before)!
	androidtools.framework_settings_secure(work + '/proof')!
	assert os.read_file(path)! == after
	classes := androidtools.framework_quick_settings_classes()
	assert classes.keys() == [tile.all_before_last('.smali')]
	tile_source := classes.values()[0]
	verify_tile(tile_source)!
	for broken in [
		tile_source.replace('android.service.quicksettings.action.REQUEST_LISTENING', 'wrong.action'),
		tile_source.replace('com.android.systemui', 'other.systemui'),
		tile_source.replace('android.permission.BIND_QUICK_SETTINGS_TILE', 'android.permission.WRITE_SECURE_SETTINGS'),
		tile_source.replace('{v0, v1, p1}', '{v0, v1, p0}'),
		tile_source.replace('sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V', 'sendBroadcast(Landroid/content/Intent;)V'),
		tile_source.replace('Landroid/app/Service;-><init>()V', 'Ljava/lang/Object;-><init>()V'),
		tile_source.replace('.method public onBind(', '.method public static onBind('),
		tile_source + '\n.field private fakeBackend:Ljava/lang/Object;\n',
	] {
		mut rejected := false
		verify_tile(broken) or { rejected = true }
		assert rejected, 'wrong tile route or fake binder state escaped oracle'
	}
	tile_path := work + '/proof/' + tile
	os.mkdir_all(os.dir(tile_path))!
	os.write_file(tile_path, 'collision')!
	mut file_rejected := false
	androidtools.framework_quick_settings(work + '/proof') or { file_rejected = true }
	assert file_rejected && os.read_file(tile_path)! == 'collision'
	os.rm(tile_path)!
	os.mkdir(tile_path)!
	mut directory_rejected := false
	androidtools.framework_quick_settings(work + '/proof') or { directory_rejected = true }
	assert directory_rejected && os.is_dir(tile_path)
	os.rmdir(tile_path)!
	os.symlink('absent-tile-helper', tile_path)!
	mut link_rejected := false
	androidtools.framework_quick_settings(work + '/proof') or { link_rejected = true }
	assert link_rejected && os.readlink(tile_path)! == 'absent-tile-helper'
	os.rm(tile_path)!
	androidtools.framework_quick_settings(work + '/proof')!
	assert os.read_file(tile_path)! == tile_source && os.read_file(path)! == after
	assert os.walk_ext(work + '/proof', '.smali').len == 2
	println('SECURE-SETTINGS-SOURCE-PASS refusals=' + (invalids.len + 3).str() + ' semantic-controls=16 retained-ten-methods two-String-entries database-only-failure API28-tile-route')
}
