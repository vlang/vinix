// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

pub fn framework_tethering(smali string) ! {
	path := smali + '/android/net/ConnectivityManager.smali'
	// Link availability does not imply tethering support. No tethering backend
	// or downstream-interface configuration is installed in native WS.
	os.write_file(path, framework_replace_method(os.read_file(path)!, 'isTetheringSupported()Z',
		'.method public isTetheringSupported()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!)!
}
