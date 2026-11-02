// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_quick_settings_classes() map[string]string {
	// API 28 requests listening through a permission-constrained SystemUI
	// broadcast. No SystemUI or Quick Settings binder backend is installed here.
	return {
		'android/service/quicksettings/TileService': '.class public Landroid/service/quicksettings/TileService;
.super Landroid/app/Service;

.method public constructor <init>()V
.registers 1
invoke-direct {p0}, Landroid/app/Service;-><init>()V
return-void
.end method

.method public onBind(Landroid/content/Intent;)Landroid/os/IBinder;
.registers 3
const/4 v0, 0x0
return-object v0
.end method

.method public static final requestListeningState(Landroid/content/Context;Landroid/content/ComponentName;)V
.registers 4
new-instance v0, Landroid/content/Intent;
const-string v1, "android.service.quicksettings.action.REQUEST_LISTENING"
invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v1, "android.intent.extra.COMPONENT_NAME"
invoke-virtual {v0, v1, p1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;
const-string v1, "com.android.systemui"
invoke-virtual {v0, v1}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "android.permission.BIND_QUICK_SETTINGS_TILE"
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V
return-void
.end method
'
	}
}

pub fn framework_quick_settings(smali string) ! {
	classes := framework_quick_settings_classes()
	for name, _ in classes {
		path := smali + '/' + name + '.smali'
		if os.exists(path) || os.is_link(path) { return error('Quick Settings class collision') }
	}
	for name, source in classes {
		path := smali + '/' + name + '.smali'
		os.mkdir_all(os.dir(path))!
		os.write_file(path, source)!
	}
}
