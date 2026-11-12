// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_account_package_query(smali string) ! {
	path := smali + '/android/accounts/AccountManager.smali'
	// Direct queries expose the authenticated caller's own visibility domain.
	// Foreign package strings do not grant authenticator/broker authority.
	// Android returns no accounts when a target query is outside caller scope.
	// The native store's separate ownership guard remains unchanged; broker
	// capability queries remain the only cross-package disclosure channel.
	os.write_file(path, framework_replace_method(os.read_file(path)!, 'getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;', r'
.method public getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;
.locals 2
new-instance v0, Landroid/app/AppOpsManager;
invoke-direct {v0}, Landroid/app/AppOpsManager;-><init>()V
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v1
:ownership_start
invoke-virtual {v0, v1, p2}, Landroid/app/AppOpsManager;->checkPackage(ILjava/lang/String;)V
:ownership_end
invoke-virtual {p0, p1}, Landroid/accounts/AccountManager;->getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;
move-result-object v0
return-object v0
:outside_scope
move-exception v0
const/4 v0, 0
new-array v0, v0, [Landroid/accounts/Account;
return-object v0
.catch Ljava/lang/SecurityException; {:ownership_start .. :ownership_end} :outside_scope
.end method')!)!
}
