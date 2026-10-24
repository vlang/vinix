import os

fn replace_once(source string, old string, replacement string) string {
	assert source.count(old) == 1, old
	return source.replace(old, replacement)
}

fn main() {
	previous := 'tests/android/results/2026-10-23/maps-popup-menus'
	out := 'tests/android/results/2026-10-23/maps-action-provider'
	assert !os.exists(out)
	os.mkdir_all(out)!
	mut retain := os.read_file(previous + '/retain.v')!
	mut validate := os.read_file(previous + '/validate.v')!
	retain = retain.replace('243', '244').replace('framework244-popup-menus', 'framework244-action-provider')
		.replace('maps-canvas-save', 'maps-popup-menus').replace('source-delta-from242', 'source-delta-from243')
		.replace('source-delta-from235', 'source-delta-from236')
		.replace('0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc', '__FRAMEWORK244_EXPECTED_SHA256__')
	retain = replace_once(retain, 'framework_sources.len == 112 && previous_framework.len == 111', 'framework_sources.len == 113 && previous_framework.len == 112')
	retain = replace_once(retain, "assert delta.len == 3\n\tfor name in ['tests/native-android-tools/androidtools/framework_classes.v',\n\t\t'tests/native-android-tools/androidtools/framework_popup_menus.v',\n\t\t'build-support/android/atlframework/menus.v']", "assert delta.len == 2\n\tfor name in ['tests/native-android-tools/androidtools/framework_classes.v',\n\t\t'tests/native-android-tools/androidtools/framework_action_provider.v']")
	retain = replace_once(retain, "assert native_delta.len == 1 && 'menus.v' in native_delta", 'assert native_delta.len == 0')
	retain = replace_once(retain, "framework + 'api-impl.jar', framework + 'classes.dex', 'suite239-stream', 'launcher200']", "framework + 'api-impl.jar', framework + 'classes.dex', 'suite239-stream', 'launcher200',\n\t\t'run244', 'interact244', 'manual244', 'identity244', 'verify-maps244-inputs']")
	retain = replace_once(retain, "'identity244.v', 'verify-maps244-inputs.v', 'trace-input.v', 'prepare-maps244-receipt.v',", "'identity244.v', 'verify-maps244-inputs.v', 'trace-input.v', 'prepare-maps244-receipt.v',\n\t\t'verify-maps244-delta.v', 'capture-maps244-inputs.v',")
	retain = replace_once(retain, "'build-framework244.log': 'framework244-build.log'\n\t\t'build-framework244-compile.log': 'framework244-compile.log'", "'framework244-build.log': 'framework244-build.log'")
	retain = replace_once(retain, "'native236-source-delta.json':             'native/builder-source-delta-from236.json'", "'native236-source-delta.json':             'native/builder-source-delta-from235.json'")
	retain = replace_once(retain, "'android/widget/PopupMenu.smali', 'android/widget/VinixPopupMenuClick.smali',", "'android/view/ActionProvider.smali', 'android/view/ActionProvider\$VisibilityListener.smali',\n\t\t'android/view/ActionProvider\$SubUiVisibilityListener.smali', 'android/view/MenuItem.smali',\n\t\t'android/widget/PopupMenu.smali', 'android/widget/VinixPopupMenuClick.smali',")
	start := retain.index("scope:                           '") or { panic('Missing scope') }
	end := retain.index_after("'\n\t}, prettify", start) or { panic('Missing scope end') }
	retain = retain[..start] + "scope:                           'Maps244 adds the real ActionProvider base API relative to Maps243. Only framework_classes.v and the new framework_action_provider.v change in the 113-source framework. The complete native236 83-source archive, APKs, launcher and frozen suite239-stream binary are unchanged. Exact V archives and selected generated Smali are retained; binary APK/JAR/ELF/DEX/kernel/firmware/image artifacts are identified by hashes. Pre-run image/kernel/EFI/QEMU hashes were recorded before runtime injection; staged runtime hashes identify the injected module. Raw application outcome is recorded separately after the run completes." + retain[end..]
	validate = validate.replace('243', '244').replace('framework244-popup-menus', 'framework244-action-provider')
		.replace('maps-canvas-save', 'maps-popup-menus').replace('source-delta-from242', 'source-delta-from243')
		.replace('source-delta-from235', 'source-delta-from236')
		.replace('0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc', '__FRAMEWORK244_EXPECTED_SHA256__')
	validate = replace_once(validate, 'framework.len == 112 && previous_framework.len == 111', 'framework.len == 113 && previous_framework.len == 112')
	validate = replace_once(validate, "assert path in ['tests/native-android-tools/androidtools/framework_classes.v',\n\t\t\t'tests/native-android-tools/androidtools/framework_popup_menus.v',\n\t\t\t'build-support/android/atlframework/menus.v']", "assert path in ['tests/native-android-tools/androidtools/framework_classes.v',\n\t\t\t'tests/native-android-tools/androidtools/framework_action_provider.v']")
	validate = replace_once(validate, 'assert changed == 3 && delta.len == 3', 'assert changed == 2 && delta.len == 2')
	validate = replace_once(validate, 'assert native_changed == 1 && native_delta.len == 1', 'assert native_changed == 0 && native_delta.len == 0')
	validate = replace_once(validate, "if path.ends_with('/api-impl.jar') || path.ends_with('/libvinix-android-native.so') { continue }", "if path.ends_with('/api-impl.jar') { continue }")
	validate = replace_once(validate, 'assert smali.len == 30', 'assert smali.len == 34')
	validate = replace_once(validate, "assert smali['android/view/VinixMenuItem.smali'].contains('vinixInvokeClick()Z')", "assert smali['android/view/VinixMenuItem.smali'].contains('vinixInvokeClick()Z')\n\tprovider := smali['android/view/ActionProvider.smali']\n\tassert provider.contains('.class public abstract Landroid/view/ActionProvider;')\n\tassert provider.contains('onCreateActionView()Landroid/view/View;')\n\tassert provider.contains('refreshVisibility()V')\n\tassert smali['android/view/ActionProvider\$VisibilityListener.smali'].contains('onActionProviderVisibilityChanged(Z)V')\n\tassert smali['android/view/ActionProvider\$SubUiVisibilityListener.smali'].contains('onSubUiVisibilityChanged(Z)V')\n\tassert smali['android/view/MenuItem.smali'].contains('setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;')\n\tassert smali['android/view/VinixMenuItem.smali'].contains('getActionProvider()Landroid/view/ActionProvider;')")
	check_start := validate.index("\t\tassert result['outcome']!.str() == 'startup_failed'") or { panic('Missing old result check') }
	check_end := validate.index_after("\n\t} else {", check_start) or { panic('Missing result check end') }
	validate = validate[..check_start] + "\t\tprintln('MAPS244-INTEGRITY PASS raw results/serial and observations retained; no success inferred from classifier')" + validate[check_end..]
	os.write_file(out + '/retain.v', retain)!
	os.write_file(out + '/validate.v', validate)!
	os.write_file(out + '/README.md', 'Maps244 evidence capture is in progress. Actual behavior will be recorded after root reviews the completed raw result and screenshots.\n\nThe 113-source framework adds ActionProvider and its framework_classes hook relative to Maps243. Native236 (83 sources), APKs, launcher and suite239-stream remain unchanged. Pre-run and staged runtime identities are retained separately.\n')!
	println('MAPS244 receipt scaffold prepared; expected JAR hash and actual result pending')
}
