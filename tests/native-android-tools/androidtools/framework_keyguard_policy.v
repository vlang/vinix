// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Without an Android policy service, no administrator has disabled keyguard
// features. Android returns KEYGUARD_DISABLE_FEATURES_NONE for either a named
// administrator or the null aggregate query in this state.
pub fn framework_keyguard_policy_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [
		'.class public Landroid/app/admin/DevicePolicyManager;',
	] || lines.filter(it.fields().len > 0 && it.fields()[0] == '.super') != [
		'.super Ljava/lang/Object;',
	] || lines.any(it.fields().len > 0 && it.fields()[0] in ['.field', '.implements']) {
		return error('canonical fieldless DevicePolicyManager required')
	}
	expected := ['.method public constructor <init>()V',
		'.method public getActiveAdmins()Ljava/util/List;',
		'.method public getDeviceOwner()Ljava/lang/String;',
		'.method public getDeviceOwnerComponentOnAnyUser()Landroid/content/ComponentName;',
		'.method public getDeviceOwnerComponentOnCallingUser()Landroid/content/ComponentName;',
		'.method public getProfileOwner()Landroid/content/ComponentName;',
		'.method public isAdminActive(Landroid/content/ComponentName;)Z',
		'.method public isDeviceManaged()Z', '.method public isDeviceOwnerApp(Ljava/lang/String;)Z',
		'.method public isProfileOwnerApp(Ljava/lang/String;)Z']
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end'
		&& it.fields()[1] == 'method')
	blocks := original.split('.method ')[1..]
	if headers.sorted() != expected.sorted() || blocks.len != expected.len
		|| ends.len != expected.len || ends.any(it != '.end method') {
		return error('exact original DevicePolicyManager method schema required')
	}
	for block in blocks {
		if block.count('.end method') != 1 {
			return error('complete DevicePolicyManager methods required')
		}
	}
	return original + '\n.method public getKeyguardDisabledFeatures(Landroid/content/ComponentName;)I\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method\n'
}

pub fn framework_keyguard_policy(smali string) ! {
	path := smali + '/android/app/admin/DevicePolicyManager.smali'
	patched := framework_keyguard_policy_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}
