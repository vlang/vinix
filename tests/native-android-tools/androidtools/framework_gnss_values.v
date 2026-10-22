// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

struct GnssField {
	api     string
	kind    string
	mask    int
	initial string
}

// Android 10 value layout, including optional-value presence bits and sentinel
// defaults. These objects hold caller-supplied data; they do not provide GNSS.
// Reference: platform/frameworks/base, android-10.0.0_r1, location/java/android/location.
fn framework_gnss_values(smali string) ! {
	clock := [
		GnssField{'', 'I', 0, '0'},
		GnssField{'LeapSecond', 'I', 1, '-0x80000000'},
		GnssField{'TimeNanos', 'J', 0, '-0x8000000000000000L'},
		GnssField{'TimeUncertaintyNanos', 'D', 2, '0x7ff8000000000000L'},
		GnssField{'FullBiasNanos', 'J', 4, '-0x8000000000000000L'},
		GnssField{'BiasNanos', 'D', 8, '0x7ff8000000000000L'},
		GnssField{'BiasUncertaintyNanos', 'D', 16, '0x7ff8000000000000L'},
		GnssField{'DriftNanosPerSecond', 'D', 32, '0x7ff8000000000000L'},
		GnssField{'DriftUncertaintyNanosPerSecond', 'D', 64, '0x7ff8000000000000L'},
		GnssField{'HardwareClockDiscontinuityCount', 'I', 0, '-0x80000000'},
		GnssField{'ElapsedRealtimeNanos', 'J', 128, '0'},
		GnssField{'ElapsedRealtimeUncertaintyNanos', 'D', 256, '0x7ff8000000000000L'},
	]
	measurement := [
		GnssField{'', 'I', 0, '0'},
		GnssField{'Svid', 'I', 0, '0'},
		GnssField{'ConstellationType', 'I', 0, '0'},
		GnssField{'TimeOffsetNanos', 'D', 0, '-0x3c20000000000000L'},
		GnssField{'State', 'I', 0, '0'},
		GnssField{'ReceivedSvTimeNanos', 'J', 0, '-0x8000000000000000L'},
		GnssField{'ReceivedSvTimeUncertaintyNanos', 'J', 0, '0x7fffffffffffffffL'},
		GnssField{'Cn0DbHz', 'D', 0, '1'},
		GnssField{'PseudorangeRateMetersPerSecond', 'D', 0, '1'},
		GnssField{'PseudorangeRateUncertaintyMetersPerSecond', 'D', 0, '1'},
		GnssField{'AccumulatedDeltaRangeState', 'I', 0, '0'},
		GnssField{'AccumulatedDeltaRangeMeters', 'D', 0, '1'},
		GnssField{'AccumulatedDeltaRangeUncertaintyMeters', 'D', 0, '1'},
		GnssField{'CarrierFrequencyHz', 'F', 512, '0x7fc00000'},
		GnssField{'CarrierCycles', 'J', 1024, '-0x8000000000000000L'},
		GnssField{'CarrierPhase', 'D', 2048, '0x7ff8000000000000L'},
		GnssField{'CarrierPhaseUncertainty', 'D', 4096, '0x7ff8000000000000L'},
		GnssField{'MultipathIndicator', 'I', 0, '0'},
		GnssField{'SnrInDb', 'D', 1, '0x7ff8000000000000L'},
		GnssField{'AutomaticGainControlLevelInDb', 'D', 8192, '0x7ff8000000000000L'},
		GnssField{'CodeType', 'Ljava/lang/String;', 16384, 'UNKNOWN'},
	]
	for name, fields in {
		'GnssClock':       clock
		'GnssMeasurement': measurement
	} {
		owner := 'Landroid/location/' + name + ';'
		mut text := gnss_value_header(name)
		if name == 'GnssMeasurement' {
			text += gnss_measurement_constants()
		}
		mut reset, copy, write, read := '', '', '', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
		for index, field in fields {
			ref := owner + '->value' + index.str() + ':' + field.kind
			wide := field.kind in ['J', 'D']
			object := field.kind.starts_with('L')
			op := if wide {
				'-wide'
			} else if object {
				'-object'
			} else {
				''
			}
			wire := match field.kind {
				'J' { 'Long' }
				'D' { 'Double' }
				'F' { 'Float' }
				'I' { 'Int' }
				else { 'String' }
			}
			text += '.field private value' + index.str() + ':' + field.kind + '\n'
			initial := if object {
				'const-string v0, "' + field.initial + '"\n'
			} else {
				'const' + if wide { '-wide' } else { '' } + ' v0, ' + field.initial + '\n'
			}
			reset += initial + 'iput' + op + ' v0, p0, ' + ref + '\n'
			copy += 'iget' + op + ' v0, p1, ' + ref + '\niput' + op + ' v0, p0, ' + ref + '\n'
			write += 'iget' + op + ' v0, p0, ' + ref + '\ninvoke-virtual {p1, v0' + if wide {
				', v1'
			} else {
				''
			} + '}, Landroid/os/Parcel;->write' + wire + '(' + field.kind + ')V\n'
			read += 'invoke-virtual {p1}, Landroid/os/Parcel;->read' + wire + '()' + field.kind + '\nmove-result' + op + ' v0\niput' + op + ' v0, p0, ' + ref + '\n'
			if field.api == '' { continue }
			text += location_method('public get' + field.api + '()' + field.kind, 'iget' + op + ' v0, p0, ' + ref + '\nreturn' + op + ' v0')
			mut setter := 'iput' + op + ' p1, p0, ' + ref + '\n'
			if field.mask != 0 {
				flags := owner + '->value0:I'
				setter += 'iget v0, p0, ' + flags + '\nconst v1, ' + field.mask.str() + '\nor-int/2addr v0, v1\niput v0, p0, ' + flags + '\n'
				has_api := if field.api == 'AutomaticGainControlLevelInDb' {
					'AutomaticGainControlLevelDb'
				} else {
					field.api
				}
				reset_api := if field.api == 'AutomaticGainControlLevelInDb' {
					'AutomaticGainControlLevel'
				} else {
					field.api
				}
				text += location_method('public has' + has_api + '()Z', 'iget v0, p0, ' + flags + '\nconst v1, ' + field.mask.str() + '\nand-int/2addr v0, v1\nif-eqz v0, :absent\nconst/4 v0, 1\n:absent\nreturn v0')
				text += location_method('public reset' + reset_api + '()V', initial + 'iput' + op + ' v0, p0, ' + ref + '\niget v0, p0, ' + flags + '\nconst v1, ' + (~field.mask).str() + '\nand-int/2addr v0, v1\niput v0, p0, ' + flags + '\nreturn-void')
			}
			text += location_method('public set' + field.api + '(' + field.kind + ')V', setter + 'return-void')
		}
		text += location_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-virtual {p0}, ' + owner + '->reset()V\nreturn-void') +
			location_method('public reset()V', reset + 'return-void') + location_method('public set(' + owner + ')V', copy + 'return-void') +
			location_method('public constructor <init>(Landroid/os/Parcel;)V', read + 'return-void') +
			location_method('public writeToParcel(Landroid/os/Parcel;I)V', write + 'return-void')
		os.write_file(smali + '/android/location/' + name + '.smali', text)!
		gnss_creator(smali, name)!
	}
	framework_gnss_navigation(smali)!
	framework_gnss_event(smali)!
}

