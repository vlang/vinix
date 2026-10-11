module main

import os

fn test_native_runtime_inputs_keep_the_workload_and_architecture_assertion() {
	for language, source in {
		'go': $embed_file('../../../tests/go/smoke.go').to_string()
		'java': $embed_file('../../../tests/java/VinixJavaSmoke.java').to_string()
	} {
		assert native_runtime_fixture(language, 'native-aarch64', source)! == source
		x86 := native_runtime_fixture(language, 'native-x86_64', source)!
		assert x86.contains('"amd64"') && x86.len > 2000
		assert x86.replace('"amd64"', if language == 'go' { '"arm64"' } else { '"aarch64"' })
			.replace('VINIX AMD64 GO SMOKE', 'VINIX ARM64 GO SMOKE')
			.replace('x86-64 Go runtime', 'AArch64 Go runtime') == source
	}
}

fn test_runtime_generation_refuses_unknown_inputs_and_foreign_compilation() {
	for path in ['translated-i386', 'translated-x86_64', 'host'] {
		native_runtime_fixture('go', path, 'runtime.GOARCH == "arm64"') or { continue }
		assert false, 'foreign runtime compiler policy was silently selected'
	}
	for source in ['', 'runtime.GOARCH == "amd64"', 'runtime.GOARCH == "arm64" runtime.GOARCH == "arm64"'] {
		native_runtime_fixture('go', 'native-x86_64', source) or { continue }
		assert false, 'unexpected application input was accepted'
	}
}

fn test_jdk_tools_must_all_be_executable_in_one_directory() {
	root := os.join_path(os.temp_dir(), 'vinix-jdk-tools-' + os.getpid().str())
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	assert !complete_java_bin(root)
	for tool in ['java', 'javac', 'jar'] {
		os.write_file(root + '/' + tool, 'fixture')!
		os.chmod(root + '/' + tool, 0o755)!
	}
	assert complete_java_bin(root)
	os.chmod(root + '/javac', 0o644)!
	assert !complete_java_bin(root)
}
