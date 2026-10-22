// SPDX-License-Identifier: GPL-2.0-or-later
// Two signed APKs exercise lazy companion Application/provider/service startup.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 6\n' + body + '\n.end method\n'
}

fn check_stage(expected int, next int) string {
	return 'const/4 v0, ${expected}\ninvoke-static {v0}, Lorg/vinix/service/App;->check(I)V\n' +
		'const/4 v0, ${next}\nsput v0, Lorg/vinix/service/App;->stage:I\n'
}

fn proxy_listener_checks() string {
	return 'new-instance v0, Lorg/vinix/service/ProxyListener;
invoke-direct {v0}, Lorg/vinix/service/ProxyListener;-><init>()V
new-instance v1, Landroid/os/Binder;
invoke-direct {v1}, Landroid/os/Binder;-><init>()V
const/4 v2, 7
const/4 v3, 1
invoke-interface {v0, v1, v2, v3}, Landroid/os/Binder$ProxyTransactListener;->onTransactStarted(Landroid/os/IBinder;II)Ljava/lang/Object;
move-result-object v4
if-ne v4, v0, :bad
iget v4, v0, Lorg/vinix/service/ProxyListener;->code:I
if-ne v4, v2, :bad
iget-object v4, v0, Lorg/vinix/service/ProxyListener;->binder:Landroid/os/IBinder;
if-ne v4, v1, :bad
invoke-interface {v0, v0}, Landroid/os/Binder$ProxyTransactListener;->onTransactEnded(Ljava/lang/Object;)V
iget-object v4, v0, Lorg/vinix/service/ProxyListener;->session:Ljava/lang/Object;
if-ne v4, v0, :bad
invoke-static {v0}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkBinder()V
iget v4, v0, Lorg/vinix/service/ProxyListener;->started:I
if-ne v4, v3, :bad
iget v4, v0, Lorg/vinix/service/ProxyListener;->ended:I
if-ne v4, v3, :bad
new-instance v1, Lorg/vinix/service/ProxyListener;
invoke-direct {v1}, Lorg/vinix/service/ProxyListener;-><init>()V
invoke-static {v1}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
const/4 v2, 0
invoke-static {v2}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
return-void
:bad
const/4 v0, 0
invoke-static {v0}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "proxy listener default overload and local Binder exclusion"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn proxy_listener_class(dir string) ! {
	os.write_file(dir + '/ProxyListener.smali', '.class public Lorg/vinix/service/ProxyListener;\n.super Ljava/lang/Object;\n' +
		'.implements Landroid/os/Binder$ProxyTransactListener;\n.field public started:I\n.field public ended:I\n.field public code:I\n' +
		'.field public binder:Landroid/os/IBinder;\n.field public session:Ljava/lang/Object;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public onTransactStarted(Landroid/os/IBinder;I)Ljava/lang/Object;', 'iget v0, p0, Lorg/vinix/service/ProxyListener;->started:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/service/ProxyListener;->started:I\niput p2, p0, Lorg/vinix/service/ProxyListener;->code:I\niput-object p1, p0, Lorg/vinix/service/ProxyListener;->binder:Landroid/os/IBinder;\nreturn-object p0') +
		method('public onTransactEnded(Ljava/lang/Object;)V', 'iget v0, p0, Lorg/vinix/service/ProxyListener;->ended:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/service/ProxyListener;->ended:I\niput-object p1, p0, Lorg/vinix/service/ProxyListener;->session:Ljava/lang/Object;\nreturn-void'))!
}