fn gnss_measurement_constants() string {
	mut text := '.field public static final STATE_UNKNOWN:I = 0\n.field public static final ADR_STATE_UNKNOWN:I = 0\n.field public static final ADR_STATE_ALL:I = 31\n'
	for index, name in ['CODE_LOCK', 'BIT_SYNC', 'SUBFRAME_SYNC', 'TOW_DECODED', 'MSEC_AMBIGUOUS',
		'SYMBOL_SYNC', 'GLO_STRING_SYNC', 'GLO_TOD_DECODED', 'BDS_D2_BIT_SYNC', 'BDS_D2_SUBFRAME_SYNC',
		'GAL_E1BC_CODE_LOCK', 'GAL_E1C_2ND_CODE_LOCK', 'GAL_E1B_PAGE_SYNC', 'SBAS_SYNC', 'TOW_KNOWN',
		'GLO_TOD_KNOWN', '2ND_CODE_LOCK'] {
		text += '.field public static final STATE_' + name + ':I = ' + (1 << index).str() + '\n'
	}
	for index, name in ['VALID', 'RESET', 'CYCLE_SLIP', 'HALF_CYCLE_RESOLVED', 'HALF_CYCLE_REPORTED'] {
		text += '.field public static final ADR_STATE_' + name + ':I = ' + (1 << index).str() + '\n'
	}
	for index, name in ['UNKNOWN', 'DETECTED', 'NOT_DETECTED'] {
		text += '.field public static final MULTIPATH_INDICATOR_' + name + ':I = ' + index.str() + '\n'
	}
	return text
}

