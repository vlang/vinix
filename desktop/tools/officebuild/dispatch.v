module officebuild

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'run' { run(args[0], args[1])! }
		'load_build_state' { return ah.Value(load_build_state(args[0])!) }
		'write_build_state' { write_build_state(args[0], args[1], args[2])! }
		'output_binary' { return ah.Value(output_binary(args[0], args[1])!) }
		'usable_cached_binary' { return ah.Value(usable_cached_binary(args[0], args[1])!) }
		'reset_directory' { reset_directory(args[0], args[1])! }
		'compiler_root' { return ah.Value(compiler_root(args[0])!) }
		'cc_base' { return ah.Value(cc_base(args[0], args[1])!) }
		'mbedtls_sources' { return ah.Value(mbedtls_sources(args[0])!) }
		'compile_mbedtls_source' {
			return ah.Value(compile_mbedtls_source(args[0], args[1], args[2], args[3])!)
		}
		'build_mbedtls' { return ah.Value(build_mbedtls(args[0], args[1])!) }
		'compile_app' { compile_app(args[0], args[1], args[2], args[3], args[4])! }
		'validate_inputs' { validate_inputs(args[0])! }
		'main' { build_main(args[0])! }
		else { return error('Unknown VOffice build operation') }
	}
	return none_value()
}