fn geofence_checks() string {
	return 'new-instance v0, Lorg/vinix/service/GeofenceProvider;
invoke-direct {v0}, Lorg/vinix/service/GeofenceProvider;-><init>()V
invoke-virtual {v0}, Lcom/android/location/provider/GeofenceProvider;->getBinder()Landroid/os/IBinder;
move-result-object v1
invoke-virtual {v0}, Lcom/android/location/provider/GeofenceProvider;->getBinder()Landroid/os/IBinder;
move-result-object v2
if-ne v1, v2, :bad
invoke-static {v1}, Landroid/location/IGeofenceProvider$Stub;->asInterface(Landroid/os/IBinder;)Landroid/location/IGeofenceProvider;
move-result-object v2
invoke-interface {v2}, Landroid/os/IInterface;->asBinder()Landroid/os/IBinder;
move-result-object v2
if-ne v1, v2, :bad
const/4 v2, 0
invoke-static {v2}, Landroid/location/IGeofenceProvider$Stub;->asInterface(Landroid/os/IBinder;)Landroid/location/IGeofenceProvider;
move-result-object v2
if-nez v2, :bad
new-instance v2, Lorg/vinix/service/ForwardBinder;
invoke-direct {v2, v1}, Lorg/vinix/service/ForwardBinder;-><init>(Landroid/os/IBinder;)V
invoke-static {v2}, Landroid/location/IGeofenceProvider$Stub;->asInterface(Landroid/os/IBinder;)Landroid/location/IGeofenceProvider;
move-result-object v2
new-instance v3, Lorg/vinix/service/GeofenceBackend;
invoke-direct {v3}, Lorg/vinix/service/GeofenceBackend;-><init>()V
invoke-direct {p0, v3}, Lorg/vinix/service/Main;->checkGeofenceWire(Landroid/os/IBinder;)V
new-instance v4, Lorg/vinix/service/ForwardBinder;
invoke-direct {v4, v3}, Lorg/vinix/service/ForwardBinder;-><init>(Landroid/os/IBinder;)V
invoke-static {v4}, Landroid/hardware/location/IGeofenceHardware$Stub;->asInterface(Landroid/os/IBinder;)Landroid/hardware/location/IGeofenceHardware;
move-result-object v4
invoke-interface {v2, v4}, Landroid/location/IGeofenceProvider;->setGeofenceHardware(Landroid/hardware/location/IGeofenceHardware;)V
iget v4, v0, Lorg/vinix/service/GeofenceProvider;->calls:I
const/4 v5, 1
if-ne v4, v5, :bad
iget-object v4, v0, Lorg/vinix/service/GeofenceProvider;->hardware:Landroid/hardware/location/GeofenceHardware;
if-eqz v4, :bad
invoke-virtual {v4}, Landroid/hardware/location/GeofenceHardware;->getMonitoringTypes()[I
move-result-object v2
array-length v5, v2
const/4 v1, 2
if-ne v5, v1, :bad
const/4 v5, 0
aget v1, v2, v5
if-nez v1, :bad
const/4 v5, 1
aget v1, v2, v5
if-ne v1, v5, :bad
invoke-virtual {v4, v5}, Landroid/hardware/location/GeofenceHardware;->getStatusOfMonitoringType(I)I
move-result v1
if-nez v1, :bad
const/16 v5, 99
invoke-virtual {v4, v5}, Landroid/hardware/location/GeofenceHardware;->getStatusOfMonitoringType(I)I
move-result v1
const/4 v5, 2
if-ne v1, v5, :bad
const/4 v1, 1
iput v1, v3, Lorg/vinix/service/GeofenceBackend;->failure:I
invoke-virtual {v4}, Landroid/hardware/location/GeofenceHardware;->getMonitoringTypes()[I
move-result-object v1
array-length v1, v1
if-nez v1, :bad
const/4 v5, 0
invoke-virtual {v4, v5}, Landroid/hardware/location/GeofenceHardware;->getStatusOfMonitoringType(I)I
move-result v1
const/4 v5, 2
if-ne v1, v5, :bad
iput v5, v3, Lorg/vinix/service/GeofenceBackend;->failure:I
:security_start
invoke-virtual {v4}, Landroid/hardware/location/GeofenceHardware;->getMonitoringTypes()[I
:security_end
.catch Ljava/lang/SecurityException; {:security_start .. :security_end} :security
goto :bad
:security
move-exception v1
invoke-virtual {v0}, Lcom/android/location/provider/GeofenceProvider;->getBinder()Landroid/os/IBinder;
move-result-object v0
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const-string v2, "wrong.descriptor"
invoke-virtual {v1, v2}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V
const/4 v2, 1
const/4 v3, 0
const/4 v4, 0
:token_start
invoke-interface {v0, v2, v1, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
:token_end
.catch Ljava/lang/SecurityException; {:token_start .. :token_end} :token
goto :bad
:token
move-exception v2
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
const/16 v2, 99
const/4 v1, 0
invoke-interface {v0, v2, v1, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v1
if-nez v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "geofence provider Binder and capability forwarding"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn geofence_classes(dir string) ! {
	os.write_file(dir + '/GeofenceProvider.smali', '.class public Lorg/vinix/service/GeofenceProvider;\n.super Lcom/android/location/provider/GeofenceProvider;\n' +
		'.field public calls:I\n.field public hardware:Landroid/hardware/location/GeofenceHardware;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Lcom/android/location/provider/GeofenceProvider;-><init>()V\nreturn-void') +
		method('public onGeofenceHardwareChange(Landroid/hardware/location/GeofenceHardware;)V', 'iget v0, p0, Lorg/vinix/service/GeofenceProvider;->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/service/GeofenceProvider;->calls:I\niput-object p1, p0, Lorg/vinix/service/GeofenceProvider;->hardware:Landroid/hardware/location/GeofenceHardware;\nreturn-void'))!
	os.write_file(dir + '/ForwardBinder.smali', '.class public Lorg/vinix/service/ForwardBinder;\n.super Landroid/os/Binder;\n.field private target:Landroid/os/IBinder;\n' +
		method('public constructor <init>(Landroid/os/IBinder;)V', 'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\niput-object p1, p0, Lorg/vinix/service/ForwardBinder;->target:Landroid/os/IBinder;\nreturn-void') +
		method('protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 'iget-object v0, p0, Lorg/vinix/service/ForwardBinder;->target:Landroid/os/IBinder;\ninvoke-interface {v0, p1, p2, p3, p4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0'))!
	os.write_file(dir + '/GeofenceBackend.smali', '.class public Lorg/vinix/service/GeofenceBackend;\n.super Landroid/hardware/location/IGeofenceHardware$Stub;\n.field public failure:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/hardware/location/IGeofenceHardware$Stub;-><init>()V\nreturn-void') +
		method('private checkFailure()V', 'iget v0, p0, Lorg/vinix/service/GeofenceBackend;->failure:I\nif-eqz v0, :ok\nconst/4 v1, 1\nif-ne v0, v1, :security\nnew-instance v0, Landroid/os/RemoteException;\ninvoke-direct {v0}, Landroid/os/RemoteException;-><init>()V\nthrow v0\n:security\nnew-instance v0, Ljava/lang/SecurityException;\ninvoke-direct {v0}, Ljava/lang/SecurityException;-><init>()V\nthrow v0\n:ok\nreturn-void') +
		method('public getMonitoringTypes()[I', 'invoke-direct {p0}, Lorg/vinix/service/GeofenceBackend;->checkFailure()V\nconst/4 v0, 2\nnew-array v0, v0, [I\nconst/4 v1, 1\naput v1, v0, v1\nreturn-object v0') +
		method('public getStatusOfMonitoringType(I)I', 'invoke-direct {p0}, Lorg/vinix/service/GeofenceBackend;->checkFailure()V\nconst/4 v0, 1\nif-ne p1, v0, :unsupported\nconst/4 v0, 0\nreturn v0\n:unsupported\nconst/4 v0, 2\nreturn v0'))!
}

fn geofence_wire_checks() string {
	mut body := ''
	// Independent AIDL wire checks: IDs 3 and 4 follow the two HAL setters.
	for code in [3, 4] {
		body += 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n' +
			'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v1\n' +
			'const-string v2, "android.hardware.location.IGeofenceHardware"\ninvoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\n'
		if code == 4 { body += 'const/4 v2, 1\ninvoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V\n' }
		body += 'const/4 v2, ' + code.str() + '\nconst/4 v3, 0\n' +
			'invoke-interface {p1, v2, v0, v1, v3}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v2\nif-eqz v2, :bad\n' +
			'invoke-virtual {v1}, Landroid/os/Parcel;->readException()V\n'
		if code == 3 {
			body += 'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nconst/4 v3, 2\nif-ne v2, v3, :bad\n' +
				'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nif-nez v2, :bad\n' +
				'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nconst/4 v3, 1\nif-ne v2, v3, :bad\n'
		} else {
			body += 'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nif-nez v2, :bad\n'
		}
		body += 'invoke-virtual {v1}, Landroid/os/Parcel;->dataAvail()I\nmove-result v2\nif-nez v2, :bad\n' +
			'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\ninvoke-virtual {v1}, Landroid/os/Parcel;->recycle()V\n'
	}
	return body + 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "geofence hardware AIDL wire"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn binder_checks() string {
	return 'new-instance v0, Lorg/vinix/service/LocalBinder;
invoke-direct {v0}, Lorg/vinix/service/LocalBinder;-><init>()V
const-string v1, "org.vinix.local"
invoke-interface {v0, v1}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v2
if-ne v0, v2, :bad
invoke-interface {v0}, Landroid/os/IBinder;->getInterfaceDescriptor()Ljava/lang/String;
move-result-object v2
invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const-string v2, "different"
invoke-interface {v0, v2}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v2
if-nez v2, :bad
invoke-interface {v0}, Landroid/os/IBinder;->pingBinder()Z
move-result v2
if-eqz v2, :bad
invoke-interface {v0}, Landroid/os/IBinder;->isBinderAlive()Z
move-result v2
if-eqz v2, :bad
new-instance v2, Landroid/os/Binder;
invoke-direct {v2}, Landroid/os/Binder;-><init>()V
invoke-virtual {v0, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v2
if-nez v2, :bad
invoke-virtual {v0, v0}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const-string v3, "org.vinix.local"
invoke-virtual {v1, v3}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V
const/4 v3, 7
invoke-virtual {v1, v3}, Landroid/os/Parcel;->writeInt(I)V
const/4 v3, 1
const/4 v4, 0
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->dataPosition()I
move-result v3
if-nez v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->readException()V
invoke-virtual {v2}, Landroid/os/Parcel;->readInt()I
move-result v3
const/16 v4, 14
if-ne v3, v4, :bad
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const v3, 0x5f4e5446
const/4 v4, 0
const/4 v1, 0
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v3
const-string v4, "org.vinix.local"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
const/4 v2, 0
const/16 v3, 99
const/4 v4, 0
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-nez v3, :bad
const/4 v3, 3
const/4 v4, 1
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-eqz v3, :bad
const/4 v3, 2
const/4 v4, 0
:exception_start
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
:exception_end
.catch Ljava/lang/IllegalStateException; {:exception_start .. :exception_end} :expected
goto :bad
:expected
move-exception v3
invoke-virtual {v3}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v3
const-string v4, "local failure"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
const/4 v3, 0
invoke-interface {v0, v1, v3}, Landroid/os/IBinder;->linkToDeath(Landroid/os/IBinder$DeathRecipient;I)V
invoke-interface {v0, v1, v3}, Landroid/os/IBinder;->unlinkToDeath(Landroid/os/IBinder$DeathRecipient;I)Z
move-result v3
if-eqz v3, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "local Binder ownership, identity, transaction dispatch and exception propagation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn parcel_checks() string {
	mut body := 'new-instance v0, Lorg/vinix/service/LocalBinder;
invoke-direct {v0}, Lorg/vinix/service/LocalBinder;-><init>()V
new-instance v1, Landroid/os/Binder;
invoke-direct {v1}, Landroid/os/Binder;-><init>()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v3
const/16 v4, 123
invoke-virtual {v2, v4}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeStrongInterface(Landroid/os/IInterface;)V
invoke-virtual {v2, v1}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
const/4 v4, 0
invoke-virtual {v2, v4}, Landroid/os/Parcel;->writeStrongInterface(Landroid/os/IInterface;)V
:marshall_start
invoke-virtual {v2}, Landroid/os/Parcel;->marshall()[B
:marshall_end
.catch Ljava/lang/RuntimeException; {:marshall_start .. :marshall_end} :marshall_rejected
goto/16 :bad
:marshall_rejected
move-exception v4
const/16 v4, 99
invoke-virtual {v3, v4}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v3, v4}, Landroid/os/Parcel;->writeInt(I)V
const/4 v4, 4
const/16 v5, 16
invoke-virtual {v3, v2, v4, v5}, Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
const/16 v4, 8
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
'
	for expected in ['v0', 'v0', 'v1', 'null'] {
		body += 'invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v4\n'
		body += if expected == 'null' { 'if-nez v4, :bad\n' } else { 'if-ne v4, ${expected}, :bad\n' }
	}
	body += 'const/16 v4, 8
const/16 v5, 8
invoke-virtual {v3, v3, v4, v5}, Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V
const/16 v4, 24
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
const/16 v4, 9
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
const/4 v4, 0
invoke-virtual {v3, v4}, Landroid/os/Parcel;->writeByte(B)V
const/16 v4, 8
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
const/16 v4, 13
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataSize(I)V
const/16 v4, 32
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataSize(I)V
const/16 v4, 12
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->marshall()[B
const/4 v4, 0
invoke-virtual {v2, v4}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v2, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
const/4 v4, 4
const/4 v5, 0
invoke-interface {v0, v4, v2, v3, v5}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->readException()V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
const/4 v4, 4
new-array v4, v4, [B
const/4 v5, 0
const/4 v1, 4
invoke-virtual {v2, v4, v5, v1}, Landroid/os/Parcel;->unmarshall([BII)V
invoke-virtual {v2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->marshall()[B
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Parcel Binder identity, copy offsets, self copy, overwrite, truncation, lifetime and callback round trip"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	return body
}

fn typed_parcel_checks() string {
	mut body := 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\nnew-instance v1, Lorg/vinix/service/ParcelCreator;\ninvoke-direct {v1}, Lorg/vinix/service/ParcelCreator;-><init>()V\n'
	// Decode independently written SafeParcel-style markers, including a size
	// marker of 8 and a null between two objects. Check complete consumption.
	for reader in ['createTypedArray', 'readTypedArray', 'createTypedArrayList', 'readTypedList'] {
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\n'
		for value in [3, 8, 41, 7, 0, 1, 42, 9] {
			body += 'const/16 v4, ${value}\ninvoke-virtual {v0, v4}, Landroid/os/Parcel;->writeInt(I)V\n'
		}
		body += 'const/4 v4, 0\ninvoke-virtual {v0, v4}, Landroid/os/Parcel;->setDataPosition(I)V\n'
		body += match reader {
			'createTypedArray' { 'invoke-virtual {v0, v1}, Landroid/os/Parcel;->createTypedArray(Landroid/os/Parcelable\$Creator;)[Ljava/lang/Object;\nmove-result-object v2\n' }
			'readTypedArray' { 'const/4 v4, 3\nnew-array v2, v4, [Lorg/vinix/service/ParcelValue;\ninvoke-virtual {v0, v2, v1}, Landroid/os/Parcel;->readTypedArray([Ljava/lang/Object;Landroid/os/Parcelable\$Creator;)V\n' }
			'createTypedArrayList' { 'invoke-virtual {v0, v1}, Landroid/os/Parcel;->createTypedArrayList(Landroid/os/Parcelable\$Creator;)Ljava/util/ArrayList;\nmove-result-object v2\n' }
			else { 'new-instance v2, Ljava/util/ArrayList;\ninvoke-direct {v2}, Ljava/util/ArrayList;-><init>()V\ninvoke-virtual {v0, v2, v1}, Landroid/os/Parcel;->readTypedList(Ljava/util/List;Landroid/os/Parcelable\$Creator;)V\n' }
		}
		if reader.ends_with('List') { body += 'invoke-interface {v2}, Ljava/util/List;->toArray()[Ljava/lang/Object;\nmove-result-object v2\n' }
		body += 'array-length v3, v2\nconst/4 v4, 3\nif-ne v3, v4, :bad\n'
		for index, value in [41, 0, 42] {
			body += 'const/4 v4, ${index}\naget-object v3, v2, v4\n'
			if value == 0 { body += 'if-nez v3, :bad\n' }
			else { body += 'check-cast v3, Lorg/vinix/service/ParcelValue;\niget v3, v3, Lorg/vinix/service/ParcelValue;->value:I\nconst/16 v4, ${value}\nif-ne v3, v4, :bad\n' }
		}
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->dataAvail()I\nmove-result v3\nif-nez v3, :bad\n'
	}
	// Inspect writers with a raw int decoder, rather than round-tripping through
	// the reader under test. Also check Parcelable flags and null/empty arrays.
	for writer in ['writeTypedArray', 'writeTypedList'] {
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nconst/4 v4, 3\nnew-array v2, v4, [Lorg/vinix/service/ParcelValue;\n'
		for index, value in [41, 0, 42] {
			if value == 0 { continue }
			body += 'new-instance v3, Lorg/vinix/service/ParcelValue;\ninvoke-direct {v3}, Lorg/vinix/service/ParcelValue;-><init>()V\nconst/16 v4, ${value}\niput v4, v3, Lorg/vinix/service/ParcelValue;->value:I\nconst/4 v4, ${index}\naput-object v3, v2, v4\n'
		}
		if writer == 'writeTypedArray' { body += 'const/4 v4, 2\ninvoke-virtual {v0, v2, v4}, Landroid/os/Parcel;->writeTypedArray([Landroid/os/Parcelable;I)V\n' }
		else { body += 'invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;\nmove-result-object v2\ninvoke-virtual {v0, v2}, Landroid/os/Parcel;->writeTypedList(Ljava/util/List;)V\n' }
		flags := if writer == 'writeTypedArray' { 2 } else { 0 }
		body += 'const/4 v4, 0\ninvoke-virtual {v0, v4}, Landroid/os/Parcel;->setDataPosition(I)V\n'
		for value in [3, 1, 41, flags, 0, 1, 42, flags] {
			body += 'invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I\nmove-result v3\nconst/16 v4, ${value}\nif-ne v3, v4, :bad\n'
		}
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->dataAvail()I\nmove-result v3\nif-nez v3, :bad\n'
		for size in [-1, 0] {
			body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nconst/4 v2, 0\nconst/4 v4, 0\n'
			if size == 0 {
				body += if writer == 'writeTypedArray' { 'new-array v2, v4, [Lorg/vinix/service/ParcelValue;\n' } else { 'new-instance v2, Ljava/util/ArrayList;\ninvoke-direct {v2}, Ljava/util/ArrayList;-><init>()V\n' }
			}
			body += if writer == 'writeTypedArray' { 'invoke-virtual {v0, v2, v4}, Landroid/os/Parcel;->writeTypedArray([Landroid/os/Parcelable;I)V\n' } else { 'invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeTypedList(Ljava/util/List;)V\n' }
			body += 'invoke-virtual {v0, v4}, Landroid/os/Parcel;->setDataPosition(I)V\ninvoke-virtual {v0}, Landroid/os/Parcel;->readInt()I\nmove-result v3\nconst/4 v4, ${size}\nif-ne v3, v4, :bad\n'
		}
	}
	body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Parcel typed collection markers, nulls, payload and flags"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	return body
}

fn typed_parcel_classes(dir string) ! {
	os.write_file(dir + '/ParcelValue.smali', '.class public Lorg/vinix/service/ParcelValue;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field public value:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public describeContents()I', 'const/4 v0, 0\nreturn v0') +
		method('public writeToParcel(Landroid/os/Parcel;I)V', 'iget v0, p0, Lorg/vinix/service/ParcelValue;->value:I\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {p1, p2}, Landroid/os/Parcel;->writeInt(I)V\nreturn-void'))!
	os.write_file(dir + '/ParcelCreator.smali', '.class public Lorg/vinix/service/ParcelCreator;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [Lorg/vinix/service/ParcelValue;\nreturn-object v0') +
		method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'new-instance v0, Lorg/vinix/service/ParcelValue;\ninvoke-direct {v0}, Lorg/vinix/service/ParcelValue;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v1\niput v1, v0, Lorg/vinix/service/ParcelValue;->value:I\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nreturn-object v0'))!
}

fn user_checks() string {
	return 'invoke-static {}, Landroid/os/Process;->myUid()I
move-result v0
invoke-static {v0}, Landroid/os/UserHandle;->getUserId(I)I
move-result v0
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v1
if-ne v0, v1, :bad
invoke-static {}, Landroid/os/Binder;->getCallingUid()I
move-result v0
invoke-static {v0}, Landroid/os/UserHandle;->getUserId(I)I
move-result v0
invoke-static {}, Landroid/os/UserHandle;->getCallingUserId()I
move-result v2
if-ne v0, v2, :bad
const-string v0, "user"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/os/UserManager;
invoke-virtual {v0}, Landroid/os/UserManager;->isSystemUser()Z
move-result v0
if-nez v1, :secondary
if-eqz v0, :bad
goto :ids
:secondary
if-nez v0, :bad
:ids
const v0, 201234
invoke-static {v0}, Landroid/os/UserHandle;->getUserId(I)I
move-result v1
const/4 v2, 2
if-ne v1, v2, :bad
invoke-static {v0}, Landroid/os/UserHandle;->getAppId(I)I
move-result v1
const/16 v2, 1234
if-ne v1, v2, :bad
const/4 v0, 2
invoke-static {v0, v2}, Landroid/os/UserHandle;->getUid(II)I
move-result v0
const v1, 201234
if-ne v0, v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Android user identity must derive from UID user ranges"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn priority_checks() string {
	return 'invoke-static {}, Landroid/os/Process;->myTid()I
move-result v0
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
const/4 v2, 0
invoke-static {v2}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
if-ne v1, v3, :bad
const/4 v2, -1
invoke-static {v2}, Landroid/os/Process;->setThreadPriority(I)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
if-ne v2, v3, :bad
invoke-static {v0, v1}, Landroid/os/Process;->setThreadPriority(II)V
const/16 v2, 19
invoke-static {v0, v2}, Landroid/os/Process;->setThreadPriority(II)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
if-ne v2, v3, :bad
invoke-static {v1}, Landroid/os/Process;->setThreadPriority(I)V
const v2, 0x7fffffff
:missing_start
invoke-static {v2}, Landroid/os/Process;->getThreadPriority(I)I
:missing_end
.catch Ljava/lang/IllegalArgumentException; {:missing_start .. :missing_end} :missing_ok
goto :bad
:missing_ok
move-exception v3
:set_missing_start
invoke-static {v2, v1}, Landroid/os/Process;->setThreadPriority(II)V
:set_missing_end
.catch Ljava/lang/IllegalArgumentException; {:set_missing_start .. :set_missing_end} :set_missing_ok
goto :bad
:set_missing_ok
move-exception v3
const/16 v2, 20
invoke-static {v2}, Landroid/os/Process;->setThreadPriority(I)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
const/16 v2, 19
if-ne v2, v3, :bad
const/16 v2, -21
invoke-static {v0, v2}, Landroid/os/Process;->setThreadPriority(II)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
const/16 v2, -20
if-ne v2, v3, :bad
invoke-static {v1}, Landroid/os/Process;->setThreadPriority(I)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v2
if-ne v1, v2, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "thread priority read, write, minus-one, missing TID and clamping"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn local_binder_fixture() string {
	return '.class public Lorg/vinix/service/LocalBinder;\n.super Landroid/os/Binder;\n.implements Landroid/os/IInterface;\n.field private caller:Ljava/lang/Thread;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/os/Binder;-><init>()V
const-string v0, "org.vinix.local"
invoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iput-object v0, p0, Lorg/vinix/service/LocalBinder;->caller:Ljava/lang/Thread;
return-void') +
		method('public asBinder()Landroid/os/IBinder;', 'return-object p0') +
		method('protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 'invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iget-object v1, p0, Lorg/vinix/service/LocalBinder;->caller:Ljava/lang/Thread;
if-ne v0, v1, :bad
const/4 v0, 1
if-eq p1, v0, :request
const/4 v0, 2
if-eq p1, v0, :exception
const/4 v0, 3
if-eq p1, v0, :oneway
const/4 v0, 4
if-eq p1, v0, :callback
invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v0
return v0
:request
const-string v0, "org.vinix.local"
invoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V
invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I
move-result v0
mul-int/lit8 v0, v0, 2
invoke-virtual {p3}, Landroid/os/Parcel;->writeNoException()V
invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeInt(I)V
const/4 v0, 1
return v0
:exception
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "local failure"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:callback
invoke-virtual {p2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p0, :bad
invoke-virtual {p3}, Landroid/os/Parcel;->writeNoException()V
invoke-virtual {p3, p0}, Landroid/os/Parcel;->writeStrongInterface(Landroid/os/IInterface;)V
const/4 v0, 1
return v0
:oneway
if-nez p3, :bad
const/4 v0, 1
if-ne p4, v0, :bad
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "local Binder caller thread and one-way arguments"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
}

fn component_checks() string {
	mut body := 'invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;\nmove-result-object v0\n'
	// Check metadata only: named companion processes still share this ART VM.
	for name in ['client', 'companion'] {
		process := 'org.vinix.service.' + name + if name == 'companion' { ':worker' } else { '' }
		body += 'const-string v2, "org.vinix.service.' + name + '"
const-string v3, "' + process + '"
const/4 v4, 0
invoke-virtual {v0, v2, v4}, Landroid/content/pm/PackageManager;->getApplicationInfo(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v4, v1, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
new-instance v4, Landroid/content/pm/ApplicationInfo;
invoke-direct {v4, v1}, Landroid/content/pm/ApplicationInfo;-><init>(Landroid/content/pm/ApplicationInfo;)V
iget-object v4, v4, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
const/4 v4, 0
invoke-virtual {p0, v2, v4}, Landroid/content/Context;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
move-result-object v5
invoke-virtual {v5}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v4, v1, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
'
	}
	for kind in ['Provider', 'Service'] {
		class := if kind == 'Provider' { 'Provider' } else { 'Worker' }
		for package_name in ['client', 'companion'] {
			app_process := 'org.vinix.service.' + package_name + if package_name == 'companion' { ':worker' } else { '' }
			component_process := if kind == 'Provider' { app_process } else if package_name == 'client' { 'org.vinix.service.global' } else { 'org.vinix.service.companion:service' }
			body += 'new-instance v1, Landroid/content/ComponentName;
const-string v2, "org.vinix.service.' + package_name + '"
const-string v3, "org.vinix.service.' + class + '"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/16 v3, 0x80
invoke-virtual {v0, v1, v3}, Landroid/content/pm/PackageManager;->get' + kind + 'Info(Landroid/content/ComponentName;I)Landroid/content/pm/' + kind + 'Info;
move-result-object v1
iget-object v3, v1, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v3, v1, Landroid/content/pm/ComponentInfo;->processName:Ljava/lang/String;
const-string v4, "' + component_process + '"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v3, v1, Landroid/content/pm/ComponentInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;
iget-object v3, v3, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
const-string v4, "' + app_process + '"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v1, v1, Landroid/content/pm/PackageItemInfo;->metaData:Landroid/os/Bundle;
if-eqz v1, :bad
const-string v2, "owner"
invoke-virtual {v1, v2}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v2, "' + package_name + '"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
'
		}
		for index in 0 .. 2 {
			label := kind + index.str()
			package_name := if index == 0 { 'org.vinix.service.companion' } else { 'org.vinix.service.absent' }
			name := if index == 0 { 'org.vinix.service.Missing' } else { 'org.vinix.service.' + class }
			body += 'new-instance v1, Landroid/content/ComponentName;
const-string v2, "' + package_name + '"
const-string v3, "' + name + '"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/4 v3, 0
:try' + label + '
invoke-virtual {v0, v1, v3}, Landroid/content/pm/PackageManager;->get' + kind + 'Info(Landroid/content/ComponentName;I)Landroid/content/pm/' + kind + 'Info;
:end' + label + '
.catch Landroid/content/pm/PackageManager$NameNotFoundException; {:try' + label + ' .. :end' + label + '} :caught' + label + '
goto :bad
:caught' + label + '
move-exception v1
'
		}
	}
	return body + 'return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package-qualified component metadata and missing component rejection"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn directory_checks() string {
	mut body := ''
	for index, context in ['p0', 'p1'] {
		body += 'invoke-virtual {' + context + '}, Landroid/content/Context;->getDataDir()Ljava/io/File;\nmove-result-object v0\n'
		for kind in ['custom', 'cache'] {
			call := if kind == 'custom' {
				'const-string v2, "fixture"\nconst/4 v3, 0\ninvoke-virtual {' + context + ', v2, v3}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;\n'
			} else {
				'invoke-virtual {' + context + '}, Landroid/content/Context;->getCacheDir()Ljava/io/File;\n'
			}
			name := if kind == 'custom' { 'app_fixture' } else { 'cache' }
			body += call + 'move-result-object v1
invoke-virtual {v1}, Ljava/io/File;->isDirectory()Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, Ljava/io/File;->getParentFile()Ljava/io/File;
move-result-object v2
invoke-virtual {v0, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, Ljava/io/File;->getName()Ljava/lang/String;
move-result-object v2
const-string v3, "' + name + '"
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
' + call + 'move-result-object v2
invoke-virtual {v1, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
new-instance v2, Ljava/io/File;
const-string v3, "owner.bin"
invoke-direct {v2, v1, v3}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v3, Ljava/io/FileOutputStream;
invoke-direct {v3, v2}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v4, ' + (49 + index).str() + '
invoke-virtual {v3, v4}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v3}, Ljava/io/FileOutputStream;->close()V
'
		}
	}
	// Reopen after both packages wrote the same relative names.
	for index, context in ['p0', 'p1'] {
		for kind in ['custom', 'cache'] {
			body += if kind == 'custom' {
				'const-string v0, "fixture"\nconst/4 v1, 0\ninvoke-virtual {' + context + ', v0, v1}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;\n'
			} else {
				'invoke-virtual {' + context + '}, Landroid/content/Context;->getCacheDir()Ljava/io/File;\n'
			}
			body += 'move-result-object v0
new-instance v1, Ljava/io/File;
const-string v2, "owner.bin"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v0, Ljava/io/FileInputStream;
invoke-direct {v0, v1}, Ljava/io/FileInputStream;-><init>(Ljava/io/File;)V
invoke-virtual {v0}, Ljava/io/FileInputStream;->read()I
move-result v1
invoke-virtual {v0}, Ljava/io/FileInputStream;->close()V
const/16 v2, ' + (49 + index).str() + '
if-ne v1, v2, :bad
'
		}
	}
	for index, mode in [1, 2] {
		body += 'const-string v0, "forbidden"\nconst/4 v1, ' + mode.str() + '
:mode_start_' + index.str() + '
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;
:mode_end_' + index.str() + '
.catch Ljava/lang/SecurityException; {:mode_start_' + index.str() + ' .. :mode_end_' + index.str() + '} :mode_caught_' + index.str() + '
goto :bad
:mode_caught_' + index.str() + '
move-exception v0
'
	}
	return body + 'const-string v0, "../escape"
const/4 v1, 0
:name_start
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;
:name_end
.catch Ljava/lang/IllegalArgumentException; {:name_start .. :name_end} :name_caught
goto :bad
:name_caught
move-exception v0
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "custom/cache directory layout, isolation or mode validation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn storage_checks() string {
	mut body := 'invoke-virtual {p1}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v0
iget-object v1, v0, Landroid/content/pm/ApplicationInfo;->splitNames:[Ljava/lang/String;
if-nez v1, :bad
new-instance v0, Landroid/content/pm/ApplicationInfo;
invoke-direct {v0}, Landroid/content/pm/ApplicationInfo;-><init>()V
const/4 v1, 1
new-array v1, v1, [Ljava/lang/String;
const/4 v2, 0
const-string v3, "feature"
aput-object v3, v1, v2
'
	for field in ['splitNames', 'splitSourceDirs', 'splitPublicSourceDirs'] {
		body += 'iput-object v1, v0, Landroid/content/pm/ApplicationInfo;->' + field + ':[Ljava/lang/String;\n'
	}
	body += 'new-instance v2, Landroid/content/pm/ApplicationInfo;
invoke-direct {v2, v0}, Landroid/content/pm/ApplicationInfo;-><init>(Landroid/content/pm/ApplicationInfo;)V
'
	for field in ['splitNames', 'splitSourceDirs', 'splitPublicSourceDirs'] {
		body += 'iget-object v3, v2, Landroid/content/pm/ApplicationInfo;->' + field + ':[Ljava/lang/String;\nif-ne v1, v3, :bad\n'
	}
	for index, context in ['p0', 'p1'] {
		body += 'invoke-virtual {' + context + '}, Landroid/content/Context;->getDataDir()Ljava/io/File;
move-result-object v0
invoke-virtual {' + context + '}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v1, v1, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;
new-instance v2, Ljava/io/File;
invoke-direct {v2, v1}, Ljava/io/File;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {' + context + '}, Landroid/content/Context;->getFilesDir()Ljava/io/File;
move-result-object v1
invoke-virtual {v1}, Ljava/io/File;->getParentFile()Ljava/io/File;
move-result-object v2
invoke-virtual {v0, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
new-instance v2, Ljava/io/File;
const-string v3, "same-name.bin"
invoke-direct {v2, v1, v3}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v3, Ljava/io/FileOutputStream;
invoke-direct {v3, v2}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v4, ' + (49 + index).str() + '
invoke-virtual {v3, v4}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v3}, Ljava/io/FileOutputStream;->close()V
const-string v1, "same-name"
const/4 v2, 0
invoke-virtual {' + context + ', v1, v2}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v1
invoke-interface {v1}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;
move-result-object v1
const-string v2, "owner"
invoke-interface {v1, v2, v4}, Landroid/content/SharedPreferences$Editor;->putInt(Ljava/lang/String;I)Landroid/content/SharedPreferences$Editor;
invoke-interface {v1}, Landroid/content/SharedPreferences$Editor;->commit()Z
move-result v1
if-eqz v1, :bad
'
	}
	body += 'invoke-virtual {p0}, Landroid/content/Context;->getDataDir()Ljava/io/File;
move-result-object v0
invoke-virtual {p1}, Landroid/content/Context;->getDataDir()Ljava/io/File;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :bad
'
	for index, context in ['p0', 'p1'] {
		body += 'invoke-virtual {' + context + '}, Landroid/content/Context;->getFilesDir()Ljava/io/File;
move-result-object v0
new-instance v1, Ljava/io/File;
const-string v2, "same-name.bin"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v0, Ljava/io/FileInputStream;
invoke-direct {v0, v1}, Ljava/io/FileInputStream;-><init>(Ljava/io/File;)V
invoke-virtual {v0}, Ljava/io/FileInputStream;->read()I
move-result v1
invoke-virtual {v0}, Ljava/io/FileInputStream;->close()V
const/16 v2, ' + (49 + index).str() + '
if-ne v1, v2, :bad
const-string v0, "same-name"
const/4 v1, 0
invoke-virtual {' + context + ', v0, v1}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v3
invoke-virtual {' + context + ', v0, v1}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v0
if-ne v0, v3, :bad
invoke-virtual {' + context + '}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v0
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
move-result-object v0
const-string v1, "same-name"
const/4 v4, 0
invoke-virtual {v0, v1, v4}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v0
if-ne v0, v3, :bad
const-string v1, "owner"
const/4 v4, -1
invoke-interface {v0, v1, v4}, Landroid/content/SharedPreferences;->getInt(Ljava/lang/String;I)I
move-result v1
if-ne v1, v2, :bad
'
	}
	return body + 'return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package-private data, files and preferences"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn importance_checks() string {
 return 'new-instance v0, Landroid/app/ActivityManager;
invoke-direct {v0}, Landroid/app/ActivityManager;-><init>()V
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v1
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->getUidImportance(I)I
move-result v2
const/16 v3, 100
if-ne v2, v3, :bad
const/4 v2, -1
invoke-virtual {v0, v2}, Landroid/app/ActivityManager;->getUidImportance(I)I
move-result v2
const/16 v3, 1000
if-ne v2, v3, :bad
new-instance v2, Landroid/app/ActivityManager$RunningAppProcessInfo;
invoke-direct {v2}, Landroid/app/ActivityManager$RunningAppProcessInfo;-><init>()V
invoke-static {v2}, Landroid/app/ActivityManager;->getMyMemoryState(Landroid/app/ActivityManager$RunningAppProcessInfo;)V
iget v3, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->uid:I
if-ne v1, v3, :bad
invoke-static {}, Landroid/os/Process;->myPid()I
move-result v3
iget v4, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->pid:I
if-ne v3, v4, :bad
iget v3, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->importance:I
const/16 v4, 100
if-ne v3, v4, :bad
iget-object v2, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->processName:Ljava/lang/String;
const-string v3, "org.vinix.service.client"
invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v0}, Landroid/app/ActivityManager;->getRunningAppProcesses()Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :bad
new-instance v1, Lorg/vinix/service/UidListener;
invoke-direct {v1}, Lorg/vinix/service/UidListener;-><init>()V
const/16 v2, 200
invoke-virtual {v0, v1, v2}, Landroid/app/ActivityManager;->addOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;I)V
:duplicate
invoke-virtual {v0, v1, v2}, Landroid/app/ActivityManager;->addOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;I)V
:duplicate_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:duplicate .. :duplicate_end} :duplicated
:duplicated
move-exception v3
# Controlled threshold crossings; onCreate also checks the real WS transition.
const/16 v2, 200
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
const/16 v2, 300
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
const/16 v2, 400
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
const/16 v2, 100
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
iget-object v2, v1, Lorg/vinix/service/UidListener;->latch:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v3, 10
sget-object v5, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v2, v3, v4, v5}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v2
if-eqz v2, :bad
iget v2, v1, Lorg/vinix/service/UidListener;->calls:I
const/4 v3, 2
if-ne v2, v3, :bad
iget v2, v1, Lorg/vinix/service/UidListener;->failed:I
if-nez v2, :bad
new-instance v2, Landroid/app/ActivityManager;
invoke-direct {v2}, Landroid/app/ActivityManager;-><init>()V
:other
invoke-virtual {v2, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
:other_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:other .. :other_end} :other_caught
:other_caught
move-exception v3
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
:absent
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
:absent_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:absent .. :absent_end} :absent_caught
:absent_caught
move-exception v2
const/16 v2, 200
invoke-virtual {v0, v1, v2}, Landroid/app/ActivityManager;->addOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;I)V
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "UID importance state, threshold, thread or registration"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn importance_listener(dir string) ! {
 os.write_file(dir + '/UidListener.smali', '.class public Lorg/vinix/service/UidListener;\n.super Ljava/lang/Object;\n.implements Landroid/app/ActivityManager$OnUidImportanceListener;\n' +
  '.field public calls:I\n.field public failed:I\n.field public latch:Ljava/util/concurrent/CountDownLatch;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 2
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
iput-object v0, p0, Lorg/vinix/service/UidListener;->latch:Ljava/util/concurrent/CountDownLatch;
return-void') +
  method('public onUidImportance(II)V', 'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-eq v0, v1, :bad
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v0
if-ne v0, p1, :bad
iget v0, p0, Lorg/vinix/service/UidListener;->calls:I
const/16 v1, 300
if-eqz v0, :expected
const/16 v1, 100
:expected
if-ne v1, p2, :bad
goto :done
:bad
const/4 v0, 1
iput v0, p0, Lorg/vinix/service/UidListener;->failed:I
:done
iget v0, p0, Lorg/vinix/service/UidListener;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/service/UidListener;->calls:I
iget-object v0, p0, Lorg/vinix/service/UidListener;->latch:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void'))!
}

fn main() {
	if os.args.len != 8 {
		panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER AAPT2 FRAMEWORK_RES')
	}
	out, fixture, tools := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3])
	java, signer, aapt, resources := os.args[4], os.abs_path(os.args[5]), os.abs_path(os.args[6]), os.abs_path(os.args[7])
	for name in ['client', 'companion'] {
		os.mkdir_all(out + '/' + name + '/smali/org/vinix/service')!
	}
	companion := out + '/companion/smali/org/vinix/service/'
	os.write_file(companion + 'App.smali', '.class public Lorg/vinix/service/App;\n.super Landroid/app/Application;\n.field public static stage:I\n.field public static starts:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Application;-><init>()V\nreturn-void') +
		method('public static check(I)V', '
sget v0, Lorg/vinix/service/App;->stage:I
if-eq v0, p0, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "companion Application/provider/service startup order"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') +
		method('protected attachBaseContext(Landroid/content/Context;)V', 'invoke-super {p0, p1}, Landroid/content/ContextWrapper;->attachBaseContext(Landroid/content/Context;)V\n' + check_stage(0, 1) + 'return-void') +
		method('public onCreate()V', check_stage(2, 3) + 'return-void'))!
	provider := '.class public Lorg/vinix/service/Provider;\n.super Landroid/content/ContentProvider;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V
invoke-virtual {p0}, Landroid/content/ContentProvider;->getContext()Landroid/content/Context;
move-result-object v0
if-eqz v0, :unattached
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "provider context before attachment"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:unattached
return-void') +
		method('public onCreate()Z', check_stage(1, 2) + '
invoke-virtual {p0}, Landroid/content/ContentProvider;->getContext()Landroid/content/Context;
move-result-object v0
invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
const-string v2, "org.vinix.service.companion"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v1
const-string v3, "provider_owner"
const-string v4, "string"
invoke-virtual {v1, v3, v4, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/Context;->getString(I)Ljava/lang/String;
move-result-object v1
const-string v2, "companion resource"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/content/ContentProvider;->attachInfo(Landroid/content/Context;Landroid/content/pm/ProviderInfo;)V
const/4 v0, 1
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "provider owning package and resources"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	mut operations := ''
	for signature in [
		'query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;',
		'insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;',
		'getType(Landroid/net/Uri;)Ljava/lang/String;',
	] {
		operations += method('public ' + signature, 'const/4 v0, 0\nreturn-object v0')
	}
	for signature in ['delete(Landroid/net/Uri;Ljava/lang/String;[Ljava/lang/String;)I',
		'update(Landroid/net/Uri;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I'] {
		operations += method('public ' + signature, 'const/4 v0, 0\nreturn v0')
	}
	os.write_file(companion + 'Provider.smali', provider + operations)!
	client := out + '/client/smali/org/vinix/service/'
	os.write_file(client + 'LocalBinder.smali', local_binder_fixture())!
	os.write_file(client + 'Provider.smali', '.class public Lorg/vinix/service/Provider;\n.super Landroid/content/ContentProvider;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V\nreturn-void') +
		method('public onCreate()Z', 'const/4 v0, 1\nreturn v0') + operations)!
	os.write_file(client + 'Worker.smali', '.class public Lorg/vinix/service/Worker;\n.super Landroid/app/Service;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void') +
		method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', 'const/4 v0, 0\nreturn-object v0'))!
	os.write_file(companion + 'Worker.smali', '.class public Lorg/vinix/service/Worker;\n.super Landroid/app/Service;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\n' + check_stage(3, 4) + 'return-void') +
		method('public onCreate()V', check_stage(4, 5) + '
invoke-virtual {p0}, Landroid/app/Service;->getApplication()Landroid/app/Application;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v1
if-eq v0, v1, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "service Application context identity"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') +
		method('public onStartCommand(Landroid/content/Intent;II)I', '
const/4 v0, 5
invoke-static {v0}, Lorg/vinix/service/App;->check(I)V
sget v0, Lorg/vinix/service/App;->starts:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/service/App;->starts:I
const/4 v0, 0
return v0') +
		method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', '
const/4 v0, 5
invoke-static {v0}, Lorg/vinix/service/App;->check(I)V
sget v0, Lorg/vinix/service/App;->starts:I
const/4 v1, 2
if-eq v0, v1, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "service must start twice without recreating Application or providers"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
return-object v0'))!
	os.write_file(out + '/client/smali/org/vinix/service/Main.smali', '.class public Lorg/vinix/service/Main;\n.super Landroid/app/Activity;\n.implements Landroid/content/ServiceConnection;\n.implements Ljava/util/concurrent/Executor;\n.implements Ljava/lang/Runnable;\n' +
		'.field private label:Landroid/widget/TextView;\n.field private callbacks:I\n.field private worker:Landroid/os/Handler;\n' +
		'.field private priorityMain:I\n.field private priorityWorker:I\n.field private priorityOriginal:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		method('private checkComponents()V', component_checks()) +
		method('private checkBinder()V', binder_checks()) +
		method('private checkProxyListener()V', proxy_listener_checks()) +
		method('private checkParcel()V', parcel_checks()) +
		method('private checkTypedParcel()V', typed_parcel_checks()) +
		method('private checkGeofence()V', geofence_checks()) +
		method('private checkGeofenceWire(Landroid/os/IBinder;)V', geofence_wire_checks()) +
		method('private checkUser()V', user_checks()) +
		method('private checkPriority()V', priority_checks()) +
		method('private checkImportance()V', importance_checks()) +
		method('private checkWorkerPriority()V', '
invoke-direct {p0}, Lorg/vinix/service/Main;->checkPriority()V
invoke-static {}, Landroid/os/Process;->myTid()I
move-result v0
iput v0, p0, Lorg/vinix/service/Main;->priorityWorker:I
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
iput v1, p0, Lorg/vinix/service/Main;->priorityOriginal:I
const/4 v1, 7
invoke-static {v1}, Landroid/os/Process;->setThreadPriority(I)V
return-void') +
		method('private checkPriorityIsolation()V', '
const/4 v0, 0
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v0
iget v1, p0, Lorg/vinix/service/Main;->priorityMain:I
if-ne v0, v1, :bad
iget v0, p0, Lorg/vinix/service/Main;->priorityWorker:I
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
const/4 v2, 7
if-ne v1, v2, :bad
const/16 v2, 12
invoke-static {v0, v2}, Landroid/os/Process;->setThreadPriority(II)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
if-ne v1, v2, :bad
iget v1, p0, Lorg/vinix/service/Main;->priorityOriginal:I
invoke-static {v0, v1}, Landroid/os/Process;->setThreadPriority(II)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "per-thread priority isolation and remote TID"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('private checkStorage(Landroid/content/Context;)V', storage_checks()) +
		method('private checkDirectories(Landroid/content/Context;)V', directory_checks()) +
		method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkComponents()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkProxyListener()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkParcel()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkTypedParcel()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkGeofence()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkUser()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkImportance()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkPriority()V
const/4 v0, 0
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v0
iput v0, p0, Lorg/vinix/service/Main;->priorityMain:I
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Lorg/vinix/service/Main;->label:Landroid/widget/TextView;
const-string v1, "Checking companion services"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
const-string v0, "org.vinix.service.companion"
const/4 v1, 3
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
move-result-object v0
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkStorage(Landroid/content/Context;)V
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkDirectories(Landroid/content/Context;)V
invoke-virtual {v0}, Landroid/content/Context;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
const-string v1, "org.vinix.service.App"
invoke-virtual {v0, v1}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
const-string v1, "stage"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->getInt(Ljava/lang/Object;)I
move-result v0
if-eqz v0, :lazy
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package context must not start companion Application"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:lazy
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.service.companion"
const-string v2, "org.vinix.service.Worker"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
const/4 v1, 1
invoke-virtual {p0, v0, p0, v1}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
return-void') +
		method('public onServiceDisconnected(Landroid/content/ComponentName;)V', 'return-void') +
		method('public execute(Ljava/lang/Runnable;)V', '
iget-object v0, p0, Lorg/vinix/service/Main;->worker:Landroid/os/Handler;
invoke-virtual {v0, p1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void') +
		method('public onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V', '
iget v2, p0, Lorg/vinix/service/Main;->callbacks:I
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-nez v2, :executor
if-ne v0, v1, :bad
goto :identity
:executor
if-eq v0, v1, :bad
invoke-direct {p0}, Lorg/vinix/service/Main;->checkWorkerPriority()V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Thread;->getName()Ljava/lang/String;
move-result-object v0
const-string v1, "service-executor"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
:identity
if-eqz p2, :bad
invoke-virtual {p1}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "org.vinix.service.companion"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
if-nez v2, :passed
const/4 v0, 1
iput v0, p0, Lorg/vinix/service/Main;->callbacks:I
new-instance v0, Landroid/os/HandlerThread;
const-string v1, "service-executor"
invoke-direct {v0, v1}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v0
new-instance v1, Landroid/os/Handler;
invoke-direct {v1, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v1, p0, Lorg/vinix/service/Main;->worker:Landroid/os/Handler;
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.service.companion"
const-string v2, "org.vinix.service.Worker"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const/4 v1, 1
invoke-virtual {p0, v0, v1, p0, p0}, Landroid/content/Context;->bindService(Landroid/content/Intent;ILjava/util/concurrent/Executor;Landroid/content/ServiceConnection;)Z
move-result v0
if-eqz v0, :bad
return-void
:passed
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "companion service binding callback"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('public run()V', '
invoke-direct {p0}, Lorg/vinix/service/Main;->checkPriorityIsolation()V
iget-object v0, p0, Lorg/vinix/service/Main;->label:Landroid/widget/TextView;
const-string v1, "Companion service startup passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "SERVICE-FIXTURE-PASS lazy-package-context application provider service constructor repeated-start bind-main-thread provider-context provider-resources attach-once bind-executor-thread component-package component-metadata component-missing package-data package-files package-preferences split-info-copy local-binder-interface local-binder-identity local-binder-transact local-binder-exception user-identity system-user uid-ranges parcel-binder-identity parcel-binder-copy parcel-binder-lifetime parcel-binder-callback custom-directory cache-directory directory-isolation directory-mode directory-name thread-priority priority-minus-one priority-errors priority-isolation priority-remote-tid uid-importance uid-listener-threshold uid-listener-thread uid-listener-registration"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void'))!
	importance_listener(out + '/client/smali/org/vinix/service')!
	typed_parcel_classes(out + '/client/smali/org/vinix/service')!
	geofence_classes(out + '/client/smali/org/vinix/service')!
	proxy_listener_class(out + '/client/smali/org/vinix/service')!
	for name in ['client', 'companion'] {
		dir := out + '/' + name
		os.mkdir_all(dir + '/res/values')!
		os.write_file(dir + '/res/values/strings.xml', '<resources><string name="provider_owner">' + name + ' resource</string></resources>')!
		checked([aapt, 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])
		service_process := if name == 'client' { 'org.vinix.service.global' } else { ':service' }
		components := '<service android:name="org.vinix.service.Worker" android:process="' + service_process + '" android:exported="true"><meta-data android:name="owner" android:value="' + name + '"/></service><provider android:name="org.vinix.service.Provider" android:authorities="fixture.service.' + name + '"><meta-data android:name="owner" android:value="' + name + '"/></provider>'
		application := if name == 'client' {
			'<application android:label="Service fixture"><activity android:name="org.vinix.service.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>' + components + '</application>'
		} else {
			'<application android:name="org.vinix.service.App" android:process=":worker" android:label="Companion fixture">' + components + '</application>'
		}
		os.write_file(dir + '/AndroidManifest.xml', '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.service.' + name + '" android:versionCode="1"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>' + application + '</manifest>')!
		checked([aapt, 'link', '-I', resources, dir + '/resources.zip', '--manifest', dir + '/AndroidManifest.xml', '-o',
			dir + '/unsigned.apk'])
		checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', dir + '/smali', '-o',
			dir + '/classes.dex'])
		checked(['zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])
		checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
			'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
			dir + '/probe.apk', dir + '/unsigned.apk'])
	}
	println('SERVICE-FIXTURE-APKS ' + out)
}
