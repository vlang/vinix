// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Android 10's request/callback ABI and one-pending-request behavior:
// platform/frameworks/base dff3deab5d25f8bbfd49abfb423043c9be47b7db,
// core/java/android/app/Activity.java requestPermissions and
// dispatchRequestPermissionsResult; PackageManager.buildRequestPermissionsIntent.
// Vinix has no permission-controller UI. Return the existing PackageManager
// decisions asynchronously without changing grants or inventing location data.
fn framework_activity_permissions(smali string) ! {
	path := smali + '/android/app/Activity.smali'
	mut text := os.read_file(path)!
	field := '.field vinixHasCurrentPermissionsRequest:Z\n'
	if !text.contains(field) {
		text = text.replace('.super Landroid/view/ContextThemeWrapper;\n',
			'.super Landroid/view/ContextThemeWrapper;\n' + field)
	}
	text = framework_replace_method(text, 'requestPermissions([Ljava/lang/String;I)V', '
.method public final requestPermissions([Ljava/lang/String;I)V
.locals 8
if-ltz p2, :bad_code
iget-boolean v0, p0, Landroid/app/Activity;->vinixHasCurrentPermissionsRequest:Z
if-eqz v0, :new_request
const/4 v0, 0
new-array v1, v0, [Ljava/lang/String;
new-array v2, v0, [I
invoke-virtual {p0, p2, v1, v2}, Landroid/app/Activity;->onRequestPermissionsResult(I[Ljava/lang/String;[I)V
return-void
:new_request
if-eqz p1, :bad_permissions
array-length v0, p1
if-eqz v0, :bad_permissions
invoke-virtual {p1}, [Ljava/lang/String;->clone()Ljava/lang/Object;
move-result-object v1
check-cast v1, [Ljava/lang/String;
new-array v2, v0, [I
invoke-virtual {p0}, Landroid/app/Activity;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v3
invoke-virtual {p0}, Landroid/app/Activity;->getPackageName()Ljava/lang/String;
move-result-object v4
const/4 v5, 0
:decision
if-ge v5, v0, :enqueue
aget-object v6, v1, v5
invoke-virtual {v3, v6, v4}, Landroid/content/pm/PackageManager;->checkPermission(Ljava/lang/String;Ljava/lang/String;)I
move-result v6
aput v6, v2, v5
add-int/lit8 v5, v5, 1
goto :decision
:enqueue
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v3
new-instance v4, Landroid/os/Handler;
invoke-direct {v4, v3}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v7, Landroid/app/VinixPermissionResult;
invoke-direct {v7, p0, p2, v1, v2}, Landroid/app/VinixPermissionResult;-><init>(Landroid/app/Activity;I[Ljava/lang/String;[I)V
const/4 v0, 1
iput-boolean v0, p0, Landroid/app/Activity;->vinixHasCurrentPermissionsRequest:Z
invoke-virtual {v4, v7}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-nez v0, :done
const/4 v0, 0
iput-boolean v0, p0, Landroid/app/Activity;->vinixHasCurrentPermissionsRequest:Z
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "main thread is shutting down"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void
:bad_code
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "requestCode should be >= 0"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:bad_permissions
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "permission cannot be null or empty"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
.end method')!
	text = framework_replace_method(text,
		'onRequestPermissionsResult(I[Ljava/lang/String;[I)V', '
.method public onRequestPermissionsResult(I[Ljava/lang/String;[I)V
.locals 0
return-void
.end method')!
	os.write_file(path, text)!
	// Same-package access keeps the pending flag outside the public API. Clear it
	// before virtual dispatch so an app can request again inside its callback.
	// A destroyed Activity cannot receive a queued result; recreation routing is
	// outside this local, fixed-policy request path.
	os.write_file(smali + '/android/app/VinixPermissionResult.smali', '
.class final Landroid/app/VinixPermissionResult;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private final owner:Landroid/app/Activity;
.field private final requestCode:I
.field private final permissions:[Ljava/lang/String;
.field private final grantResults:[I
.method constructor <init>(Landroid/app/Activity;I[Ljava/lang/String;[I)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/app/VinixPermissionResult;->owner:Landroid/app/Activity;
iput p2, p0, Landroid/app/VinixPermissionResult;->requestCode:I
iput-object p3, p0, Landroid/app/VinixPermissionResult;->permissions:[Ljava/lang/String;
iput-object p4, p0, Landroid/app/VinixPermissionResult;->grantResults:[I
return-void
.end method
.method public run()V
.locals 4
iget-object v0, p0, Landroid/app/VinixPermissionResult;->owner:Landroid/app/Activity;
const/4 v1, 0
iput-boolean v1, v0, Landroid/app/Activity;->vinixHasCurrentPermissionsRequest:Z
invoke-virtual {v0}, Landroid/app/Activity;->isDestroyed()Z
move-result v1
if-nez v1, :done
iget v1, p0, Landroid/app/VinixPermissionResult;->requestCode:I
iget-object v2, p0, Landroid/app/VinixPermissionResult;->permissions:[Ljava/lang/String;
iget-object v3, p0, Landroid/app/VinixPermissionResult;->grantResults:[I
invoke-virtual {v0, v1, v2, v3}, Landroid/app/Activity;->onRequestPermissionsResult(I[Ljava/lang/String;[I)V
:done
return-void
.end method
')!
}
