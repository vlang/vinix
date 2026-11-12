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
	androidtools.framework_user_parcel(root + '/smali')!
	androidtools.framework_system_boolean(root + '/smali')!
	androidtools.framework_subscription_listener(root + '/smali')!
	androidtools.framework_shortcut_query(root + '/smali')!
	androidtools.framework_restrictions_service(root + '/smali')!
	androidtools.framework_stable_density(root + '/smali')!
	androidtools.framework_secure_longs(root + '/smali')!
	androidtools.framework_runtime_queries(root + '/smali')!
	androidtools.framework_account_package_query(root + '/smali')!
	androidtools.framework_user_broadcast(root + '/smali')!
	androidtools.framework_module_catalog(root + '/smali')!
	androidtools.framework_sandbox_metadata(root + '/smali')!
	androidtools.framework_build_base(root + '/smali')!
	androidtools.framework_package_observers(root + '/smali')!
	androidtools.framework_shared_library_catalog(root + '/smali')!
	androidtools.framework_job_install_queries(root + '/smali')!
	androidtools.framework_job_parameters(root + '/smali')!
	androidtools.framework_modem_identifiers(root + '/smali')!
	androidtools.framework_storage_stats_type(root + '/smali')!
	androidtools.framework_serial_tls_cache(root + '/smali')!
	androidtools.framework_force_layout(root + '/smali')!
	androidtools.framework_certificate_factory(root + '/smali')!
	androidtools.framework_guest_user(root + '/smali')!
	androidtools.framework_service_create_failure(root + '/smali')!
	androidtools.framework_result_receiver(root + '/smali')!
	androidtools.framework_bluetooth_unavailable(root + '/smali')!
	androidtools.framework_contacts_directory(root + '/smali')!
	androidtools.framework_vm_policy(root + '/smali')!
	androidtools.framework_display_sms(root + '/smali')!
	androidtools.framework_update_policy(root + '/smali')!
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
	types << 'android/os/UserHandle'
	types << 'android/os/SystemProperties'
	types << 'android/telephony/SubscriptionManager'
	types << 'android/content/pm/ShortcutManager'
	types << 'android/content/RestrictionsManager'
	types << 'android/app/ContextImpl'
	types << 'android/content/Context'
	types << 'android/util/DisplayMetrics'
	types << r'android/provider/Settings$Secure'
	types << 'android/os/UserManager'
	types << 'android/content/pm/ApplicationInfo'
	types << 'android/content/pm/PackageManager'
	types << 'android/content/pm/PackageInstaller'
	types << 'android/app/job/JobInfo'
	types << 'android/app/job/JobParameters'
	types << 'android/app/usage/StorageStatsManager'
	types << 'android/os/Build'
	types << 'android/net/SSLSessionCache'
	types << 'android/view/View'
	types << 'android/net/SSLCertificateSocketFactory'
	types << 'android/net/VinixCertificateSocket'
	types << 'android/net/VinixCertificateInput'
	types << 'android/net/VinixCertificateOutput'
	types << 'android/atl/ATLLoadedApp'
	types << r'android/atl/ATLLoadedApp$1'
	types << 'android/os/ResultReceiver'
	types << 'android/os/VinixResultReceiverBinder'
	types << 'android/os/VinixResultReceiverDelivery'
	types << 'android/os/VinixResultReceiverCreator'
	types << 'android/bluetooth/BluetoothAdapter'
	types << 'android/bluetooth/BluetoothManager'
	types << r'android/provider/ContactsContract$Directory'
	types << 'android/os/StrictMode'
	types << 'android/view/Display'
	types << 'android/hardware/display/DisplayManager'
	types << r'android/provider/Telephony$Sms'
	types << 'android/app/admin/DevicePolicyManager'
	types << 'android/app/admin/SystemUpdatePolicy'
	types << r'android/os/StrictMode$VmPolicy'
	types << r'android/os/StrictMode$VmPolicy$Builder'
	types << r'android/os/StrictMode$OnVmViolationListener'
	types << r'android/app/job/JobInfo$Builder'
	types << 'android/content/pm/PackageParser'
	types << 'android/content/pm/IPackageDeleteObserver'
	types << 'android/content/pm/IPackageDataObserver'
	types << r'android/os/Build$VERSION'
	types << 'android/telephony/VinixSubscriptionFailure'
	types << r'android/telephony/SubscriptionManager$OnSubscriptionsChangedListener'
	types << r'android/os/UserHandle$VinixCreator'
	for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
		[java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', types.map('L' + it + ';').join(','), '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
		if os.system_args(args) != 0 { panic('assembly/readback failed') }
	}
	for name in types { if !os.is_file(root + '/roundtrip/' + name + '.smali') { panic('missing DEX type: ' + name) } }
	println('BLUETOOTH-VALUES-BUILD-PASS ' + root)
}
