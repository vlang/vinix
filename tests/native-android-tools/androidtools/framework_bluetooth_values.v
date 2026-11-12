// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Passive Parcelable values used by intent-extra type registries. These do
// not expose an adapter, discover peers or claim that a radio is available.
// Android contracts: developer.android.com/reference/android/bluetooth/BluetoothDevice
// and developer.android.com/reference/android/bluetooth/BluetoothClass.
pub fn framework_bluetooth_value_classes() map[string]string {
	mut result := map[string]string{}
	for name in ['BluetoothDevice', 'BluetoothClass'] {
		class := 'Landroid/bluetooth/' + name + ';'
		creator := 'Landroid/bluetooth/' + name + r'$VinixCreator;'
		device := name == 'BluetoothDevice'
		type_name := if device { 'Ljava/lang/String;' } else { 'I' }
		read := if device { 'readString()Ljava/lang/String;' } else { 'readInt()I' }
		write := if device { 'writeString(Ljava/lang/String;)V' } else { 'writeInt(I)V' }
		get := if device { 'iget-object' } else { 'iget' }
		put := if device { 'iput-object' } else { 'iput' }
		mut source := '.class public final ' + class + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
			'.field private final value:' + type_name + '\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n' +
			'.method static constructor <clinit>()V\n.locals 1\nnew-instance v0, ' + creator + '\ninvoke-direct {v0}, ' + creator + '-><init>()V\nsput-object v0, ' + class + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void\n.end method\n' +
			'.method constructor <init>(' + type_name + ')V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' + put + ' p1, p0, ' + class + '->value:' + type_name + '\nreturn-void\n.end method\n' +
			'.method public describeContents()I\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method\n' +
			'.method public writeToParcel(Landroid/os/Parcel;I)V\n.locals 1\n' + get + ' v0, p0, ' + class + '->value:' + type_name + '\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->' + write + '\nreturn-void\n.end method\n'
		if device {
			source = source.replace('.method constructor <init>(Ljava/lang/String;)V\n.locals 0\n',
				'.method constructor <init>(Ljava/lang/String;)V\n.locals 1\n')
			source = source.replace('iput-object p1, p0, ' + class + '->value:Ljava/lang/String;',
				'if-eqz p1, :invalid\nconst-string v0, "([0-9A-F]{2}:){5}[0-9A-F]{2}"\ninvoke-virtual {p1, v0}, Ljava/lang/String;->matches(Ljava/lang/String;)Z\nmove-result v0\nif-nez v0, :valid\n:invalid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\ninvoke-direct {v0}, Ljava/lang/IllegalArgumentException;-><init>()V\nthrow v0\n:valid\niput-object p1, p0, ' + class + '->value:Ljava/lang/String;')
			source += '.method public getAddress()Ljava/lang/String;\n.locals 1\niget-object v0, p0, ' + class + '->value:Ljava/lang/String;\nreturn-object v0\n.end method\n'
			source += '.method public toString()Ljava/lang/String;\n.locals 1\ninvoke-virtual {p0}, ' + class + '->getAddress()Ljava/lang/String;\nmove-result-object v0\nreturn-object v0\n.end method\n'
		} else {
			for method, mask in {'getDeviceClass': '0x1ffc', 'getMajorDeviceClass': '0x1f00'} {
				source += '.method public ' + method + '()I\n.locals 1\niget v0, p0, ' + class + '->value:I\nand-int/lit16 v0, v0, ' + mask + '\nreturn v0\n.end method\n'
			}
			source += '.method public hasService(I)Z\n.locals 1\niget v0, p0, ' + class + '->value:I\nconst p0, 0xffe000\nand-int/2addr p1, p0\nand-int/2addr v0, p1\nif-eqz v0, :no\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0\n.end method\n'
		}
		// Equality and hashing are value-based, without consulting hardware.
		source += '.method public equals(Ljava/lang/Object;)Z\n.locals 2\ninstance-of v0, p1, ' + class + '\nif-eqz v0, :no\ncheck-cast p1, ' + class + '\n' + get + ' v0, p0, ' + class + '->value:' + type_name + '\n' + get + ' v1, p1, ' + class + '->value:' + type_name + '\n'
		source += if device { 'invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n' } else { 'if-ne v0, v1, :no\nconst/4 v0, 1\nreturn v0\n' }
		source += ':no\nconst/4 v0, 0\nreturn v0\n.end method\n'
		source += '.method public hashCode()I\n.locals 1\n' + get + ' v0, p0, ' + class + '->value:' + type_name + '\n'
		if device { source += 'invoke-virtual {v0}, Ljava/lang/String;->hashCode()I\nmove-result v0\n' }
		source += 'return v0\n.end method\n'
		result[name + '.smali'] = source
		result[name + r'$VinixCreator.smali'] = '.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
			'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
			'.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\n.locals 2\ninvoke-virtual {p1}, Landroid/os/Parcel;->' + read + '\n' + (if device { 'move-result-object' } else { 'move-result' }) + ' v0\nnew-instance v1, ' + class + '\ninvoke-direct {v1, v0}, ' + class + '-><init>(' + type_name + ')V\nreturn-object v1\n.end method\n' +
			'.method public newArray(I)[Ljava/lang/Object;\n.locals 1\nnew-array v0, p1, [' + class + '\nreturn-object v0\n.end method\n'
	}
	return result
}

pub fn framework_bluetooth_values(smali string) ! {
	os.mkdir_all(smali + '/android/bluetooth')!
	for name, source in framework_bluetooth_value_classes() {
		os.write_file(smali + '/android/bluetooth/' + name, source)!
	}
}