fn gnss_value_header(name string) string {
	owner := 'Landroid/location/' + name + ';'
	creator := 'Landroid/location/Vinix' + name + 'Creator;'
	return '.class public final ' + owner + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
		'.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n' +
		location_method('static constructor <clinit>()V', 'new-instance v0, ' + creator + '\ninvoke-direct {v0}, ' + creator + '-><init>()V\nsput-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void') +
		location_method('public describeContents()I', 'const/4 v0, 0\nreturn v0')
}

fn gnss_creator(smali string, name string) ! {
	owner := 'Landroid/location/' + name + ';'
	creator := 'Landroid/location/Vinix' + name + 'Creator;'
	os.write_file(smali + '/android/location/Vinix' + name + 'Creator.smali',
		'.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
			location_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
			location_method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'new-instance v0, ' + owner + '\ninvoke-direct {v0, p1}, ' + owner + '-><init>(Landroid/os/Parcel;)V\nreturn-object v0') +
			location_method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [' + owner + '\nreturn-object v0'))!
}

fn framework_gnss_navigation(smali string) ! {
	name := 'GnssNavigationMessage'
	owner := 'Landroid/location/' + name + ';'
	mut text := gnss_value_header(name)
	for key, value in {
		'TYPE_UNKNOWN':          0
		'TYPE_GPS_L1CA':         0x101
		'TYPE_GPS_L2CNAV':       0x102
		'TYPE_GPS_L5CNAV':       0x103
		'TYPE_GPS_CNAV2':        0x104
		'TYPE_GLO_L1CA':         0x301
		'TYPE_BDS_D1':           0x501
		'TYPE_BDS_D2':           0x502
		'TYPE_GAL_I':            0x601
		'TYPE_GAL_F':            0x602
		'STATUS_UNKNOWN':        0
		'STATUS_PARITY_PASSED':  1
		'STATUS_PARITY_REBUILT': 2
	} {
		text += '.field public static final ' + key + ':I = ' + value.str() + '\n'
	}
	mut reset, copy, read, write := '', '', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n', ''
	for api in ['Type', 'Svid', 'MessageId', 'SubmessageId', 'Data', 'Status'] {
		data := api == 'Data'
		kind, op := if data { '[B' } else { 'I' }, if data { '-object' } else { '' }
		ref := owner + '->' + api + ':' + kind
		text += '.field private ' + api + ':' + kind + '\n'
		text += location_method('public get' + api + '()' + kind, 'iget' + op + ' v0, p0, ' + ref + '\nreturn' + op + ' v0')
		guard := if data {
			'if-nez p1, :valid\nnew-instance v0, Ljava/security/InvalidParameterException;\ninvoke-direct {v0}, Ljava/security/InvalidParameterException;-><init>()V\nthrow v0\n:valid\n'
		} else {
			''
		}
		text += location_method('public set' + api + '(' + kind + ')V', guard + 'iput' + op + ' p1, p0, ' + ref + '\nreturn-void')
		reset += 'const/4 v0, ' + if api in ['MessageId', 'SubmessageId'] { '-1' } else { '0' } + '\n' + if data {
			'new-array v0, v0, [B\n'
		} else {
			''
		} + 'iput' + op + ' v0, p0, ' + ref + '\n'
		copy += 'iget' + op + ' v0, p1, ' + ref + '\niput' + op + ' v0, p0, ' + ref + '\n'
		write += 'iget' + op + ' v0, p0, ' + ref + '\n' + if data {
			'array-length v1, v0\ninvoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeByteArray([B)V\n'
		} else {
			'invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n'
		}
		read += if data {
			'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nnew-array v0, v0, [B\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->readByteArray([B)V\n'
		} else {
			'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\n'
		} + 'iput' + op + ' v0, p0, ' + ref + '\n'
	}
	text += location_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-virtual {p0}, ' + owner + '->reset()V\nreturn-void') +
		location_method('public reset()V', reset + 'return-void') + location_method('public set(' + owner + ')V', copy + 'return-void') +
		location_method('public constructor <init>(Landroid/os/Parcel;)V', read + 'return-void') + location_method('public writeToParcel(Landroid/os/Parcel;I)V', write + 'return-void')
	os.write_file(smali + '/android/location/' + name + '.smali', text)!
	gnss_creator(smali, name)!
}

fn framework_gnss_event(smali string) ! {
	name := 'GnssMeasurementsEvent'
	owner := 'Landroid/location/' + name + ';'
	mut text := gnss_value_header(name) + '.field private clock:Landroid/location/GnssClock;\n.field private measurements:Ljava/util/Collection;\n'
	text += location_method('public constructor <init>(Landroid/location/GnssClock;[Landroid/location/GnssMeasurement;)V',
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nif-nez p1, :clock\nnew-instance v0, Ljava/security/InvalidParameterException;\ninvoke-direct {v0}, Ljava/security/InvalidParameterException;-><init>()V\nthrow v0\n:clock\niput-object p1, p0, ' + owner + '->clock:Landroid/location/GnssClock;\n' +
			'if-eqz p2, :empty\narray-length v0, p2\nif-eqz v0, :empty\ninvoke-static {p2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;\nmove-result-object v0\ninvoke-static {v0}, Ljava/util/Collections;->unmodifiableCollection(Ljava/util/Collection;)Ljava/util/Collection;\nmove-result-object v0\ngoto :store\n:empty\ninvoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;\nmove-result-object v0\n:store\niput-object v0, p0, ' + owner + '->measurements:Ljava/util/Collection;\nreturn-void')
	text += location_method('public getClock()Landroid/location/GnssClock;', 'iget-object v0, p0, ' + owner + '->clock:Landroid/location/GnssClock;\nreturn-object v0') +
		location_method('public getMeasurements()Ljava/util/Collection;', 'iget-object v0, p0, ' + owner + '->measurements:Ljava/util/Collection;\nreturn-object v0')
	text += location_method('public writeToParcel(Landroid/os/Parcel;I)V', 'iget-object v0, p0, ' + owner + '->clock:Landroid/location/GnssClock;\ninvoke-virtual {p1, v0, p2}, Landroid/os/Parcel;->writeParcelable(Landroid/os/Parcelable;I)V\n' +
		'iget-object v0, p0, ' + owner + '->measurements:Ljava/util/Collection;\ninvoke-interface {v0}, Ljava/util/Collection;->size()I\nmove-result v1\nnew-array v2, v1, [Landroid/location/GnssMeasurement;\ninvoke-interface {v0, v2}, Ljava/util/Collection;->toArray([Ljava/lang/Object;)[Ljava/lang/Object;\nmove-result-object v2\ncheck-cast v2, [Landroid/location/GnssMeasurement;\ninvoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {p1, v2, p2}, Landroid/os/Parcel;->writeTypedArray([Landroid/os/Parcelable;I)V\nreturn-void')
	text += location_method('public constructor <init>(Landroid/os/Parcel;)V', 'const-class v0, Landroid/location/GnssClock;\ninvoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;\nmove-result-object v0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;\nmove-result-object v0\ncheck-cast v0, Landroid/location/GnssClock;\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v1\nnew-array v1, v1, [Landroid/location/GnssMeasurement;\nsget-object v2, Landroid/location/GnssMeasurement;->CREATOR:Landroid/os/Parcelable$Creator;\ninvoke-virtual {p1, v1, v2}, Landroid/os/Parcel;->readTypedArray([Ljava/lang/Object;Landroid/os/Parcelable$Creator;)V\ninvoke-direct {p0, v0, v1}, ' + owner + '-><init>(Landroid/location/GnssClock;[Landroid/location/GnssMeasurement;)V\nreturn-void')
	os.write_file(smali + '/android/location/' + name + '.smali', text)!
	gnss_creator(smali, name)!
}
