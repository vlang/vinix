// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

struct GeofenceMethod {
	name string
	code int
	argument string
	result string
}

// The native runtime has local Binder transport. Preserve the AIDL descriptors,
// transaction IDs and proxy path, including calls through a forwarding Binder.
fn geofence_binder(smali string, name string, methods []GeofenceMethod) ! {
	iface := 'L' + name + ';'
	stub := 'L' + name + '$Stub;'
	proxy := 'L' + name + '$Stub$Proxy;'
	descriptor := name.replace('/', '.')
	mut declarations := '.class public interface abstract ' + iface + '\n.super Ljava/lang/Object;\n.implements Landroid/os/IInterface;\n'
	mut base := '.class public abstract ' + stub + '\n.super Landroid/os/Binder;\n.implements ' + iface + '\n' +
		'.method public constructor <init>()V\n.locals 1\ninvoke-direct {p0}, Landroid/os/Binder;-><init>()V\n' +
		'const-string v0, "' + descriptor + '"\ninvoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V\nreturn-void\n.end method\n' +
		'.method public asBinder()Landroid/os/IBinder;\n.locals 0\nreturn-object p0\n.end method\n' +
		'.method public static asInterface(Landroid/os/IBinder;)' + iface + '\n.locals 2\nif-nez p0, :lookup\nconst/4 v0, 0\nreturn-object v0\n:lookup\n' +
		'const-string v0, "' + descriptor + '"\ninvoke-interface {p0, v0}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;\nmove-result-object v0\n' +
		'instance-of v1, v0, ' + iface + '\nif-eqz v1, :proxy\ncheck-cast v0, ' + iface + '\nreturn-object v0\n:proxy\n' +
		'new-instance v0, ' + proxy + '\ninvoke-direct {v0, p0}, ' + proxy + '-><init>(Landroid/os/IBinder;)V\nreturn-object v0\n.end method\n'
	mut remote := '.class public final ' + proxy + '\n.super Ljava/lang/Object;\n.implements ' + iface + '\n.field private remote:Landroid/os/IBinder;\n' +
		'.method public constructor <init>(Landroid/os/IBinder;)V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + proxy + '->remote:Landroid/os/IBinder;\nreturn-void\n.end method\n' +
		'.method public asBinder()Landroid/os/IBinder;\n.locals 1\niget-object v0, p0, ' + proxy + '->remote:Landroid/os/IBinder;\nreturn-object v0\n.end method\n'
	mut dispatch := '.method protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\n.locals 2\n'
	for method in methods {
		signature := method.name + '(' + method.argument + ')' + method.result
		declarations += '.method public abstract ' + signature + '\n.end method\n'
		dispatch += 'const/16 v0, ' + method.code.str() + '\nif-eq p1, v0, :call' + method.code.str() + '\n'
		mut body := '.method public ' + signature + '\n.locals 6\n' +
			'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n' +
			'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v1\n:try_start\n' +
			'const-string v2, "' + descriptor + '"\ninvoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\n'
		if method.argument == 'I' {
			body += 'invoke-virtual {v0, p1}, Landroid/os/Parcel;->writeInt(I)V\n'
		} else if method.argument != '' {
			body += 'const/4 v2, 0\nif-eqz p1, :binder\ninvoke-interface {p1}, Landroid/os/IInterface;->asBinder()Landroid/os/IBinder;\nmove-result-object v2\n:binder\n' +
				'invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\n'
		}
		body += 'const/16 v2, ' + method.code.str() + '\nconst/4 v3, 0\niget-object v4, p0, ' + proxy + '->remote:Landroid/os/IBinder;\n' +
			'invoke-interface {v4, v2, v0, v1, v3}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v2\nif-nez v2, :reply\n' +
			'new-instance v2, Landroid/os/RemoteException;\ninvoke-direct {v2}, Landroid/os/RemoteException;-><init>()V\nthrow v2\n:reply\n' +
			'invoke-virtual {v1}, Landroid/os/Parcel;->readException()V\n'
		if method.result == 'I' { body += 'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\n' }
		if method.result == '[I' { body += 'invoke-virtual {v1}, Landroid/os/Parcel;->createIntArray()[I\nmove-result-object v2\n' }
		body += ':try_end\n.catchall {:try_start .. :try_end} :failed\n' +
			'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\ninvoke-virtual {v1}, Landroid/os/Parcel;->recycle()V\n' +
			if method.result == 'V' { 'return-void\n' } else if method.result == '[I' { 'return-object v2\n' } else { 'return v2\n' }
		body += ':failed\nmove-exception v2\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\ninvoke-virtual {v1}, Landroid/os/Parcel;->recycle()V\nthrow v2\n.end method\n'
		remote += body
	}
	dispatch += 'invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0\n'
	for method in methods {
		signature := method.name + '(' + method.argument + ')' + method.result
		dispatch += ':call' + method.code.str() + '\nconst-string v0, "' + descriptor + '"\ninvoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\n'
		if method.argument == 'I' {
			dispatch += 'invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I\nmove-result v0\n'
		} else if method.argument != '' {
			dispatch += 'invoke-virtual {p2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v0\n' +
				'invoke-static {v0}, Landroid/hardware/location/IGeofenceHardware$Stub;->asInterface(Landroid/os/IBinder;)Landroid/hardware/location/IGeofenceHardware;\nmove-result-object v0\n'
		}
		dispatch += 'invoke-interface {' + if method.argument == '' { 'p0' } else { 'p0, v0' } + '}, ' + iface + '->' + signature + '\n'
		if method.result != 'V' { dispatch += if method.result == '[I' { 'move-result-object v0\n' } else { 'move-result v0\n' } }
		dispatch += 'if-eqz p3, :done' + method.code.str() + '\ninvoke-virtual {p3}, Landroid/os/Parcel;->writeNoException()V\n'
		if method.result == 'I' { dispatch += 'invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeInt(I)V\n' }
		if method.result == '[I' { dispatch += 'invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeIntArray([I)V\n' }
		dispatch += ':done' + method.code.str() + '\nconst/4 v0, 1\nreturn v0\n'
	}
	base += dispatch + '.end method\n'
	os.mkdir_all(os.dir(smali + '/' + name))!
	os.write_file(smali + '/' + name + '.smali', declarations)!
	os.write_file(smali + '/' + name + '$Stub.smali', base)!
	os.write_file(smali + '/' + name + '$Stub$Proxy.smali', remote)!
}

