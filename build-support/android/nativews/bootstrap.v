// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Shared ART, framework and main-Looper startup. No Application or component
// callback runs here: service launch policy is checked before APK startup.
fn ws_bootstrap(root &char, apk &char, display bool) voidptr {
	unsafe {
		// The framework enumerates ICU converters through the stable native
		// provider API. ART loads javacore locally, so expose that provider
		// explicitly instead of relying on another toolkit's dependency scope.
		if C.dlopen(c'libicuuc.so.78', 2 | 256) == nil {
			C.puts(C.dlerror())
			return nil
		}
		art := C.dlopen(c'libart.so', 2 | 256)
		if art == nil {
			C.puts(C.dlerror())
			return nil
		}
		// The Bionic linker publishes mapped APK libraries through the host's
		// debugger rendezvous. ATL's executable normally supplies this pointer;
		// our native entry point must initialize it before the first NDK load.
		debug_target := C.dlsym(art, c'_r_debug_ptr')
		debug_host := C.dlsym(nil, c'_dl_debug_addr')
		if debug_target == nil || debug_host == nil || *(&voidptr(debug_host)) == nil {
			C.puts(c'ANDROID-WS-FAIL native linker debugger ABI')
			return nil
		}
		*(&voidptr(debug_target)) = *(&voidptr(debug_host))
		options := &WsOption(C.alloca(16 * sizeof(WsOption)))
		buffer := &char(C.alloca(49152))
		C.snprintf(buffer, 8192, c'-Djava.class.path=%s/usr/lib/java/dex/android_translation_layer/api-impl.jar:%s/usr/lib/java/dex/android_translation_layer/framework-res.apk', root, root)
		options[0] = WsOption{buffer, nil}
		C.snprintf(&buffer[8192], 8192, c'-Datl.app.class.path=%s', apk)
		options[1] = WsOption{&buffer[8192], nil}
		C.snprintf(&buffer[16384], 8192, c'-Djava.library.path=%s/usr/lib/art', root)
		options[2] = WsOption{&buffer[16384], nil}
		mut native := C.getenv(c'VINIX_ANDROID_NATIVE_DIR')
		if native == nil { native = c'' }
		C.snprintf(&buffer[24576], 8192, c'-Datl.app.library.path=%s', native)
		options[3] = WsOption{&buffer[24576], nil}
		options[4] = WsOption{c'-Xcheck:jni', nil}
		options[5] = WsOption{c'-Xnoimage-dex2oat', nil}
		options[6] = WsOption{c'-Xusejit:false', nil}
		// ART's upstream ANDROID_ROOT fallback concatenates "dex2oat"
		// directly to the root. Use the executable in our private runtime.
		C.snprintf(&buffer[32768], 8192, c'-Xcompiler:%s/usr/bin/dex2oat', root)
		options[7] = WsOption{&buffer[32768], nil}
		options[8] = WsOption{c'exit', voidptr(ws_vm_exit)}
		// WolfJSSE uses JVM trust-store properties rather than SSL_CERT_FILE.
		// Use the private JKS generated when staging this runtime, just as the
		// command-line launcher does, before any default SSLContext is created.
		C.snprintf(&buffer[40960], 8192, c'-Djavax.net.ssl.trustStore=%s/etc/ssl/certs/java/cacerts', root)
		options[9] = WsOption{&buffer[40960], nil}
		options[10] = WsOption{c'-Djavax.net.ssl.trustStoreType=JKS', nil}
		options[11] = WsOption{c'-Djavax.net.ssl.trustStorePassword=changeit', nil}
		mut args := WsVmArgs{ version: 0x10006, count: 12, options: options }
		trace_tls := C.getenv(c'VINIX_ANDROID_TRACE_TLS')
		if trace_tls != nil && trace_tls[0] == `1` {
			options[12] = WsOption{c'-Dwolfjsse.debug=true', nil}
			options[13] = WsOption{c'-Dwolfssljni.debug=true', nil}
			args.count = 14
		}
		create := CreateVM(C.dlsym(art, c'JNI_CreateJavaVM'))
		if create(&ws.vm, &ws.e, &args) != 0 { return nil }
		ws_trace_tls_logging(ws.e)
		ws_start_diagnostics(ws.vm)
		e := ws.e
		C.snprintf(&buffer[24576], 8192, c'%s/usr/lib/art/libvinix-android-native.so', root)
		if !ws_load_jni(e, &buffer[24576]) { return nil }
		ws_install_exception_reporter(e)
		if ws_failure(e, c'ANDROID-WS-FAIL exception reporter') { return nil }
		if register_activity(e) != 0 || register_action_bar(e) != 0 || register_menu(e) != 0 || register_menu_item(e) != 0 || register_menu_click(e) != 0 || register_theme(e) != 0 || register_view(e) != 0 || register_list_click(e) != 0 || register_search(e) != 0 || register_search_callbacks(e) != 0 || register_simple_cursor(e) != 0 || register_charsets(e) != 0 {
			ws_failure(e, c'ANDROID-WS-FAIL framework')
			return nil
		}
		if register_dialog_builder(e) != 0 || register_dialog_click(e) != 0 || register_recreate(e) != 0 {
			return nil
		}
		if !ws_install_digests(e, root) {
			ws_failure(e, c'ANDROID-WS-FAIL native digests')
			return nil
		}
		static_void(e, c'com/android/org/conscrypt/OpenSSLProvider', c'install', c'()V', nil)
		if ws_failure(e, c'ANDROID-WS-FAIL TLS provider adapter') { return nil }
		if display {
			ws_static_int(e, c'android/view/Display', c'window_width', ws.width)
			ws_static_int(e, c'android/view/Display', c'window_height', ws.height)
		}
		static_void(e, c'android/os/Looper', c'prepareMainLooper', c'()V', nil)
		if ws_failure(e, c'ANDROID-WS-FAIL prepare main looper') { return nil }
		// Application.attachBaseContext and onCreate must complete before any
		// Activity class initialization or constructor can access app globals.
		// Context's class initializer creates the PackageManager from the primary
		// package. Initialize it first: loading the primary package while Context
		// is uninitialized recursively parses a second package, leaving the
		// PackageManager and Application with different ApplicationInfo objects.
		static_obj(e, c'android/content/Context', c'native_get_apk_path', c'()Ljava/lang/String;', nil)
		if ws_failure(e, c'ANDROID-WS-FAIL initialize context') { return nil }
		loaded := static_obj(e, c'android/atl/ATLLoadedApp', c'getPrimaryApplication', c'()Landroid/atl/ATLLoadedApp;', nil)
		pkg := get_object(e, loaded, c'android/atl/ATLLoadedApp', c'pkg', c'Landroid/content/pm/PackageParser$Package;')
		info := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'applicationInfo', c'Landroid/content/pm/ApplicationInfo;')
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'dataDir', c'Ljava/lang/String;', ws_string(e, ws.data))
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'sourceDir', c'Ljava/lang/String;', ws_string(e, apk))
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'publicSourceDir', c'Ljava/lang/String;', ws_string(e, apk))
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'nativeLibraryDir', c'Ljava/lang/String;', ws_string(e, native))
		if ws_failure(e, c'ANDROID-WS-FAIL application paths') { return nil }
		return loaded
	}
}
