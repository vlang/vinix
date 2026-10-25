// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn location_state_method(signature string, body string) string {
	return '.method public ' + signature + '\n.locals 2\n' + body + '\n.end method'
}

fn location_state_not_null(register string, name string) string {
	return 'if-nez ' + register + ', :' + name + '_valid\n' +
		'new-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "' + name + ' must not be null"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:' + name + '_valid\n'
}

// There are no native WS location providers, including disabled providers.
// Follow the existing legacy API's Android 10 contracts: a missing provider
// cannot accept updates or emit GNSS status. Extra commands still return true.
fn framework_location_state(smali string) ! {
	path := smali + '/android/location/LocationManager.smali'
	mut text := os.read_file(path)!
	for signature in ['isLocationEnabled()Z', 'isProviderEnabled(Ljava/lang/String;)Z'] {
		guard := if signature.starts_with('isProvider') {
			location_state_not_null('p1', 'provider')
		} else {
			''
		}
		text = framework_replace_method(text, signature, location_state_method(signature,
			guard + 'const/4 v0, 0\nreturn v0'))!
	}
	for signature, argument in {
		'getBestProvider(Landroid/location/Criteria;Z)Ljava/lang/String;':     'criteria'
		'getLastKnownLocation(Ljava/lang/String;)Landroid/location/Location;': 'provider'
	} {
		text = framework_replace_method(text, signature, location_state_method(signature,
			location_state_not_null('p1', argument) + 'const/4 v0, 0\nreturn-object v0'))!
	}
	request := 'requestLocationUpdates(Ljava/lang/String;JFLandroid/location/LocationListener;)V'
	// The legacy listener transport creates a Handler before the service checks
	// provider existence. Preserve its caller-Looper validation without retaining
	// a listener or entering the unbound nativeGetLocation method.
	text = framework_replace_method(text, request, location_state_method(request,
		location_state_not_null('p1', 'provider') + location_state_not_null('p5', 'listener') +
			'new-instance v0, Landroid/os/Handler;\ninvoke-direct {v0}, Landroid/os/Handler;-><init>()V\n' +
			'new-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "provider does not exist"\n' +
			'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0'))!
	remove := 'removeUpdates(Landroid/location/LocationListener;)V'
	text = framework_replace_method(text, remove, location_state_method(remove,
		location_state_not_null('p1', 'listener') +
			'sget-object v0, Landroid/location/LocationManager;->listeners:Ljava/util/Set;\n' +
			'invoke-interface {v0, p1}, Ljava/util/Set;->remove(Ljava/lang/Object;)Z\nreturn-void'))!
	gnss := 'registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z'
	// Android 10 accepts a null callback here until a provider emits an event.
	// Its transport uses Handler(Looper), including the null-Looper exception.
	text = framework_replace_method(text, gnss, location_state_method(gnss,
		'if-nez p2, :handler_valid\ninvoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\n' +
			'move-result-object v1\nnew-instance v0, Landroid/os/Handler;\n' +
			'invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V\n' +
			':handler_valid\nconst/4 v0, 0\nreturn v0'))!
	unregister := 'unregisterGnssStatusCallback(Landroid/location/GnssStatus$Callback;)V'
	// A failed registration has no transport to remove, even for a null callback.
	text = framework_replace_method(text, unregister, location_state_method(unregister,
		'return-void'))!
	command := 'sendExtraCommand(Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Z'
	text = framework_replace_method(text, command, location_state_method(command,
		'if-nez p1, :provider_valid\nnew-instance v0, Ljava/lang/NullPointerException;\n' +
			'invoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n' +
			':provider_valid\nconst/4 v0, 1\nreturn v0'))!
	os.write_file(path, text)!
	os.write_file(smali + '/android/app/PendingIntent$OnFinished.smali', interface_class('android/app/PendingIntent$OnFinished',
		['onSendFinished(Landroid/app/PendingIntent;Landroid/content/Intent;ILjava/lang/String;Landroid/os/Bundle;)V']))!
}
