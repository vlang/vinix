// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Applications may construct these callbacks even on devices without GNSS.
// Their default methods are no-ops; constructing one must not initialize a
// provider or manufacture a measurement. See AOSP's GnssMeasurementsEvent and
// GnssNavigationMessage callback contracts (API 24 and later).
fn framework_gnss(smali string) ! {
	framework_gnss_values(smali)!
	for event, received in {
		'GnssMeasurementsEvent': 'onGnssMeasurementsReceived'
		'GnssNavigationMessage': 'onGnssNavigationMessageReceived'
	} {
		owner := 'android/location/' + event
		mut text := '.class public abstract L' + owner + '$Callback;\n.super Ljava/lang/Object;\n' +
			'.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = L' + owner + ';\n.end annotation\n' +
			'.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x409\nname = "Callback"\n.end annotation\n' +
			'.field public static final STATUS_NOT_SUPPORTED:I = 0\n' +
			'.field public static final STATUS_READY:I = 1\n' +
			'.field public static final STATUS_LOCATION_DISABLED:I = 2\n'
		if event == 'GnssMeasurementsEvent' {
			text += '.field public static final STATUS_NOT_ALLOWED:I = 3\n'
		}
		text += '.method public constructor <init>()V\n.locals 0\n' +
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
			'.method public ' + received + '(L' + owner + ';)V\n.locals 0\nreturn-void\n.end method\n' +
			'.method public onStatusChanged(I)V\n.locals 0\nreturn-void\n.end method\n'
		os.write_file(smali + '/' + owner + '$Callback.smali', text)!
	}
}
