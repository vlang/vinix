// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_update_policy(smali string) ! {
	policy := smali + '/android/app/admin/SystemUpdatePolicy.smali'
	if os.exists(policy) { return error('system update policy type already exists') }
	manager := smali + '/android/app/admin/DevicePolicyManager.smali'
	mut source := os.read_file(manager)!
	if source.contains(' getSystemUpdatePolicy()') { return error('system update policy query already exists') }
	// The desktop runtime has no device owner or managed-update backend.
	// A nullable query still requires its return type to be resolvable. Do not
	// invent a policy or enable device-management/update authority.
	os.write_file(policy, r'.class public final Landroid/app/admin/SystemUpdatePolicy;
.super Ljava/lang/Object;
.method private constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
')!
	source += signature_method('public getSystemUpdatePolicy()Landroid/app/admin/SystemUpdatePolicy;',
		'const/4 v0, 0\nreturn-object v0')
	os.write_file(manager, source)!
}
