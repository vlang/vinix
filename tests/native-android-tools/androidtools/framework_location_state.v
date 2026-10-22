// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The native WS backend currently has no location provider. Keep discovery and
// enabled queries consistent; never invent a fix or advertise xdgportal/GNSS.
fn framework_location_state(smali string) ! {
	path := smali + '/android/location/LocationManager.smali'
	mut text := os.read_file(path)!
	for signature in ['isLocationEnabled()Z', 'isProviderEnabled(Ljava/lang/String;)Z'] {
		guard := if signature.starts_with('isProvider') {
			'if-nez p1, :valid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "provider must not be null"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n'
		} else { '' }
		text = framework_replace_method(text, signature, '.method public ' + signature + '\n.locals 2\n' + guard + 'const/4 v0, 0\nreturn v0\n.end method')!
	}
	text = framework_replace_method(text, 'getBestProvider(Landroid/location/Criteria;Z)Ljava/lang/String;',
		'.method public getBestProvider(Landroid/location/Criteria;Z)Ljava/lang/String;\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method')!
	os.write_file(path, text)!
	os.write_file(smali + '/android/app/PendingIntent$OnFinished.smali', interface_class('android/app/PendingIntent$OnFinished',
		['onSendFinished(Landroid/app/PendingIntent;Landroid/content/Intent;ILjava/lang/String;Landroid/os/Bundle;)V']))!
}
