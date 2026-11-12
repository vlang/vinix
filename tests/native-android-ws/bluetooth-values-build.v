// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os
fn main() {
	if os.args.len != 3 { panic('usage: bluetooth-values-build FRAMEWORK FRESH_OUTPUT') }
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) { panic('fresh output required') }
	os.mkdir_all(root)!
	os.cp_all(base + '/smali', root + '/smali', false)!
	androidtools.framework_bluetooth_values(root + '/smali')!
	androidtools.framework_parcel_uuid(root + '/smali')!
	androidtools.framework_peripheral_types(root + '/smali')!
	androidtools.framework_account_features(root + '/smali')!
	androidtools.framework_voice_capability(root + '/smali')!
	androidtools.framework_intent_mime(root + '/smali')!
	androidtools.framework_contacts_authority(root + '/smali')!
	androidtools.framework_intent_to_uri(root + '/smali')!
	androidtools.framework_tethering(root + '/smali')!
	os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	cp := '/Users/alex/code/vinix/build/android-framework/tools/*'
	mut types := ['android/os/ParcelUuid', 'android/bluetooth/BluetoothDevice', 'android/bluetooth/BluetoothClass',
		'android/nfc/Tag', 'android/nfc/NdefMessage', 'android/hardware/usb/UsbDevice', 'android/hardware/usb/UsbAccessory']
	for name in types.clone() { types << name + r'$VinixCreator' }
	types << 'android/accounts/AccountManager'
	types << 'android/atl/VinixAccountFuture'
	types << 'android/telephony/TelephonyManager'
	types << 'android/content/IntentFilter'
	types << r'android/content/IntentFilter$MalformedMimeTypeException'
	types << 'android/provider/ContactsContract'
	types << 'android/content/Intent'
	types << 'android/net/ConnectivityManager'
	for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
		[java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', types.map('L' + it + ';').join(','), '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
		if os.system_args(args) != 0 { panic('assembly/readback failed') }
	}
	for name in types { if !os.is_file(root + '/roundtrip/' + name + '.smali') { panic('missing DEX type: ' + name) } }
	println('BLUETOOTH-VALUES-BUILD-PASS ' + root)
}
