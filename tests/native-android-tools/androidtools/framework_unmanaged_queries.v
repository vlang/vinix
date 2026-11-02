// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn unmanaged_directive(line string, name string) bool {
	parts := line.fields()
	return parts.len > 0 && parts[0] == name
}

fn unmanaged_method_end(line string) bool {
	parts := line.fields()
	return parts.len >= 2 && parts[0] == '.end' && parts[1] == 'method'
}

// The guest has no Android device owner, managed-profile enrollment or policy
// service. Preserve its existing no-administrator queries and expose that state
// through the two read-only API names used by the work-account initialization.
fn unmanaged_query_source(original string, descriptor string, expected []string, entry string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(unmanaged_directive(it, '.class')) != ['.class public ' + descriptor]
		|| lines.filter(unmanaged_directive(it, '.super')) != ['.super Ljava/lang/Object;']
		|| lines.any(unmanaged_directive(it, '.field') || unmanaged_directive(it, '.implements')) {
		return error('canonical fieldless unmanaged service class required: ' + descriptor)
	}
	mut actual := lines.filter(unmanaged_directive(it, '.method')).map(it.all_after('.method').trim_space())
	actual.sort()
	if actual != expected.sorted() || lines.filter(unmanaged_method_end(it)).len != expected.len {
		return error('exact original unmanaged service method schema required: ' + descriptor)
	}
	for block in original.split('.method ')[1..] {
		if block.count('.end method') != 1 {
			return error('balanced unmanaged service methods required: ' + descriptor)
		}
	}
	return original + entry
}

pub fn framework_device_owner_source(original string) !string {
	return unmanaged_query_source(original, 'Landroid/app/admin/DevicePolicyManager;',
		['public constructor <init>()V', 'public getActiveAdmins()Ljava/util/List;',
			'public getDeviceOwnerComponentOnCallingUser()Landroid/content/ComponentName;',
			'public getDeviceOwnerComponentOnAnyUser()Landroid/content/ComponentName;',
			'public getProfileOwner()Landroid/content/ComponentName;',
			'public isAdminActive(Landroid/content/ComponentName;)Z',
			'public isProfileOwnerApp(Ljava/lang/String;)Z',
			'public isDeviceOwnerApp(Ljava/lang/String;)Z', 'public isDeviceManaged()Z'],
		'\n.method public getDeviceOwner()Ljava/lang/String;\n    .registers 2\n\n    const/4 v0, 0x0\n\n    return-object v0\n.end method\n')
}

pub fn framework_managed_profile_source(original string) !string {
	return unmanaged_query_source(original, 'Landroid/os/UserManager;',
		['public constructor <init>()V', 'public static supportsMultipleUsers()Z',
			'public getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;',
			'public getSeedAccountOptions()Landroid/os/PersistableBundle;',
			'public getSerialNumberForUser(Landroid/os/UserHandle;)J',
			'public getUserProfiles()Ljava/util/List;',
			'public getUserRestrictions()Landroid/os/Bundle;',
			'public hasUserRestriction(Ljava/lang/String;)Z', 'public isSystemUser()Z',
			'public isUserUnlocked()Z'],
		'\n.method public isManagedProfile()Z\n    .registers 2\n\n    const/4 v0, 0x0\n\n    return v0\n.end method\n')
}

pub fn framework_unmanaged_queries(smali string) ! {
	policy := smali + '/android/app/admin/DevicePolicyManager.smali'
	user := smali + '/android/os/UserManager.smali'
	// Validate both source schemas before writing either class.
	patched_policy := framework_device_owner_source(os.read_file(policy)!)!
	patched_user := framework_managed_profile_source(os.read_file(user)!)!
	os.write_file(policy, patched_policy)!
	os.write_file(user, patched_user)!
}
