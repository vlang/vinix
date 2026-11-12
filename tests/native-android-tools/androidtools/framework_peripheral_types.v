// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

// These services currently expose no hardware objects. Keep their Android
// types resolvable for intent-extra registries, but reject attempts to import
// or serialize unsupported hardware parcels instead of inventing devices.
pub fn framework_peripheral_types(smali string) ! {
	for name in ['android/nfc/Tag', 'android/nfc/NdefMessage', 'android/hardware/usb/UsbDevice', 'android/hardware/usb/UsbAccessory'] {
		class := 'L' + name + ';'
		creator := 'L' + name + r'$VinixCreator;'
		os.mkdir_all(os.dir(smali + '/' + name))!
		os.write_file(smali + '/' + name + '.smali', '.class public final ' + class + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
			'.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n' +
			'.method static constructor <clinit>()V\n.locals 1\nnew-instance v0, ' + creator + '\ninvoke-direct {v0}, ' + creator + '-><init>()V\nsput-object v0, ' + class + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void\n.end method\n' +
			'.method private constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
			'.method public describeContents()I\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method\n' +
			'.method public writeToParcel(Landroid/os/Parcel;I)V\n.locals 2\nnew-instance v0, Ljava/lang/UnsupportedOperationException;\nconst-string v1, "Peripheral parcel transport unavailable"\ninvoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V\nthrow v0\n.end method\n')!
		os.write_file(smali + '/' + name + r'$VinixCreator.smali', '.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
			'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
			'.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\n.locals 2\nnew-instance v0, Landroid/os/BadParcelableException;\nconst-string v1, "Peripheral parcel transport unavailable"\ninvoke-direct {v0, v1}, Landroid/os/BadParcelableException;-><init>(Ljava/lang/String;)V\nthrow v0\n.end method\n' +
			'.method public newArray(I)[Ljava/lang/Object;\n.locals 1\nnew-array v0, p1, [' + class + '\nreturn-object v0\n.end method\n')!
	}
}
