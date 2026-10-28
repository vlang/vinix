// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Public base configurations have a measured 560-byte record. This profile
// stores settings only. Default and background factories are supported; their
// unresolved built-in protocols, persistent/shared stores and session loading
// remains an explicit unsupported boundary.
// Ownership follows the allocation, independently of its current isa.
fn url_session_configuration_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSURLSessionConfiguration' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic session configuration superclass chain')
}

fn url_session_configuration_require_class(cls u64) {
	if url_session_configuration_family(cls) && cls != ios_runtime.names['NSURLSessionConfiguration'] {
		panic('iOS: custom session configuration subclass construction is not implemented')
	}
}

fn url_session_configuration_initialize(object u64) {
	for i, value in [u32(6), 4, 2, 4, 0, 1]! { write32(object + 8 + u64(i * 4), value) }
	for i, value in [f64(30), 1, 120, 120]! { unsafe { *(&f64(object + 32 + u64(i * 8))) = value } }
}

fn url_session_configuration_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSURLSessionConfiguration']] or { panic('iOS: missing session configuration class') }
	cls.ivars['_limits'] = &ObjIvar{name: '_limits'.clone(), types: '{HTTPConnectionCacheLimits="fHTTPLoadWidth"i"fHTTPPipeliningHighWatermark"i"fHTTPPipeliningLowWatermark"i"fHTTPPriorityNumLevels"i"fHTTPNumFastLanes"i"fHTTPMinimumFastLanePriority"i"fHTTPConnectionCachePurgeTimeout"d"fHTTPConnectionCacheCellPurgeTimeout"d"fLongLivedConnectionCachePurgeTimeout"d"fLongLivedConnectionCacheCellPurgeTimeout"d}'.clone(), offset: 8, size: 56}
	for i, name in ['_allowsCellularAccess', '_allowsExpensiveNetworkAccess', '_allowsConstrainedNetworkAccess',
		'_waitsForConnectivity', '_discretionary', '_sessionSendsLaunchEvents', '_HTTPShouldUsePipelining',
		'_HTTPShouldSetCookies', '_requiresDNSSECValidation', '_usesClassicLoadingMode', '_enablesEarlyData',
		'_requiresPowerPluggedIn', '_reportsDataStalls', '_allowsPowerNapScheduling',
		'_allowsHSTSWithUntrustedRootCertificate', '_preventsIdleSleepOnceConnected',
		'_sessionSendsLaunchOnDemandEvents', '_shouldSkipPreferredClientCertificateLookup', '_explicitlySetATSContext',
		'_allowsRetryForBackgroundDataTasks', '_onBehalfOfPairedDevice', '_clientIsNotExplicitlyDiscretionary',
		'_respectsAllowsCellularAccessForDiscretionaryTasks', '_overridesBackgroundSessionAutoRedirect',
		'_performsEVCertCheck', '_infersDiscretionaryFromOriginatingClient', '_prefersInfraWiFi',
		'_allowsMultipathTCP', '_allowsResponseMonitoringDuringBodyTranmission', '_allowsIndefiniteConnections',
		'_allowsTCPFastOpen', '_allowsTLSSessionTickets', '_allowsTLSSessionResumption', '_allowsTLSFalseStart',
		'_allowsTLSFallback', '_allowsTLSECH', '_forceEnablePQTLS', '_preventsDirectWiFiAccess',
		'_allowTCPIOConnectionStreamTask', '_preventsSystemHTTPProxyAuthentication', '_requiresSecureHTTPSProxyConnection',
		'_preventsAppSSO', '_duetPreauthorized', '_xpcActivityBudgeted', '_requiresSustainedDataDelivery',
		'_ignoreDidReceiveResponseDisposition', '_alwaysPerformDefaultTrustEvaluation', '_enableOAuthBearerTokenChallenges',
		'_allowsUltraConstrainedInternal', '_allowsVirtualInterfaces', '_systemClientOfPrivateAccessTokens',
		'_prohibitEncryptedDNS', '_disableAPWakeOnIdleConnections', '_backgroundSession', '_phskip_credStorageSet',
		'_phskip_urlCacheSet', '_phskip_cookieStorageSet', '_phskip_hstsStorageSet', '_skip_download_unlink',
		'_requiresClientToOpenFiles', '_forcesNewConnections', '_supportsAVAssetDownloads', '_proxySession',
		'_preventsIdleSleep', '_usePipeliningHeuristics', '_shouldPreserveBackgroundSessionDisposition',
		'_disablesOutOfProcessDirectWiFiUsage', '_disablesUseOfProxySession', '_allowsHTTP3Internal',
		'_phskip_alternativeServicesStorageSet', '_disablesNWLoader', '_enablesL4SInternal',
		'_backgroundSessionForPrivilegedDaemon', '__allowsWCA', '__skipsStackTraceCapture']! {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: (if i in [43, 48, 68, 71]! { 'C' } else { 'B' }).clone(), offset: i64(64 + i), size: 1}
	}
	for i, name in ['_TLSMinimumSupportedProtocol', '_TLSMaximumSupportedProtocol', '_loggingPrivacyLevel', '_pidForHAR', '_neTrackerTCCResult']! {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: 'i'.clone(), offset: i64(140 + i * 4), size: 4}
	}
	names := ['_identifier', '_requestCachePolicy', '_timeoutIntervalForRequest', '_timeoutIntervalForResource',
		'_networkServiceType', '_sharedContainerIdentifier', '_connectionProxyDictionary', '_HTTPCookieAcceptPolicy',
		'_HTTPAdditionalHeaders', '_protocolClasses', '_directoryForDownloadedFiles', '_sourceApplicationBundleIdentifier',
		'_sourceApplicationSecondaryIdentifier', '_sourceApplicationAuditTokenData', '_attributedBundleIdentifier',
		'_TCPAdaptiveReadTimeout', '_TCPAdaptiveWriteTimeout', '_timingDataOptions', '_appleIDContext', '_atsContext',
		'_connectionPoolName', '_CTDataConnectionServiceType', '_tlsTrustPinningPolicyName', '_customReadBufferSize',
		'_customReadBufferTimeout', '_proxyConfigurations', '_duetPreClearedMode', '_xpcActivity', '_IDSMessageTimeout',
		'_maximumWatchCellularTransferSize', '_multipathAlternatePort', '_suppressedAutoAddedHTTPHeaders',
		'_expiredDNSBehavior', '_downloadFileProtectionType', '_disposition', '_phskip_credStorage', '_phskip_urlCache',
		'_phskip_cookieStorage', '_phskip_hstsStorage', '_tcpConnectionPoolName', '_socketStreamProperties',
		'_authenticatorStatusCodes', '_companionAppBundleIdentifier', '_watchAppBundleIdentifier',
		'_watchExtensionBundleIdentifier', '_forcedNetworkServiceType', '_overriddenDelegateOptions',
		'_phskip_alternativeServicesStorage', '_multipathServiceType', '__companionProxyPreference']!
	types := ['@"NSString"', 'Q', 'd', 'd', 'Q', '@"NSString"', '@"NSDictionary"', 'Q', '@"NSDictionary"', '@"NSArray"',
		'@"NSURL"', '@"NSString"', '@"NSString"', '@"NSData"', '@"NSString"', 'Q', 'Q', 'q',
		'@"<NSURLSessionAppleIDContext>"', '@"NSData"', '@"NSString"', '@"NSString"', '@"NSString"', 'Q', 'd',
		'@"NSArray"', 'q', '@"NSObject<OS_xpc_object>"', 'q', '@"NSNumber"', 'Q', '@"NSSet"', 'q', '@"NSString"',
		'@"NSString"', '@"NSURLCredentialStorage"', '@"NSURLCache"', '@"NSHTTPCookieStorage"', '@"_NSHSTSStorage"',
		'@"NSString"', '@"NSDictionary"', '@"NSSet"', '@"NSString"', '@"NSString"', '@"NSString"', 'Q',
		'@"NSDictionary"', '@"_NSHTTPAlternativeServicesStorage"', 'q', 'q']!
	for i, name in names {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: types[i].clone(), offset: i64(160 + i * 8), size: 8}
	}
}

