// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_shared_library_catalog(smali string) ! {
	path := smali + '/android/content/pm/PackageManager.smali'
	// No Android system shared-library catalog is installed. Use an empty
	// array so consumers can enumerate it directly; host ELF libraries and
	// app-private APK modules are not Android shared-library declarations.
	os.write_file(path, framework_replace_method(os.read_file(path)!,
		'getSystemSharedLibraryNames()[Ljava/lang/String;', r'
.method public getSystemSharedLibraryNames()[Ljava/lang/String;
.locals 1
const/4 v0, 0
new-array v0, v0, [Ljava/lang/String;
return-object v0
.end method')!)!
}
