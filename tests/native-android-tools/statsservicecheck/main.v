// SPDX-License-Identifier: GPL-2.0-or-later
// Source/ABI proof for a loadable type and an explicitly unsupported service.
module main

import androidtools
import os

const target = 'android/app/ContextImpl.smali'
const manager = 'android/app/StatsManager'
const signature = 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'

fn marker_source() string {
	return '.class public final Landroid/app/StatsManager;\n.super Ljava/lang/Object;\n'
}

fn guard() string {
	return '\nconst-class v0, Landroid/app/StatsManager;\nif-ne p1, v0, :vinix_stats_unavailable_other\nconst/4 v0, 0x0\nreturn-object v0\n:vinix_stats_unavailable_other\n'
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete method required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

// Compare branch structure independently of baksmali's shifted offset labels.
fn labels(source string) string {
	mut names := map[string]string{}
	mut result := ''
	mut index := 0
	for index < source.len {
		if source[index] != `:` {
			result += source[index..index + 1]
			index++
			continue
		}
		mut end := index + 1
		for end < source.len && (source[end].is_alnum() || source[end] in [`_`, `$`, `-`]) { end++ }
		name := source[index..end]
		if name !in names { names[name] = ':label_' + names.len.str() }
		result += names[name]
		index = end
	}
	return result
}

fn frozen_method() string {
	return '.method public getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
.registers 3
const-class v0, Landroid/content/pm/CrossProfileApps;
if-ne p1, v0, :cond_6
const/4 v0, 0x0
return-object v0
:cond_6
const-class v0, Landroid/service/persistentdata/PersistentDataBlockManager;
if-ne p1, v0, :cond_c
const/4 v0, 0x0
return-object v0
:cond_c
const-class v0, Landroid/net/wifi/rtt/WifiRttManager;
if-ne p1, v0, :cond_12
const/4 v0, 0x0
return-object v0
:cond_12
invoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixRttFallbackClass(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v0
return-object v0
.end method'
}

fn verify_context(old string, patched string, raw bool) ! {
	before, after := methods(old)!, methods(patched)!
	if before.len != after.len || signature !in before || signature !in after {
		return error('exact retained ContextImpl method membership required')
	}
	for name, body in before {
		if name != signature && after[name] != body {
			return error('changed retained method: ' + name)
		}
	}
	if old.replace(before[signature], '') != patched.replace(after[signature], '') {
		return error('ContextImpl metadata changed')
	}
	if raw {
		if patched != old.replace(before[signature], before[signature].replace('.registers 3', '.registers 3' + guard())) {
			return error('exact leading stats guard required')
		}
		return
	}
	if norm(before[signature]) != frozen_method() {
		return error('canonical frozen fallback required')
	}
	lines := norm(after[signature]).split_into_lines()
	if lines.len < 8 || lines[..3] != ['.method public ' + signature, '.registers 3',
		'const-class v0, Landroid/app/StatsManager;']
		|| !lines[3].starts_with('if-ne p1, v0, :') || lines[4..6] != [
		'const/4 v0, 0x0',
		'return-object v0',
	] {
		return error('canonical null stats guard differs')
	}
	branch := lines[3].all_after_last(', ')
	if lines[6] != branch || lines[7..].contains(branch) {
		return error('stats branch target differs')
	}
	remaining := lines[..2].join('\n') + '\n' + lines[7..].join('\n')
	if labels(remaining) != labels(norm(before[signature])) {
		return error('retained fallback instructions or labels changed')
	}
}

fn files(root string) ![]string {
	mut result := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		match os.lstat(path)!.get_filetype() {
			.regular { result << path }
			.directory { result << files(path)! }
			else { return error('unexpected proof file type: ' + path) }
		}
	}
	return result.sorted()
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	added := androidtools.framework_stats_service_classes()
	assert added.keys() == [manager] && added[manager] == marker_source(), 'exact memberless final marker required'
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		assert files(work + '/baseline-roundtrip')! == [work + '/baseline-roundtrip/' + target]
		for name in ['patched-roundtrip', 'second-roundtrip'] {
			assert files(work + '/' + name)! == [work + '/' + name + '/' + target,
				work + '/' + name + '/' + manager + '.smali'].sorted()
		}
		old := os.read_file(work + '/baseline-roundtrip/' + target)!
		patched := os.read_file(work + '/patched-roundtrip/' + target)!
		verify_context(old, patched, false)!
		for kind in [target, manager + '.smali'] {
			assert os.read_file(work + '/patched-roundtrip/' + kind)! == os.read_file(work + '/second-roundtrip/' + kind)!, 'unstable second DEX'
		}
		assert norm(os.read_file(work + '/patched-roundtrip/' + manager + '.smali')!) == norm(marker_source())
		println('STATS-SERVICE-ROUNDTRIP-PASS classes=2 memberless-final-marker null-service retained-fallbacks stable-second-DEX')
		return
	}
	root := work + '/proof'
	path, class_path := root + '/' + target, root + '/' + manager + '.smali'
	assert files(root)! == [path], 'isolated ContextImpl proof required'
	old := os.read_file(path)!
	getter := (methods(old)!)[signature]
	assert norm(getter) == frozen_method(), 'frozen canonical input required'
	patched := androidtools.framework_stats_service_source(old)!
	verify_context(old, patched, true)!
	mut invalids := [patched,
		old.replace('.class public final Landroid/app/ContextImpl;', '.class public Landroid/app/ContextImpl;'),
		old.replace('.class public final Landroid/app/ContextImpl;', '.class public final Lwrong/ContextImpl;'),
		old + '\n.class public final Landroid/app/ContextImpl;\n',
		old + '\n.class\tpublic final Landroid/app/ContextImpl;\n',
		old.replace('.super Landroid/content/Context;', '.super Ljava/lang/Object;'),
		old + '\n.super Landroid/content/Context;\n', old + '\n.super\tLandroid/content/Context;\n',
		old.replace(getter, ''), old + '\n' + getter,
		old + '\n.method\tpublic ' + signature + '\n.end method\n', old + '\n.end method\n',
		old + '\n.end\tmethod\n',
		old.replace(getter, getter.replace('.method public ', '.method private ')),
		old.replace(getter, getter.replace('.method public ', '.method public static ')),
		old.replace(getter, getter.replace('.method public ', '.method public native ')),
		old.replace(getter, getter.replace('.registers 3', '.registers 4')),
		old.replace(getter, getter.replace('.end method', '')),
		old.replace(getter, getter.replace('CrossProfileApps;', 'OtherManager;')),
		old.replace(getter, getter.replace('PersistentDataBlockManager;', 'OtherManager;')),
		old.replace(getter, getter.replace('WifiRttManager;', 'WifiManager;')),
		old.replace(getter, getter.replace('if-ne p1, v0', 'if-eq p1, v0')),
		old.replace(getter, getter.replace('vinixRttFallbackClass(', 'wrongFallbackClass(')),
		old.replace(getter, getter.replace('invoke-direct {p0, p1}', 'invoke-direct {p1, p0}')),
		old.replace(getter, getter.replace('move-result-object v0', 'move-result v0')),
		old.replace(getter, getter.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
		old.replace(getter, getter.replace(':cond_6', ':changed_branch')),
		old.replace(getter, getter.replace(':cond_c', ':cond_6'))]
	for instruction in norm(getter).split_into_lines().filter(!it.starts_with('.method ') && it != '.end method') {
		invalids << old.replace(getter, getter.replace(instruction, '# removed retained instruction'))
	}
	for invalid in invalids {
		assert invalid != old, 'negative mutation no longer applies'
		os.write_file(path, invalid)!
		mut rejected := false
		androidtools.framework_stats_service(root) or { rejected = true }
		assert rejected && os.read_file(path)! == invalid && !os.exists(class_path) && !os.is_link(class_path), 'refusal must precede writes'
		assert files(root)! == [path], 'refusal changed directory membership'
	}
	raw_getter := getter.replace(':cond_6', ':vinix_cross_profile_other')
		.replace(':cond_c', ':vinix_persistent_data_other').replace(':cond_12', ':cond_6')
	assert raw_getter != getter
	raw := old.replace(getter, raw_getter)
	verify_context(raw, androidtools.framework_stats_service_source(raw)!, true)!
	// Independent output oracle rejects a nonnull/incorrect guard and any
	// changed original member; marker membership is checked separately above.
	for broken in [
		patched.replace(guard(), guard().replace('const/4 v0, 0x0', 'new-instance v0, Landroid/app/StatsManager;')),
		patched.replace(guard(), guard().replace('if-ne p1, v0', 'if-eq p1, v0')),
		patched.replace(guard(), guard().replace('return-object v0', 'return-void')),
		patched + '\n.field private fakeStats:I\n',
	] {
		mut rejected := false
		verify_context(old, broken, true) or { rejected = true }
		assert rejected, 'wrong guard or member change escaped output oracle'
	}
	os.write_file(path, old)!
	os.mkdir_all(os.dir(class_path))!
	sentinel := 'owned collision fixture\x00\xff'
	os.write_file(class_path, sentinel)!
	mut file_rejected := false
	androidtools.framework_stats_service(root) or { file_rejected = true }
	assert file_rejected && os.read_file(path)! == old && os.read_file(class_path)! == sentinel
	os.rm(class_path)!
	os.mkdir(class_path)!
	os.write_file(class_path + '/sentinel', sentinel)!
	mut directory_rejected := false
	androidtools.framework_stats_service(root) or { directory_rejected = true }
	assert directory_rejected && os.read_file(path)! == old && os.ls(class_path)! == ['sentinel']
	assert os.read_file(class_path + '/sentinel')! == sentinel
	os.rm(class_path + '/sentinel')!
	os.rmdir(class_path)!
	os.symlink('absent-stats-marker-target', class_path)!
	mut link_rejected := false
	androidtools.framework_stats_service(root) or { link_rejected = true }
	assert link_rejected && os.read_file(path)! == old && os.is_link(class_path)
	assert os.readlink(class_path)! == 'absent-stats-marker-target'
	os.rm(class_path)!
	androidtools.framework_stats_service(root)!
	assert os.read_file(path)! == patched && os.read_file(class_path)! == marker_source()
	assert files(root)! == [path, class_path].sorted(), 'exact two output files required'
	println('STATS-SERVICE-SOURCE-PASS rejected=' + (invalids.len + 3).str() +
		' semantic-controls=4 one-guard memberless-final-marker retained-methods validation-before-writes')
}
