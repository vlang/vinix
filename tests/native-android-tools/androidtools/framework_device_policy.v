// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Vinix has no enrolled Android administrators or managed profiles. Expose
// that state through the read-only queries; do not advertise policy enforcement.
fn framework_device_policy(smali string) ! {
	manager := 'Landroid/app/admin/DevicePolicyManager;'
	path := smali + '/android/app/admin/DevicePolicyManager.smali'
	mut text := os.read_file(path)!
	for signature in ['getActiveAdmins()Ljava/util/List;',
		'getDeviceOwnerComponentOnCallingUser()Landroid/content/ComponentName;',
		'getDeviceOwnerComponentOnAnyUser()Landroid/content/ComponentName;',
		'getProfileOwner()Landroid/content/ComponentName;'] {
		text = framework_replace_method(text, signature, '.method public ' + signature + '
.locals 1
const/4 v0, 0
return-object v0
.end method')!
	}
	for signature in ['isAdminActive(Landroid/content/ComponentName;)Z',
		'isProfileOwnerApp(Ljava/lang/String;)Z', 'isDeviceOwnerApp(Ljava/lang/String;)Z',
		'isDeviceManaged()Z'] {
		text = framework_replace_method(text, signature, '.method public ' + signature + '
.locals 1
const/4 v0, 0
return v0
.end method')!
	}
	os.write_file(path, text)!
	context := smali + '/android/content/Context.smali'
	mut base := os.read_file(context)!
	if !base.contains(' DEVICE_POLICY_SERVICE:') {
		base += '\n.field public static final DEVICE_POLICY_SERVICE:Ljava/lang/String; = "device_policy"\n'
	}
	os.write_file(context, base)!
	implementation := smali + '/android/app/ContextImpl.smali'
	mut impl := os.read_file(implementation)!
	for kind, arg in {'String': 'Ljava/lang/String;', 'Class': 'Ljava/lang/Class;'} {
		old := '.method public getSystemService(' + arg + ')'
		if impl.count(old) != 1 { return error('unexpected device policy service lookup: ' + kind) }
		impl = impl.replace(old, '.method private vinixPolicyFallback' + kind + '(' + arg + ')')
		condition := if kind == 'String' {
			'const-string v0, "device_policy"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :other\n'
		} else {
			'const-class v0, ' + manager + '\nif-ne p1, v0, :other\n'
		}
		impl += '\n.method public getSystemService(' + arg + ')Ljava/lang/Object;\n.locals 1\n' + condition +
			'invoke-direct {p0}, Landroid/app/ContextImpl;->vinixDevicePolicy()' + manager + '\nmove-result-object v0\nreturn-object v0\n' +
			':other\ninvoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixPolicyFallback' + kind + '(' + arg + ')Ljava/lang/Object;\nmove-result-object v0\nreturn-object v0\n.end method\n'
	}
	impl += '\n.field private vinixPolicyManager:' + manager + '
.method private synchronized vinixDevicePolicy()' + manager + '
.locals 1
iget-object v0, p0, Landroid/app/ContextImpl;->vinixPolicyManager:' + manager + '
if-nez v0, :done
new-instance v0, ' + manager + '
invoke-direct {v0}, ' + manager + '-><init>()V
iput-object v0, p0, Landroid/app/ContextImpl;->vinixPolicyManager:' + manager + '
:done
return-object v0
.end method
'
	os.write_file(implementation, impl)!
}
