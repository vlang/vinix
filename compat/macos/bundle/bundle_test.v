module bundle

fn test_reads_bundle_executable() {
	data := '<plist><dict>\n<key>CFBundleExecutable</key>\n<string>Cocoa &amp; Calc</string>\n</dict></plist>'.bytes()
	assert executable_name(data) or { panic(err) } == 'Cocoa & Calc'
}

fn test_rejects_path_in_bundle_executable() {
	executable_name('<key>CFBundleExecutable</key><string>../bad</string>'.bytes()) or {
		assert err.msg().contains('unsafe')
		return
	}
	assert false
}

fn test_requires_executable_key() {
	executable_name('<plist><dict></dict></plist>'.bytes()) or {
		assert err.msg().contains('no CFBundleExecutable')
		return
	}
	assert false
}
