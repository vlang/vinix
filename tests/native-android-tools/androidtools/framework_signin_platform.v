// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

struct SigninPlatformMember {
	class  string
	method string
	body   string
}

// Platform members GMS's sign-in fragment (MinuteMaid) and its mm JavaScript
// interface call outside android.webkit, found by framework-api-gaps over those
// classes. r124 exited on Settings.System.getConfiguration once the WebView
// was complete. Vinix has one user, no managed profiles, no USB ports and no
// carrier apps, so these give AOSP's results for that device.
const signin_platform_members = [
	// A hidden API that fills the font scale from settings; the default scale
	// already in the configuration is the only value Vinix stores.
	SigninPlatformMember{'android/provider/Settings$System',
		'public static getConfiguration(Landroid/content/ContentResolver;Landroid/content/res/Configuration;)V',
		'.locals 0\nreturn-void'},
	// AOSP stores integers as their decimal text.
	SigninPlatformMember{'android/provider/Settings$Secure',
		'public static putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z',
		'.locals 1\ninvoke-static {p2}, Ljava/lang/String;->valueOf(I)Ljava/lang/String;\nmove-result-object v0\ninvoke-static {p0, p1, v0}, Landroid/provider/Settings$Secure;->putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z\nmove-result v0\nreturn v0'},
	SigninPlatformMember{'android/os/UserManager', 'public isManagedProfile(I)Z',
		'.locals 1\ninvoke-virtual {p0}, Landroid/os/UserManager;->isManagedProfile()Z\nmove-result v0\nreturn v0'},
	SigninPlatformMember{'android/app/admin/DevicePolicyManager',
		'public getProfileOwnerNameAsUser(I)Ljava/lang/String;', '.locals 1\nconst/4 v0, 0x0\nreturn-object v0'},
	SigninPlatformMember{'android/hardware/usb/UsbManager', 'public getPorts()Ljava/util/List;',
		'.locals 1\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\nreturn-object v0'},
	SigninPlatformMember{'android/telephony/TelephonyManager',
		'public getCarrierPackageNamesForIntent(Landroid/content/Intent;)Ljava/util/List;',
		'.locals 1\nconst/4 v0, 0x0\nreturn-object v0'},
]

pub fn signin_platform_classes() []string {
	mut classes := []string{}
	for member in signin_platform_members {
		if member.class !in classes {
			classes << member.class
		}
	}
	return classes
}

pub fn framework_signin_platform_source(class string, original string) !string {
	if original.count('.class public ') != 1 || !original.contains(' L' + class + ';\n') {
		return error('canonical ' + class + ' input required')
	}
	if class == 'android/provider/Settings$Secure'
		&& !original.contains('.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z\n') {
		return error('Settings.Secure.putString required')
	}
	if class == 'android/os/UserManager' && !original.contains('.method public isManagedProfile()Z\n') {
		return error('UserManager.isManagedProfile() required')
	}
	mut source := original
	for member in signin_platform_members {
		if member.class != class {
			continue
		}
		name := member.method.all_after_last(' ')
		if original.contains(' ' + name + '\n') {
			return error(class + ' already has ' + name)
		}
		source += '\n.method ' + member.method + '\n' + member.body + '\n.end method\n'
	}
	return source
}

pub fn framework_signin_platform(smali string) ! {
	for class in signin_platform_classes() {
		path := smali + '/' + class + '.smali'
		os.write_file(path, framework_signin_platform_source(class, os.read_file(path)!)!)!
	}
}
