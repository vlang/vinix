// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

struct LocationField {
	name string
	kind string
	api string
	wire string
	mask int
}

// Android 11 Location wire order. Retain the original double-backed fields and
// internal constructor used by ATL, while exposing Android's float accessors.
const location_fields = [
	LocationField{'provider', 'Ljava/lang/String;', 'Provider', 'String', 0},
	LocationField{'timestamp', 'J', 'Time', 'Long', 0},
	LocationField{'elapsedRealtimeNanos', 'J', 'ElapsedRealtimeNanos', 'Long', 0},
	LocationField{'elapsedRealtimeUncertaintyNanos', 'D', 'ElapsedRealtimeUncertaintyNanos', 'Double', 256},
	LocationField{'fieldsMask', 'I', '', 'Int', 0},
	LocationField{'latitude', 'D', 'Latitude', 'Double', 0},
	LocationField{'longitude', 'D', 'Longitude', 'Double', 0},
	LocationField{'altitude', 'D', 'Altitude', 'Double', 1},
	LocationField{'speed', 'D', 'Speed', 'Float', 2},
	LocationField{'bearing', 'D', 'Bearing', 'Float', 4},
	LocationField{'accuracy', 'D', 'Accuracy', 'Float', 8},
	LocationField{'verticalAccuracyMeters', 'F', 'VerticalAccuracyMeters', 'Float', 32},
	LocationField{'speedAccuracyMetersPerSecond', 'F', 'SpeedAccuracyMetersPerSecond', 'Float', 64},
	LocationField{'bearingAccuracyDegrees', 'F', 'BearingAccuracyDegrees', 'Float', 128},
	LocationField{'extras', 'Landroid/os/Bundle;', 'Extras', 'Bundle', 0},
]

fn location_method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 6\n' + body + '\n.end method\n'
}

