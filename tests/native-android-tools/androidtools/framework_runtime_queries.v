// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_runtime_queries(smali string) ! {
	users := smali + '/android/os/UserManager.smali'
	mut text := os.read_file(users)!
	// This backend supports one Android user (distinct from per-app Unix UIDs).
	// Its existing serial-number mapping uses the Android user identifier.
	text = framework_replace_method(text, 'getUserCount()I',
		'.method public getUserCount()I\n.locals 1\nconst/4 v0, 1\nreturn v0\n.end method')!
	text = framework_replace_method(text, 'getUserForSerialNumber(J)Landroid/os/UserHandle;', r'
.method public getUserForSerialNumber(J)Landroid/os/UserHandle;
.locals 4
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v0
int-to-long v1, v0
cmp-long v3, v1, p1
if-nez v3, :missing
new-instance v1, Landroid/os/UserHandle;
invoke-direct {v1, v0}, Landroid/os/UserHandle;-><init>(I)V
return-object v1
:missing
const/4 v0, 0
return-object v0
.end method')!
	os.write_file(users, text)!
	network := smali + '/android/net/ConnectivityManager.smali'
	// Use one native state observation and match the handle's interface, just
	// as getNetworkCapabilities/LinkProperties do. Never substitute another
	// currently active interface for an unknown or expired handle.
	os.write_file(network, framework_replace_method(os.read_file(network)!, 'getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;', r'
.method public getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;
.locals 3
if-eqz p1, :missing
invoke-virtual {p0}, Landroid/net/ConnectivityManager;->nativeGetNetworkState()I
move-result v0
if-eqz v0, :missing
ushr-int/lit8 v1, v0, 16
iget v2, p1, Landroid/net/Network;->vinixInterface:I
if-ne v1, v2, :missing
new-instance v1, Landroid/net/NetworkInfo;
invoke-direct {v1, v0}, Landroid/net/NetworkInfo;-><init>(I)V
return-object v1
:missing
const/4 v0, 0
return-object v0
.end method')!)!
	application := smali + '/android/content/pm/ApplicationInfo.smali'
	mut info := os.read_file(application)!
	if info.contains('privateFlags:I') { return error('ApplicationInfo private flags already installed') }
	signature := '.method public constructor <init>(Landroid/content/pm/ApplicationInfo;)V'
	start := info.index(signature) or { return error('ApplicationInfo copy constructor missing') }
	end := start + info[start..].index('.end method') or { return error('copy constructor incomplete') }
	body := info[start..end]
	if body.count('return-void') != 1 || !body.contains('.registers 4') {
		return error('two-local ApplicationInfo copy constructor required')
	}
	info = info[..start] + body.replace('return-void', 'iget v0, p1, Landroid/content/pm/ApplicationInfo;->privateFlags:I\niput v0, p0, Landroid/content/pm/ApplicationInfo;->privateFlags:I\nreturn-void') + info[end..]
	info += '\n.field public privateFlags:I\n'
	info = framework_replace_method(info, 'isInstantApp()Z', r'
.method public isInstantApp()Z
.locals 1
iget v0, p0, Landroid/content/pm/ApplicationInfo;->privateFlags:I
and-int/lit16 v0, v0, 0x80
if-eqz v0, :ordinary
const/4 v0, 1
:ordinary
return v0
.end method')!
	os.write_file(application, info)!
}
