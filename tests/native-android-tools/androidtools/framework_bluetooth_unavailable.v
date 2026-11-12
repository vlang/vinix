// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_bluetooth_unavailable(smali string) ! {
	manager := smali + '/android/bluetooth/BluetoothManager.smali'
	os.write_file(manager, framework_replace_method(os.read_file(manager)!, 'getAdapter()Landroid/bluetooth/BluetoothAdapter;', r'
.method public getAdapter()Landroid/bluetooth/BluetoothAdapter;
.locals 1
invoke-static {}, Landroid/bluetooth/BluetoothAdapter;->getDefaultAdapter()Landroid/bluetooth/BluetoothAdapter;
move-result-object v0
return-object v0
.end method')!)!
	// There is no radio backend. Manager lookup must agree with the existing
	// null default adapter. Retain truthful off-state queries for legacy objects.
	path := smali + '/android/bluetooth/BluetoothAdapter.smali'
	mut source := os.read_file(path)!
	for declaration, value in {
		'getState()I': 10
		'getScanMode()I': 20
		'getProfileConnectionState(I)I': 0
		'isEnabled()Z': 0
		'isDiscovering()Z': 0
	} {
		source = framework_replace_method(source, declaration,
			'.method public ${declaration}\n.locals 1\nconst/16 v0, ${value}\nreturn v0\n.end method')!
	}
	for declaration in ['getAddress()Ljava/lang/String;', 'getName()Ljava/lang/String;'] {
		source = framework_replace_method(source, declaration,
			'.method public ${declaration}\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method')!
	}
	source = framework_replace_method(source, 'getBondedDevices()Ljava/util/Set;', r'
.method public getBondedDevices()Ljava/util/Set;
.locals 1
new-instance v0, Ljava/util/HashSet;
invoke-direct {v0}, Ljava/util/HashSet;-><init>()V
return-object v0
.end method')!
	os.write_file(path, source)!
}
