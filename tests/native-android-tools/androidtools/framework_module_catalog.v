// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_module_catalog(smali string) ! {
	path := smali + '/android/content/pm/PackageManager.smali'
	// This deployment has no platform module metadata/installation service.
	// APKs, Chimera modules and host libraries are not Android system modules.
	// Return a fresh catalog so caller mutations never change later queries.
	os.write_file(path, framework_replace_method(os.read_file(path)!, 'getInstalledModules(I)Ljava/util/List;', r'
.method public getInstalledModules(I)Ljava/util/List;
.locals 1
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
return-object v0
.end method')!)!
}
