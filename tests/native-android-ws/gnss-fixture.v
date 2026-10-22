// SPDX-License-Identifier: GPL-2.0-or-later
// Run on ART/native WS: callback linkage, dispatch and GNSS value/Parcel contracts.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	mut body := '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void\n.end method\n' +
		'.method public onCreate(Landroid/os/Bundle;)V\n.locals 5\ninvoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\ninvoke-static {}, Lorg/vinix/bootstrap/Main;->values()V\n'
	for event, received in {
		'GnssMeasurementsEvent': 'onGnssMeasurementsReceived'
		'GnssNavigationMessage': 'onGnssNavigationMessageReceived'
	} {
		base := 'Landroid/location/' + event + '$Callback;'
		payload := 'Landroid/location/' + event + ';'
		for recording in [false, true] {
			name := 'Lorg/vinix/bootstrap/' + event + if recording {
				'Recording;'
			} else {
				'Default;'
			}
			mut text := '.class public ' + name + '\n.super ' + base + '\n' +
				'.field public calls:I\n.method public constructor <init>()V\n.locals 0\n' +
				'invoke-direct {p0}, ' + base + '-><init>()V\nreturn-void\n.end method\n'
			if recording {
				for signature in [received + '(' + payload + ')V', 'onStatusChanged(I)V'] {
					text += '.method public ' + signature + '\n.locals 1\n' +
						'invoke-super {p0, p1}, ' + base + '->' + signature + '\n' +
						'iget v0, p0, ' + name + '->calls:I\nadd-int/lit8 v0, v0, 1\n' +
						'iput v0, p0, ' + name + '->calls:I\nreturn-void\n.end method\n'
				}
			}
			os.write_file(root + '/' + name.all_after_last('/').trim_right(';') + '.smali', text)!
			body += 'new-instance v0, ' + name + '\ninvoke-direct {v0}, ' + name + '-><init>()V\n' +
				'const/4 v1, 0\ninvoke-virtual {v0, v1}, ' + base + '->' + received + '(' + payload + ')V\n'
			for index, status in ['STATUS_NOT_SUPPORTED', 'STATUS_READY', 'STATUS_LOCATION_DISABLED'] {
				body += 'sget v1, ' + base + '->' + status + ':I\nconst/4 v2, ' + index.str() + '\n' +
					'if-ne v1, v2, :bad\ninvoke-virtual {v0, v1}, ' + base + '->onStatusChanged(I)V\n'
			}
			body += 'iget v1, v0, ' + name + '->calls:I\nconst/4 v2, ' + if recording {
				'4'
			} else {
				'0'
			} + '\nif-ne v1, v2, :bad\n'
		}
	}
	body += 'const-string v0, "location"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/location/LocationManager;
invoke-virtual {v0}, Landroid/location/LocationManager;->isLocationEnabled()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/location/LocationManager;->getAllProviders()Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->isEmpty()Z
move-result v1
if-eqz v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "GNSS-CALLBACK-PASS constructors default-methods virtual-dispatch constants values parcel no-providers"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "GNSS callback and value checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GNSS callback contract failed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
'
	os.write_file(root + '/Main.smali', body + value_checks())!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o',
		dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	println('GNSS-CALLBACK-APK ' + out + '/probe.apk')
}