fn url_session_configuration_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.url_session_configuration_owned || header.native_size < 560 || header.destroying || header.destroyed {
		panic('iOS: session configuration requires live base configuration storage')
	}
	return header
}

enum SessionConfigurationKind { object boolean unsigned signed integer real connections }
struct SessionConfigurationProperty { offset u64 kind SessionConfigurationKind }

fn url_session_configuration_property(selector string) ?SessionConfigurationProperty {
	return match selector {
		'identifier', 'setIdentifier:' { SessionConfigurationProperty{160, .object} }
		'sharedContainerIdentifier', 'setSharedContainerIdentifier:' { SessionConfigurationProperty{200, .object} }
		'connectionProxyDictionary', 'setConnectionProxyDictionary:' { SessionConfigurationProperty{208, .object} }
		'HTTPAdditionalHeaders', 'setHTTPAdditionalHeaders:' { SessionConfigurationProperty{224, .object} }
		'protocolClasses', 'setProtocolClasses:' { SessionConfigurationProperty{232, .object} }
		'allowsCellularAccess', 'setAllowsCellularAccess:' { SessionConfigurationProperty{64, .boolean} }
		'allowsExpensiveNetworkAccess', 'setAllowsExpensiveNetworkAccess:' { SessionConfigurationProperty{65, .boolean} }
		'allowsConstrainedNetworkAccess', 'setAllowsConstrainedNetworkAccess:' { SessionConfigurationProperty{66, .boolean} }
		'waitsForConnectivity', 'setWaitsForConnectivity:' { SessionConfigurationProperty{67, .boolean} }
		'isDiscretionary', 'setDiscretionary:' { SessionConfigurationProperty{68, .boolean} }
		'sessionSendsLaunchEvents', 'setSessionSendsLaunchEvents:' { SessionConfigurationProperty{69, .boolean} }
		'HTTPShouldUsePipelining', 'setHTTPShouldUsePipelining:' { SessionConfigurationProperty{70, .boolean} }
		'HTTPShouldSetCookies', 'setHTTPShouldSetCookies:' { SessionConfigurationProperty{71, .boolean} }
		'requiresDNSSECValidation', 'setRequiresDNSSECValidation:' { SessionConfigurationProperty{72, .boolean} }
		'TLSMinimumSupportedProtocol', 'setTLSMinimumSupportedProtocol:' { SessionConfigurationProperty{140, .integer} }
		'TLSMaximumSupportedProtocol', 'setTLSMaximumSupportedProtocol:' { SessionConfigurationProperty{144, .integer} }
		'requestCachePolicy', 'setRequestCachePolicy:' { SessionConfigurationProperty{168, .unsigned} }
		'networkServiceType', 'setNetworkServiceType:' { SessionConfigurationProperty{192, .unsigned} }
		'HTTPCookieAcceptPolicy', 'setHTTPCookieAcceptPolicy:' { SessionConfigurationProperty{216, .unsigned} }
		'multipathServiceType', 'setMultipathServiceType:' { SessionConfigurationProperty{544, .signed} }
		'timeoutIntervalForRequest', 'setTimeoutIntervalForRequest:' { SessionConfigurationProperty{176, .real} }
		'timeoutIntervalForResource', 'setTimeoutIntervalForResource:' { SessionConfigurationProperty{184, .real} }
		'HTTPMaximumConnectionsPerHost', 'setHTTPMaximumConnectionsPerHost:' { SessionConfigurationProperty{8, .connections} }
		else { return none }
	}
}