fn framework_geofence(smali string) ! {
	geofence_binder(smali, 'android/location/IGeofenceProvider', [GeofenceMethod{'setGeofenceHardware', 1, 'Landroid/hardware/location/IGeofenceHardware;', 'V'}])!
	// There is no Vinix geofence HAL. Only capability queries are exposed here;
	// they forward to a supplied backend, rather than advertising a fake device.
	geofence_binder(smali, 'android/hardware/location/IGeofenceHardware', [GeofenceMethod{'getMonitoringTypes', 3, '', '[I'}, GeofenceMethod{'getStatusOfMonitoringType', 4, 'I', 'I'}])!
	hardware := 'Landroid/hardware/location/GeofenceHardware;'
	mut text := '.class public final ' + hardware + '\n.super Ljava/lang/Object;\n.field private service:Landroid/hardware/location/IGeofenceHardware;\n' +
		'.method public constructor <init>(Landroid/hardware/location/IGeofenceHardware;)V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + hardware + '->service:Landroid/hardware/location/IGeofenceHardware;\nreturn-void\n.end method\n'
	for name, value in {'MONITORING_TYPE_GPS_HARDWARE': 0, 'MONITORING_TYPE_FUSED_HARDWARE': 1, 'MONITOR_CURRENTLY_AVAILABLE': 0, 'MONITOR_CURRENTLY_UNAVAILABLE': 1, 'MONITOR_UNSUPPORTED': 2} {
		text += '.field public static final ' + name + ':I = ' + value.str() + '\n'
	}
	for array in [true, false] {
		signature := if array { 'getMonitoringTypes()[I' } else { 'getStatusOfMonitoringType(I)I' }
		text += '.method public ' + signature + '\n.locals 1\n:try_start\niget-object v0, p0, ' + hardware + '->service:Landroid/hardware/location/IGeofenceHardware;\n' +
			'invoke-interface {' + if array { 'v0' } else { 'v0, p1' } + '}, Landroid/hardware/location/IGeofenceHardware;->' + signature + '\n' +
			if array { 'move-result-object v0\nreturn-object v0\n' } else { 'move-result v0\nreturn v0\n' }
		text += ':try_end\n.catch Landroid/os/RemoteException; {:try_start .. :try_end} :failed\n:failed\nmove-exception v0\n' +
			if array { 'const/4 v0, 0\nnew-array v0, v0, [I\nreturn-object v0\n.end method\n' } else { 'const/4 v0, 2\nreturn v0\n.end method\n' }
	}
	os.write_file(smali + '/android/hardware/location/GeofenceHardware.smali', text)!
	provider := 'Lcom/android/location/provider/GeofenceProvider;'
	binder := 'Lcom/android/location/provider/VinixGeofenceProvider;'
	os.mkdir_all(smali + '/com/android/location/provider')!
	os.write_file(smali + '/com/android/location/provider/GeofenceProvider.smali',
		'.class public abstract ' + provider + '\n.super Ljava/lang/Object;\n.field private binder:' + binder + '\n' +
		'.method public constructor <init>()V\n.locals 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
		'new-instance v0, ' + binder + '\ninvoke-direct {v0, p0}, ' + binder + '-><init>(' + provider + ')V\niput-object v0, p0, ' + provider + '->binder:' + binder + '\nreturn-void\n.end method\n' +
		'.method public getBinder()Landroid/os/IBinder;\n.locals 1\niget-object v0, p0, ' + provider + '->binder:' + binder + '\nreturn-object v0\n.end method\n' +
		'.method public abstract onGeofenceHardwareChange(' + hardware + ')V\n.end method\n')!
	os.write_file(smali + '/com/android/location/provider/VinixGeofenceProvider.smali',
		'.class public final ' + binder + '\n.super Landroid/location/IGeofenceProvider$Stub;\n.field private owner:' + provider + '\n' +
		'.method public constructor <init>(' + provider + ')V\n.locals 0\ninvoke-direct {p0}, Landroid/location/IGeofenceProvider$Stub;-><init>()V\niput-object p1, p0, ' + binder + '->owner:' + provider + '\nreturn-void\n.end method\n' +
		'.method public setGeofenceHardware(Landroid/hardware/location/IGeofenceHardware;)V\n.locals 2\n' +
		'new-instance v0, ' + hardware + '\ninvoke-direct {v0, p1}, ' + hardware + '-><init>(Landroid/hardware/location/IGeofenceHardware;)V\n' +
		'iget-object v1, p0, ' + binder + '->owner:' + provider + '\ninvoke-virtual {v1, v0}, ' + provider + '->onGeofenceHardwareChange(' + hardware + ')V\nreturn-void\n.end method\n')!
}