fn value_checks() string {
	return '
.method public static values()V
.locals 8
new-instance v0, Landroid/location/GnssClock;
invoke-direct {v0}, Landroid/location/GnssClock;-><init>()V
invoke-virtual {v0}, Landroid/location/GnssClock;->hasBiasNanos()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/location/GnssClock;->getBiasNanos()D
move-result-wide v1
invoke-static {v1, v2}, Ljava/lang/Double;->isNaN(D)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/location/GnssClock;->getTimeNanos()J
move-result-wide v1
const-wide v3, -0x8000000000000000L
cmp-long v1, v1, v3
if-nez v1, :bad
const-wide/16 v1, 123
invoke-virtual {v0, v1, v2}, Landroid/location/GnssClock;->setElapsedRealtimeNanos(J)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v5
const/4 v6, 0
invoke-virtual {v0, v5, v6}, Landroid/location/GnssClock;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v5, v6}, Landroid/os/Parcel;->setDataPosition(I)V
# Independent wire check: elapsed-realtime presence flag precedes leap-second and time.
invoke-virtual {v5}, Landroid/os/Parcel;->readInt()I
move-result v1
const/16 v2, 128
if-ne v1, v2, :bad
invoke-virtual {v5}, Landroid/os/Parcel;->readInt()I
move-result v1
const v2, -0x80000000
if-ne v1, v2, :bad
invoke-virtual {v5}, Landroid/os/Parcel;->readLong()J
move-result-wide v1
const-wide v3, -0x8000000000000000L
cmp-long v1, v1, v3
if-nez v1, :bad
invoke-virtual {v5, v6}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v7, Landroid/location/GnssClock;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v7, v5}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v7
check-cast v7, Landroid/location/GnssClock;
invoke-virtual {v7}, Landroid/location/GnssClock;->getElapsedRealtimeNanos()J
move-result-wide v1
const-wide/16 v3, 123
cmp-long v1, v1, v3
if-nez v1, :bad
invoke-virtual {v7}, Landroid/location/GnssClock;->hasElapsedRealtimeNanos()Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v5}, Landroid/os/Parcel;->dataAvail()I
move-result v1
if-nez v1, :bad
invoke-virtual {v5}, Landroid/os/Parcel;->recycle()V
new-instance v1, Landroid/location/GnssMeasurement;
invoke-direct {v1}, Landroid/location/GnssMeasurement;-><init>()V
invoke-virtual {v1}, Landroid/location/GnssMeasurement;->hasCarrierFrequencyHz()Z
move-result v2
if-nez v2, :bad
const-wide v2, 0x3ff8000000000000L
invoke-virtual {v1, v2, v3}, Landroid/location/GnssMeasurement;->setSnrInDb(D)V
const/4 v2, 7
invoke-virtual {v1, v2}, Landroid/location/GnssMeasurement;->setSvid(I)V
new-instance v2, Landroid/location/GnssMeasurement;
invoke-direct {v2}, Landroid/location/GnssMeasurement;-><init>()V
invoke-virtual {v2, v1}, Landroid/location/GnssMeasurement;->set(Landroid/location/GnssMeasurement;)V
invoke-virtual {v1}, Landroid/location/GnssMeasurement;->resetSnrInDb()V
invoke-virtual {v1}, Landroid/location/GnssMeasurement;->hasSnrInDb()Z
move-result v3
if-nez v3, :bad
invoke-virtual {v2}, Landroid/location/GnssMeasurement;->hasSnrInDb()Z
move-result v3
if-eqz v3, :bad
const/4 v3, 1
new-array v3, v3, [Landroid/location/GnssMeasurement;
aput-object v2, v3, v6
new-instance v1, Landroid/location/GnssMeasurementsEvent;
invoke-direct {v1, v0, v3}, Landroid/location/GnssMeasurementsEvent;-><init>(Landroid/location/GnssClock;[Landroid/location/GnssMeasurement;)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v5
invoke-virtual {v1, v5, v6}, Landroid/location/GnssMeasurementsEvent;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v5, v6}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v7, Landroid/location/GnssMeasurementsEvent;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v7, v5}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/location/GnssMeasurementsEvent;
invoke-virtual {v1}, Landroid/location/GnssMeasurementsEvent;->getMeasurements()Ljava/util/Collection;
move-result-object v1
invoke-interface {v1}, Ljava/util/Collection;->size()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :bad
invoke-interface {v1}, Ljava/util/Collection;->iterator()Ljava/util/Iterator;
move-result-object v2
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/location/GnssMeasurement;
invoke-virtual {v2}, Landroid/location/GnssMeasurement;->getSvid()I
move-result v3
const/4 v4, 7
if-ne v3, v4, :bad
invoke-virtual {v2}, Landroid/location/GnssMeasurement;->getSnrInDb()D
move-result-wide v2
const-wide v6, 0x3ff8000000000000L
cmpl-double v2, v2, v6
if-nez v2, :bad
:try_start
invoke-interface {v1}, Ljava/util/Collection;->clear()V
:try_end
goto :bad
.catch Ljava/lang/UnsupportedOperationException; {:try_start .. :try_end} :immutable
:immutable
move-exception v1
invoke-virtual {v5}, Landroid/os/Parcel;->dataAvail()I
move-result v1
if-nez v1, :bad
invoke-virtual {v5}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->navigation()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GNSS value/Parcel contract failed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method

.method public static navigation()V
.locals 6
new-instance v0, Landroid/location/GnssNavigationMessage;
invoke-direct {v0}, Landroid/location/GnssNavigationMessage;-><init>()V
invoke-virtual {v0}, Landroid/location/GnssNavigationMessage;->getMessageId()I
move-result v1
const/4 v2, -1
if-ne v1, v2, :bad
const/4 v1, 2
new-array v1, v1, [B
const/4 v2, 0
const/16 v3, 42
aput-byte v3, v1, v2
invoke-virtual {v0, v1}, Landroid/location/GnssNavigationMessage;->setData([B)V
sget v1, Landroid/location/GnssNavigationMessage;->TYPE_GPS_L1CA:I
invoke-virtual {v0, v1}, Landroid/location/GnssNavigationMessage;->setType(I)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v4
invoke-virtual {v0, v4, v2}, Landroid/location/GnssNavigationMessage;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v4, v2}, Landroid/os/Parcel;->setDataPosition(I)V
# Independent wire check: type, svid, message/submessage, explicit and array lengths.
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v1
const/16 v3, 0x101
if-ne v1, v3, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v1
if-nez v1, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v1
const/4 v3, -1
if-ne v1, v3, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v1
if-ne v1, v3, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v1
const/4 v3, 2
if-ne v1, v3, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->createByteArray()[B
move-result-object v1
array-length v5, v1
if-ne v5, v3, :bad
aget-byte v1, v1, v2
const/16 v3, 42
if-ne v1, v3, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v1
if-nez v1, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->dataAvail()I
move-result v1
if-nez v1, :bad
invoke-virtual {v4, v2}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v5, Landroid/location/GnssNavigationMessage;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v5, v4}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v5
check-cast v5, Landroid/location/GnssNavigationMessage;
invoke-virtual {v5}, Landroid/location/GnssNavigationMessage;->getData()[B
move-result-object v1
aget-byte v1, v1, v2
if-ne v1, v3, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->recycle()V
:try_start
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/location/GnssNavigationMessage;->setData([B)V
:try_end
goto :bad
.catch Ljava/security/InvalidParameterException; {:try_start .. :try_end} :invalid
:invalid
move-exception v1
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GNSS navigation wire contract failed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
'
}