fn url_session_configuration_types(name string, meta bool, selector string) ?string {
	if name != 'NSURLSessionConfiguration' { return none }
	if meta {
		return match selector {
			'new', 'defaultSessionConfiguration' { '@16@0:8' }
			'backgroundSessionConfigurationWithIdentifier:', 'backgroundSessionConfiguration:' { '@24@0:8@16' }
			else { return none }
		}
	}
	if selector in ['init', 'copy']! { return '@16@0:8' }
	if selector == 'copyWithZone:' { return '@24@0:8^{_NSZone=}16' }
	property := url_session_configuration_property(selector) or { return none }
	setter := selector.starts_with('set')
	return match property.kind {
		.object { if setter { 'v24@0:8@16' } else { '@16@0:8' } }
		.boolean { if setter { 'v20@0:8B16' } else { 'B16@0:8' } }
		.unsigned { if setter { 'v24@0:8Q16' } else { 'Q16@0:8' } }
		.signed, .connections { if setter { 'v24@0:8q16' } else { 'q16@0:8' } }
		.integer { if setter { 'v20@0:8i16' } else { 'i16@0:8' } }
		.real { if setter { 'v24@0:8d16' } else { 'd16@0:8' } }
	}
}

fn url_session_configuration_unsupported(selector string) bool {
	return selector in ['ephemeralSessionConfiguration',
		'HTTPCookieStorage', 'setHTTPCookieStorage:', 'URLCredentialStorage', 'setURLCredentialStorage:',
		'URLCache', 'setURLCache:', 'TLSMinimumSupportedProtocolVersion', 'setTLSMinimumSupportedProtocolVersion:',
		'TLSMaximumSupportedProtocolVersion', 'setTLSMaximumSupportedProtocolVersion:',
		'shouldUseExtendedBackgroundIdleMode', 'setShouldUseExtendedBackgroundIdleMode:',
		'proxyConfigurations', 'setProxyConfigurations:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'description', 'isEqual:', 'hash']!
		|| selector.starts_with('initWith')
}

fn url_session_configuration_reference(offset u64) int {
	return match offset { 160 { 0 } 200 { 1 } 208 { 2 } 224 { 3 } 232 { 4 } else { panic('iOS: invalid configuration reference slot') } }
}

fn url_session_configuration_value(value u64, index int) {
	if value == 0 { return }
	name := if index < 2 { 'NSString' } else if index == 4 { 'NSArray' } else { 'NSDictionary' }
	if !objc_is_kind(value, ios_runtime.names[name]) { panic('iOS: configuration property has the wrong object type') }
	if index >= 2 {
		header := obj_header(value)
		if header.cf_raw_keys || header.cf_raw_values || header.items.len > 1024 {
			panic('iOS: configuration collections require at most 1024 owned objects')
		}
	}
}

fn url_session_configuration_copy(object u64) u64 {
	objc_retain(object)
	defer { objc_release(object) }
	mut bytes := [560]u8{}
	mut refs := [5]u64{}
	C.ios_objc_initialize_lock()
	source := url_session_configuration_state(object)
	unsafe { C.memcpy(&bytes[0], voidptr(object), 560) }
	default_protocols := source.url_session_configuration_default_protocols
	for i in 0 .. 5 { refs[i] = objc_retain(source.fields[i]) }
	C.ios_objc_initialize_unlock()
	// Allocation can run a replaced +initialize or C++ constructor. The captured
	// bytes and references must survive source mutation/destruction during it.
	copy := objc_allocate(ios_runtime.names['NSURLSessionConfiguration'])
	if copy == 0 { for value in refs { objc_release(value) }; return 0 }
	mut retired := [5]u64{}
	C.ios_objc_initialize_lock()
	mut target := url_session_configuration_state(copy)
	target.url_session_configuration_default_protocols = default_protocols
	unsafe { C.memcpy(voidptr(copy + 8), &bytes[8], 552) }
	for i, offset in [u64(160), 200, 208, 224, 232]! {
		retired[i] = target.fields[i]
		target.fields[i] = refs[i]
		unsafe { *(&u64(copy + offset)) = refs[i] }
	}
	C.ios_objc_initialize_unlock()
	for value in retired { objc_release(value) }
	return copy
}

fn url_session_configuration_factory(cls u64, identifier u64, background bool) u64 {
	url_session_configuration_require_class(cls)
	mut copied := u64(0)
	if background {
		if identifier == 0 { panic('iOS: background session configuration requires a non-nil identifier') }
		url_session_configuration_value(identifier, 0)
		// Both copying and construction can invoke application code. Pin the
		// caller's identifier across copy and capture its value before allocation.
		objc_retain(identifier)
		copied = objc_copy_value(identifier, false)
		objc_release(identifier)
		if copied == 0 { panic('iOS: configuration property copy returned nil') }
		url_session_configuration_value(copied, 0)
	}
	object := objc_new(cls)
	if object == 0 { objc_release(copied); return 0 }
	C.ios_objc_initialize_lock()
	mut header := url_session_configuration_state(object)
	for offset in [u64(64), 65, 66, 71]! { unsafe { *(&u8(object + offset)) = 1 } }
	write32(object + 140, 8) // kTLSProtocol12; modern-version selectors remain unsupported.
	unsafe {
		*(&u64(object + 216)) = 2 // NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain
		*(&f64(object + 176)) = 60.0
		*(&f64(object + 184)) = 604800.0
	}
	mut retired := u64(0)
	if background {
		retired = header.fields[0]
		header.fields[0] = copied
		unsafe {
			*(&u64(object + 160)) = copied
			*(&u8(object + 69)) = 1 // sessionSendsLaunchEvents
			*(&u8(object + 117)) = 1 // _backgroundSession, measured common prefix
		}
	}
	// Do not expose nil/empty built-in protocols as a usable transport profile.
	// An explicit protocolClasses setter replaces this unresolved default.
	header.url_session_configuration_default_protocols = true
	C.ios_objc_initialize_unlock()
	objc_release(retired)
	return objc_autorelease(object)
}

fn url_session_configuration_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !url_session_configuration_family(if meta { object } else { read64(object) }) { return false }
	if url_session_configuration_unsupported(selector) {
		panic('iOS: configuration factories, stores, coding and this property are not implemented: ' + selector)
	}
	if url_session_configuration_types('NSURLSessionConfiguration', meta, selector) == none { return false }
	if meta {
		frame.x[0] = match selector {
			'defaultSessionConfiguration' { url_session_configuration_factory(object, 0, false) }
			'backgroundSessionConfigurationWithIdentifier:', 'backgroundSessionConfiguration:' { url_session_configuration_factory(object, frame.x[2], true) }
			else { objc_new(object) }
		}
		return true
	}
	if selector in ['copy', 'copyWithZone:']! { frame.x[0] = url_session_configuration_copy(object); return true }
	if selector == 'init' { url_session_configuration_state(object); return true }
	property := url_session_configuration_property(selector) or { return false }
	setter := selector.starts_with('set')
	if property.kind == .object && setter {
		objc_retain(object)
		defer { objc_release(object) }
		index := url_session_configuration_reference(property.offset)
		value := frame.x[2]
		url_session_configuration_value(value, index)
		// User copy methods and deallocation callbacks run outside the state lock.
		copied := if value == 0 { u64(0) } else { objc_copy_value(value, false) }
		if value != 0 && copied == 0 { panic('iOS: configuration property copy returned nil') }
		url_session_configuration_value(copied, index)
		C.ios_objc_initialize_lock()
		mut header := url_session_configuration_state(object)
		retired := header.fields[index]
		header.fields[index] = copied
		if index == 4 { header.url_session_configuration_default_protocols = false }
		unsafe { *(&u64(object + property.offset)) = copied }
		C.ios_objc_initialize_unlock()
		objc_release(retired)
		return true
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := url_session_configuration_state(object)
	if selector == 'protocolClasses' && header.url_session_configuration_default_protocols {
		panic('iOS: default session protocol classes are not implemented')
	}
	address := object + property.offset
	value := frame.x[2]
	match property.kind {
		.object { frame.x[0] = objc_retain_autorelease(header.fields[url_session_configuration_reference(property.offset)]) }
		.boolean { if setter { unsafe { *(&u8(address)) = u8(u8(value) != 0) } } else { frame.x[0] = unsafe { u64(*(&u8(address))) } } }
		.unsigned, .signed { if setter { unsafe { *(&u64(address)) = value } } else { frame.x[0] = read64(address) } }
		.integer { if setter { write32(address, u32(value)) } else { frame.x[0] = u64(read32(address)) } }
		.real {
			if setter {
				real := frame_double(frame, 0)
				if !math.is_finite(real) { panic('iOS: configuration timeouts require finite values') }
				unsafe { *(&f64(address)) = real }
			} else { frame_float_return(mut frame, 0, unsafe { *(&f64(address)) }) }
		}
		.connections {
			if setter {
				write32(address, u32(value))
			} else { frame.x[0] = u64(i64(i32(read32(address)))) }
		}
	}
	return true
}

fn url_session_configuration_dispose(object u64, header &ObjHeader) {
	if !header.url_session_configuration_owned { return }
	// Generic fields release the five copied references after this clears the
	// public record, including when objc_destructInstance leaves caller bytes.
	for offset in [u64(160), 200, 208, 224, 232]! { unsafe { *(&u64(object + offset)) = 0 } }
}
