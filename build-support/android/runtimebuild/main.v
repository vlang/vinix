module runtimebuild

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	e := Engine{ah.field(row, 'constants').object(), text(row, 'source'), text(row, 'root'), text(row, 'support')}
	return match text(row, 'operation') {
		'art_tools', 'musl_tools', 'runtime_tools' {
			result_object(e.tools(text(row, 'operation'))!)
		}
		'main' { e.main(borrow('args')!)! }
		'stage' {
			result_object(e.stage(borrow('args')!, borrow('package_lock')!, borrow('downloads')!)!)
		}
		'make_lock' { result_object(e.make_lock(borrow('downloads')!, borrow('mirror')!)!) }
		'fetch_lock' {
			result_object(e.fetch_lock(borrow('item')!, borrow('downloads')!, borrow('mirror')!)!)
		}
		'fetch_package' {
			result_object(fetch_package(borrow('item')!, borrow('downloads')!, borrow('package_lock')!)!)
		}
		'extract_apk' {
			extract(borrow('archive')!, borrow('target')!)!
			null()
		}
		'sha256' { ah.Value(digest(borrow('path')!)!) }
		'download' {
			result_object(download(borrow('url')!, borrow('target')!, borrow('expected')!)!)
		}
		'calculator_apk' { result_object(e.calculator(borrow('downloads')!)!) }
		'relocate_configuration' {
			e.relocate(borrow('runtime')!)!
			null()
		}
		'materialize_library_links' {
			materialize(borrow('runtime')!)!
			null()
		}
		else { return error('Unknown Android runtime builder operation ' + text(row, 'operation')) }
	}
}
