// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_absent_hardware(smali string) ! {
	// No modem is connected to native WS. Android uses UNKNOWN_CARRIER_ID
	// and null names when the subscription or telephony service is unavailable.
	path := smali + '/android/telephony/TelephonyManager.smali'
	mut text := os.read_file(path)!
	if !text.contains(' UNKNOWN_CARRIER_ID:') {
		text += '\n.field public static final UNKNOWN_CARRIER_ID:I = -0x1\n'
	}
	for name in ['getSimCarrierId', 'getSimSpecificCarrierId', 'getCarrierIdFromSimMccMnc'] {
		text = framework_replace_method(text, name + '()I', '.method public ' + name + '()I\n.locals 1\nconst/4 v0, -1\nreturn v0\n.end method')!
	}
	for name in ['getSimCarrierIdName', 'getSimSpecificCarrierIdName'] {
		text = framework_replace_method(text, name + '()Ljava/lang/CharSequence;', '.method public ' + name + '()Ljava/lang/CharSequence;\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method')!
	}
	os.write_file(path, text)!
	// The API type must resolve even when getSystemService returns null for
	// unsupported hardware: check-cast on a null reference still resolves it.
	// Do not register a context-hub service or advertise a context-hub feature.
	os.mkdir_all(smali + '/android/hardware/location')!
	os.write_file(smali + '/android/hardware/location/ContextHubManager.smali',
		'.class public final Landroid/hardware/location/ContextHubManager;\n.super Ljava/lang/Object;\n' +
		'.method private constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
		'.method public getContextHubs()Ljava/util/List;\n.locals 1\ninvoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;\nmove-result-object v0\nreturn-object v0\n.end method\n')!
	context := smali + '/android/content/Context.smali'
	mut base := os.read_file(context)!
	if !base.contains(' CONTEXTHUB_SERVICE:') {
		base += '\n.field public static final CONTEXTHUB_SERVICE:Ljava/lang/String; = "contexthub"\n'
	}
	os.write_file(context, base)!
}
