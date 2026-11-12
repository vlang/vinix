// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_serial_tls_cache(smali string) ! {
	build := smali + '/android/os/Build.smali'
	cache := smali + '/android/net/SSLSessionCache.smali'
	new_build := framework_replace_method(os.read_file(build)!, 'getSerial()Ljava/lang/String;', r'
.method public static getSerial()Ljava/lang/String;
.locals 2
new-instance v0, Ljava/lang/SecurityException;
const-string v1, "Hardware serial access is not authorized"
invoke-direct {v0, v1}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V
throw v0
.end method')!
	// This deployment has no authorized hardware-serial service. Preserve the
	// caller's permission-denial path instead of exposing a host identifier.
	// The cache overload selects the app-private directory and delegates to
	// the existing File overload. It adds no TLS/session persistence backend.
	new_cache := framework_replace_method(os.read_file(cache)!, '<init>(Landroid/content/Context;)V', r'
.method public constructor <init>(Landroid/content/Context;)V
.locals 2
const-string v0, "sslcache"
const/4 v1, 0
invoke-virtual {p1, v0, v1}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;
move-result-object v0
invoke-direct {p0, v0}, Landroid/net/SSLSessionCache;-><init>(Ljava/io/File;)V
return-void
.end method')!
	os.write_file(build, new_build)!
	os.write_file(cache, new_cache)!
}