fn framework_location_value(smali string) ! {
	owner := 'Landroid/location/Location;'
	creator := 'Landroid/location/VinixLocationCreator;'
	path := smali + '/android/location/Location.smali'
	original := os.read_file(path)!
	start := original.index('.method public constructor <init>(DDDDDDJ)V') or { return error('missing ATL Location constructor') }
	end := start + (original[start..].index('.end method') or { return error('unterminated ATL Location constructor') }) + '.end method'.len
	legacy := original[start..end].replace('return-void', 'invoke-direct {p0}, ' + owner + '->vinixLegacyFields()V\nreturn-void')
	mut text := '.class public ' + owner + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n'
	mut copy := ''
	mut reset := ''
	mut write := ''
	mut read := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
	for field in location_fields {
		ref := owner + '->' + field.name + ':' + field.kind
		object := field.kind.starts_with('L')
		wide := field.kind in ['D', 'J']
		op := if object { '-object' } else if wide { '-wide' } else { '' }
		api_kind := if field.wire == 'Float' { 'F' } else { field.kind }
		wire_kind := if field.wire == 'Float' { 'F' } else { field.kind }
		text += '.field private ' + field.name + ':' + field.kind + '\n'
		copy += 'iget' + op + ' v0, p1, ' + ref + '\n' + if field.name == 'extras' { 'if-eqz v0, :extras_copied\nnew-instance v1, Landroid/os/Bundle;\ninvoke-direct {v1, v0}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V\nmove-object v0, v1\n:extras_copied\n' } else { '' } + 'iput' + op + ' v0, p0, ' + ref + '\n'
		reset += if wide { 'const-wide/16 v0, 0\n' } else { 'const/4 v0, 0\n' } + 'iput' + op + ' v0, p0, ' + ref + '\n'
		write += 'iget' + op + ' v0, p0, ' + ref + '\n' + if field.kind == 'D' && field.wire == 'Float' { 'double-to-float v0, v0\n' } else { '' } +
			'invoke-virtual {p1, v0' + if field.wire in ['Long', 'Double'] { ', v1' } else { '' } + '}, Landroid/os/Parcel;->write' + field.wire + '(' + wire_kind + ')V\n'
		read += 'invoke-virtual {p1}, Landroid/os/Parcel;->read' + field.wire + '()' + wire_kind + '\nmove-result' + if object { '-object' } else if field.wire in ['Long', 'Double'] { '-wide' } else { '' } + ' v0\n' +
			if field.kind == 'D' && field.wire == 'Float' { 'float-to-double v0, v0\n' } else { '' } + 'iput' + op + ' v0, p0, ' + ref + '\n'
		if field.api == '' { continue }
		text += location_method('public get' + field.api + '()' + api_kind, 'iget' + op + ' v0, p0, ' + ref + '\n' +
			if field.kind == 'D' && field.wire == 'Float' { 'double-to-float v0, v0\n' } else { '' } +
			'return' + if object { '-object' } else if api_kind in ['J', 'D'] { '-wide' } else { '' } + ' v0')
		mut setter := ''
		if field.name == 'extras' {
			setter = 'move-object v0, p1\nif-eqz v0, :extras_copied\nnew-instance v0, Landroid/os/Bundle;\ninvoke-direct {v0, p1}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V\n:extras_copied\niput-object v0, p0, ' + ref + '\n'
		} else {
			if field.name == 'bearing' {
				setter += 'const v0, 0x43b40000\nrem-float p1, p1, v0\nconst/4 v1, 0\ncmpg-float v1, p1, v1\nif-gez v1, :normalized\nadd-float/2addr p1, v0\n:normalized\n'
			}
			setter += if field.kind == 'D' && api_kind == 'F' { 'float-to-double v0, p1\niput-wide v0, p0, ' + ref + '\n' } else { 'iput' + op + ' p1, p0, ' + ref + '\n' }
		}
		if field.mask != 0 {
			presence := match field.name {
				'verticalAccuracyMeters' { 'VerticalAccuracy' }
				'speedAccuracyMetersPerSecond' { 'SpeedAccuracy' }
				'bearingAccuracyDegrees' { 'BearingAccuracy' }
				else { field.api }
			}
			setter += 'iget v0, p0, ' + owner + '->fieldsMask:I\nconst/16 v1, ' + field.mask.str() + '\nor-int/2addr v0, v1\niput v0, p0, ' + owner + '->fieldsMask:I\n'
			text += location_method('public has' + presence + '()Z', 'iget v0, p0, ' + owner + '->fieldsMask:I\nconst/16 v1, ' + field.mask.str() + '\nand-int/2addr v0, v1\nif-eqz v0, :done\nconst/4 v0, 1\n:done\nreturn v0') +
				location_method('public remove' + presence + '()V', if wide { 'const-wide/16 v0, 0\n' } else { 'const/4 v0, 0\n' } + 'iput' + op + ' v0, p0, ' + ref + '\niget v0, p0, ' + owner + '->fieldsMask:I\nconst/16 v1, ' + (~field.mask).str() + '\nand-int/2addr v0, v1\niput v0, p0, ' + owner + '->fieldsMask:I\nreturn-void')
		}
		text += location_method('public set' + field.api + '(' + api_kind + ')V', setter + 'return-void')
	}
	mut legacy_fields := 'const-string v0, "fused"\niput-object v0, p0, ' + owner + '->provider:Ljava/lang/String;\nconst/16 v4, 8\n'
	for field in location_fields {
		if field.name !in ['altitude', 'speed', 'bearing'] { continue }
		legacy_fields += 'iget-wide v0, p0, ' + owner + '->' + field.name + ':D\nconst-wide v2, ' + if field.name == 'altitude' { '-0x10000000000001L' } else { '-0x4010000000000000L' } + '\ncmpl-double v0, v0, v2\nif-eqz v0, :absent_' + field.name + '\nor-int/lit8 v4, v4, ' + field.mask.str() + '\n:absent_' + field.name + '\n'
	}
	text += legacy + '\n' +
		location_method('private vinixLegacyFields()V', legacy_fields + 'iput v4, p0, ' + owner + '->fieldsMask:I\nreturn-void') +
		location_method('public constructor <init>(Ljava/lang/String;)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + owner + '->provider:Ljava/lang/String;\nreturn-void') +
		location_method('public constructor <init>(' + owner + ')V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-virtual {p0, p1}, ' + owner + '->set(' + owner + ')V\nreturn-void') +
		location_method('public set(' + owner + ')V', copy + 'return-void') +
		location_method('public reset()V', reset + 'return-void') +
		location_method('public isFromMockProvider()Z', 'iget v0, p0, ' + owner + '->fieldsMask:I\nand-int/lit8 v0, v0, 16\nif-eqz v0, :done\nconst/4 v0, 1\n:done\nreturn v0') +
		location_method('public setIsFromMockProvider(Z)V', 'iget v0, p0, ' + owner + '->fieldsMask:I\nand-int/lit8 v0, v0, -17\nif-eqz p1, :done\nor-int/lit8 v0, v0, 16\n:done\niput v0, p0, ' + owner + '->fieldsMask:I\nreturn-void') +
		location_method('public describeContents()I', 'const/4 v0, 0\nreturn v0') +
		location_method('public writeToParcel(Landroid/os/Parcel;I)V', write + 'return-void') +
		location_method('public constructor <init>(Landroid/os/Parcel;)V', read + 'return-void') +
		location_method('static constructor <clinit>()V', 'new-instance v0, ' + creator + '\ninvoke-direct {v0}, ' + creator + '-><init>()V\nsput-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
	os.write_file(path, text)!
	os.write_file(smali + '/android/location/VinixLocationCreator.smali', '.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
		location_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		location_method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'new-instance v0, ' + owner + '\ninvoke-direct {v0, p1}, ' + owner + '-><init>(Landroid/os/Parcel;)V\nreturn-object v0') +
		location_method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [' + owner + '\nreturn-object v0'))!
}
