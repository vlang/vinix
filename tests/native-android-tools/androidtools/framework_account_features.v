// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

// An empty visible account set has no feature matches. Without a feature
// authenticator operation, never guess which nonempty accounts support them.
pub fn framework_account_features(smali string) ! {
	path := smali + '/android/accounts/AccountManager.smali'
	mut manager := os.read_file(path)!
	if manager.contains('getAccountsByTypeAndFeatures(') { return error('account feature query already exists') }
	future_path := smali + '/android/atl/VinixAccountFuture.smali'
	mut future := os.read_file(future_path)!
	if !future.contains('<init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;Z)V') {
		return error('pending account future required')
	}
	future += r'
.method public vinixAccounts([Landroid/accounts/Account;)V
.locals 0
invoke-super {p0, p1}, Ljava/util/concurrent/FutureTask;->set(Ljava/lang/Object;)V
return-void
.end method
'
	manager += r'
.method public getAccountsByTypeAndFeatures(Ljava/lang/String;[Ljava/lang/String;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
.locals 4
if-nez p1, :valid
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "accountType is null"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:valid
invoke-virtual {p0, p1}, Landroid/accounts/AccountManager;->getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;
move-result-object v1
new-instance v0, Landroid/atl/VinixAccountFuture;
const/4 v2, 1
invoke-direct {v0, p3, p4, v2}, Landroid/atl/VinixAccountFuture;-><init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;Z)V
array-length v2, v1
if-eqz v2, :complete
if-eqz p2, :complete
array-length v2, p2
if-eqz v2, :complete
const/4 v2, 6
const-string v3, "Authenticator feature queries unavailable"
invoke-virtual {v0, v2, v3}, Landroid/atl/VinixAccountFuture;->vinixError(ILjava/lang/String;)V
return-object v0
:complete
invoke-virtual {v0, v1}, Landroid/atl/VinixAccountFuture;->vinixAccounts([Landroid/accounts/Account;)V
return-object v0
.end method
'
	os.write_file(path, manager)!
	os.write_file(future_path, future)!
}
