// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_stats_service_classes() map[string]string {
	// The service is unsupported. The type must resolve for a null check-cast,
	// without advertising a manager, a stats daemon or successful telemetry.
	return {
		'android/app/StatsManager': '.class public final Landroid/app/StatsManager;\n.super Ljava/lang/Object;\n'
	}
}

fn stats_service_directive(line string, name string) bool {
	parts := line.fields()
	return parts.len > 0 && parts[0] == name
}

fn stats_service_typed_method(source string) !string {
	signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
	lines := source.split_into_lines().map(it.trim_space())
	headers := lines.filter(stats_service_directive(it, '.method'))
	if headers.filter(it.fields().last() == signature) != ['.method public ' + signature] {
		return error('unique canonical public typed service declaration required')
	}
	if lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end'
		&& it.fields()[1] == 'method').len != headers.len {
		return error('balanced ContextImpl methods required')
	}
	mut found := ''
	for block in source.split('.method ')[1..] {
		header := block.all_before('\n')
		if header.all_after_last(' ') != signature { continue }
		if found != '' || header != 'public ' + signature {
			return error('unique public typed service lookup required')
		}
		end := block.index('.end method') or { return error('unterminated typed service lookup') }
		found = '.method ' + block[..end] + '.end method'
	}
	if found == '' { return error('typed service lookup missing') }
	return found
}

pub fn framework_stats_service_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(stats_service_directive(it, '.class')) != ['.class public final Landroid/app/ContextImpl;']
		|| lines.filter(stats_service_directive(it, '.super')) != ['.super Landroid/content/Context;'] {
		return error('canonical ContextImpl required for unsupported stats service')
	}
	old := stats_service_typed_method(original)!
	actual := old.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
	expected := '.method public getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
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
	// Preserve either the sealed canonical DEX spelling or the exact raw labels
	// emitted by the preceding unsupported cross-profile service provider.
	raw := expected.replace(':cond_6', ':vinix_cross_profile_other')
		.replace(':cond_c', ':vinix_persistent_data_other').replace(':cond_12', ':cond_6')
	if actual != expected && actual != raw {
		return error('retained typed service fallback instructions required')
	}
	guard := '\nconst-class v0, Landroid/app/StatsManager;\nif-ne p1, v0, :vinix_stats_unavailable_other\nconst/4 v0, 0x0\nreturn-object v0\n:vinix_stats_unavailable_other\n'
	return original.replace(old, old.replace('.registers 3', '.registers 3' + guard))
}

pub fn framework_stats_service(smali string) ! {
	context := smali + '/android/app/ContextImpl.smali'
	patched := framework_stats_service_source(os.read_file(context)!)!
	classes := framework_stats_service_classes()
	for name, _ in classes {
		path := smali + '/' + name + '.smali'
		if os.exists(path) || os.is_link(path) {
			return error('stats manager API type already exists')
		}
	}
	// Validate the retained lookup and all new type paths before writing.
	for name, source in classes {
		path := smali + '/' + name + '.smali'
		os.mkdir_all(os.dir(path))!
		os.write_file(path, source)!
	}
	os.write_file(context, patched)!
}
