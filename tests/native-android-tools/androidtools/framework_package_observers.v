// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_package_observers(smali string) ! {
	for name, callback in {
		'IPackageDeleteObserver': 'packageDeleted(Ljava/lang/String;I)V'
		'IPackageDataObserver':   'onRemoveCompleted(Ljava/lang/String;Z)V'
	} {
		path := smali + '/android/content/pm/' + name + '.smali'
		old := os.read_file(path)!
		if old.all_before('\n') != '.class Landroid/content/pm/' + name + ';'
			|| old.count('.method ') != 1 || !old.contains('.method constructor <init>()V') {
			return error('original package observer placeholder required: ' + name)
		}
		// A callback type, not package deletion authority or a package-manager service.
		os.write_file(path, '.class public interface abstract Landroid/content/pm/' + name + ';
.super Ljava/lang/Object;
.implements Landroid/os/IInterface;

.method public abstract ' + callback + '
.annotation system Ldalvik/annotation/Throws;
value = { Landroid/os/RemoteException; }
.end annotation
.end method
')!
	}
}
