// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The single-user guest has no administrator or application restrictions store.
// Android returns an empty Bundle when no restrictions are saved. Allocate it
// for every query so a caller cannot change another query's result.
pub fn framework_application_restrictions_method() string {
	return '.method public getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
    .locals 1
    new-instance v0, Landroid/os/Bundle;
    invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
    return-object v0
.end method'
}

pub fn framework_application_restrictions_user_manager(source string) !string {
	if source.split_into_lines().filter(it.starts_with('.class ')) != ['.class public Landroid/os/UserManager;']
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| source.split_into_lines().any(it.starts_with('.field '))
		|| source.count('.method ') != 6 || source.count('.end method') != 6
		|| source.contains('getApplicationRestrictions(') {
		return error('unexpected or already extended UserManager restrictions class')
	}
	for declaration in [
		'public constructor <init>()V',
		'public static supportsMultipleUsers()Z',
		'public getSerialNumberForUser(Landroid/os/UserHandle;)J',
		'public getUserProfiles()Ljava/util/List;',
		'public isSystemUser()Z',
		'public isUserUnlocked()Z',
	] {
		if source.count('.method ' + declaration + '\n') != 1 {
			return error('missing exact UserManager method: ' + declaration)
		}
	}
	return source + '\n' + framework_application_restrictions_method() + '\n'
}

fn framework_application_restrictions_api(smali string) ! {
	path := smali + '/android/os/UserManager.smali'
	os.write_file(path, framework_application_restrictions_user_manager(os.read_file(path)!)!)!
}
