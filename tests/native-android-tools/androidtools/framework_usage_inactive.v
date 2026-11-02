// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// This target has no AppStandby classification or enforcement backend. Match
// the disabled-policy result, without claiming measured application activity.
pub fn framework_usage_inactive_method() string {
	return '.method public isAppInactive(Ljava/lang/String;)Z\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method'
}

pub fn framework_usage_inactive_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [
		'.class public Landroid/app/usage/UsageStatsManager;',
	] || lines.filter(it.fields().len > 0 && it.fields()[0] == '.super') != [
		'.super Ljava/lang/Object;',
	] || lines.any(it.fields().len > 0 && it.fields()[0] in ['.field', '.implements']) {
		return error('canonical fieldless UsageStatsManager required')
	}
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end' && it.fields()[1] == 'method')
	blocks := original.split('.method ')[1..]
	if headers != ['.method public constructor <init>()V'] || ends != ['.end method'] || blocks.len != 1 {
		return error('exact constructor-only UsageStatsManager schema required')
	}
	constructor := '.method ' + blocks[0].all_before('.end method') + '.end method'
	if constructor.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n') !=
		'.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method'
		|| blocks[0].count('.end method') != 1 {
		return error('retained UsageStatsManager constructor required')
	}
	return original + '\n' + framework_usage_inactive_method() + '\n'
}

pub fn framework_usage_inactive(smali string) ! {
	path := smali + '/android/app/usage/UsageStatsManager.smali'
	patched := framework_usage_inactive_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}
