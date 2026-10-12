// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import androidhost as ah
import buildcore
import encoding.hex
import gamehost
import hosttest
import json2
import os
import runtime
import vulkanbuild

fn field(row map[string]json2.Any, name string) json2.Any { return row[name] or { json2.Null{} } }

fn text(row map[string]json2.Any, name string) string { return field(row, name).str() }

fn tagged_path(value string) json2.Any {
	return json2.Any({
		'path_hex': json2.Any(value.bytes().hex())
	})
}

fn value_path(value json2.Any) !string {
	return hex.decode(value.as_map()['path_hex']!.str())!.bytestr()
}

pub fn policy_value(value ah.Value) buildcore.Value {
	return match value {
		string { buildcore.Value(value) }
		bool { buildcore.Value(value) }
		ah.Number {
			buildcore.Value(buildcore.Number{ raw: value.text, integer: !value.text.contains_any('.eE') && value.text !in [
				'nan',
				'inf',
				'-inf',
			] })
		}
		[]ah.Value { buildcore.Value(value.map(policy_value(it))) }
		map[string]ah.Value {
			mut fields := map[string]buildcore.Value{}
			for key, item in value { fields[key] = policy_value(item) }
			buildcore.Value(fields)
		}
		json2.Null { buildcore.Value(json2.Null{}) }
		else { buildcore.Value(buildcore.Number{ raw: ah.encode(value), integer: true }) }
	}
}

pub struct PrimitiveReplacement {
pub:
	handled bool
	value   json2.Any
}

pub struct VulkanContext {
pub:
	tools gamehost.Tools
pub mut:
	primitive_hook    fn (map[string]json2.Any, voidptr) !PrimitiveReplacement = unsafe { nil }
	primitive_context voidptr
	driver_hook       fn (bool, string, string, voidptr) ![]string = unsafe { nil }
	driver_context    voidptr
mut:
	temporaries    map[int]string
	next_temporary int
}

fn runtime_vulkan_callback(row map[string]json2.Any, pointer voidptr) !json2.Any {
	mut context := unsafe { &VulkanContext(pointer) }
	return context.callback(row) or { return error('Vulkan ' + text(row, 'kind') + '/' + text(row, 'name') + ': ' + err.msg()) }
}

pub fn (mut context VulkanContext) close() {
	for _, directory in context.temporaries { gamehost.remove(directory) or {} }
	context.temporaries.clear()
}

pub fn (mut context VulkanContext) call(operation string, arguments map[string]json2.Any) !json2.Any {
	if operation == 'policy_sources' {
		return json2.Any(native_sources(context.tools.root)!.map(tagged_path(it)))
	}
	previous, pointer := vulkanbuild.set_native_request(runtime_vulkan_callback, context)
	defer { vulkanbuild.set_native_request(previous, pointer) }
	return vulkanbuild.dispatch({
		'operation':   json2.Any(operation)
		'repo_hex':    json2.Any(context.tools.root.bytes().hex())
		'python_hex':  json2.Any('')
		'builder_hex': json2.Any((context.tools.root + '/tests/native-runtime-tools/main.v').bytes().hex())
		'platform':    json2.Any(if os.user_os() == 'macos' { 'darwin' } else { os.user_os() })
		'pid':         json2.Any(os.getpid().str())
		'arguments':   json2.Any(arguments)
	})
}

fn (mut context VulkanContext) callback(row map[string]json2.Any) !json2.Any {
	if context.primitive_hook != unsafe { nil } {
		replacement := context.primitive_hook(row, context.primitive_context)!
		if replacement.handled { return replacement.value }
	}
	kind := text(row, 'kind')
	arguments := field(row, 'arguments').as_array()
	return match kind {
		'global' {
			name := text(row, 'name')
			if name == '_native' {
				json2.Any({
					'native_function': json2.Any('policy_sources')
				})
			} else if name == 'Path' {
				json2.Any({
					'native_function': json2.Any('Path')
				})
			} else {
				value := vulkanbuild.exported_constant(context.tools.root, name)!
				if name in ['GLIBC_PIN', 'MMAP32_SOURCE', 'EARLY_CLIENT_SOURCE', 'MESA_BUILDER',
					'VENUS_BUILDER'] {
					tagged_path(value.str())
				} else {
					value
				}
			}
		}
		'resolver' { json2.Any({
			'module': json2.Any('debian')
		}) }
		'keys' {
			target := field(row, 'target')
			if target is []json2.Any {
				target
			} else {
				json2.Any(target.as_map().keys().map(json2.Any(it)))
			}
		}
		'equal' {
			json2.Any(buildcore.values_equal(policy_value(any_value(arguments[0])!), policy_value(any_value(arguments[1])!)))
		}
		'symlink' {
			os.symlink(arguments[0].str(), value_path(arguments[1])!)!
			json2.Any(json2.Null{})
		}
		'copy2' {
			hosttest.module_copy_file_preserving_stat(value_path(arguments[0])!, value_path(arguments[1])!)!
			json2.Any(json2.Null{})
		}
		'json_loads' { json2.decode[json2.Any](hex.decode(text(row, 'data_hex'))!.bytestr())! }
		'json_dumps' {
			options := field(row, 'keywords').as_map()
			json2.Any(native_dumps(arguments[0], field(options, 'sort_keys').bool(), 'indent' in options)!)
		}
		'run', 'check_output' {
			argv := arguments[0].as_array().map(it.str())
			result := context.tools.command(argv, kind == 'check_output')!
			if result.status != 0 {
				return error('command failed (${result.status}): ' + argv.str())
			}
			if kind == 'check_output' {
				json2.Any(result.stdout)
			} else {
				json2.Any({
					'returncode': json2.Any(0)
				})
			}
		}
		'temporary' {
			base := value_path(field(field(row, 'keywords').as_map(), 'dir'))!
			directory := private_directory(base)!
			identity := context.next_temporary
			context.next_temporary++
			context.temporaries[identity] = directory
			json2.Any({
				'owner':   json2.Any(identity)
				'entered': json2.Any(directory)
			})
		}
		'retire' {
			identity := arguments[0].int()
			directory := context.temporaries[identity] or { return error('temporary owner already retired') }
			context.temporaries.delete(identity)
			gamehost.remove(directory)!
			json2.Any(false)
		}
		'call' {
			function := text(field(row, 'target').as_map(), 'native_function')
			if function == 'Path' {
				tagged_path(arguments[0].str())
			} else if function == 'policy_sources' {
				json2.Any(native_sources(context.tools.root)!.map(tagged_path(it)))
			} else {
				return error('unknown native Vulkan function: ' + function)
			}
		}
		'print' {
			for argument in arguments {
				println(if 'path_hex' in argument.as_map() {
					value_path(argument)!
				} else {
					argument.str()
				})
			}
			json2.Any(json2.Null{})
		}
		'public' { context.public(text(row, 'name'), arguments)! }
		'method' { context.method(field(row, 'target'), text(row, 'name'), arguments)! }
		'attribute' { context.attribute(field(row, 'target'), text(row, 'name'))! }
		else { return error('unknown native Vulkan primitive: ' + kind) }
	}
}

fn native_sources(root string) ![]string {
	mut paths := []string{}
	for directory in ['tests/native-runtime-tools', 'tests/native-game-tools/gamehost',
		'build-support/dota2/vulkanbuild', 'build-support/dota2/buildcore',
		'build-support/dota2/qemubuild', 'tools/sourcecommand', 'build-support/cachecli',
		'tests/linuxkpi/hosttest'] {
		for path in gamehost.files(root + '/' + directory)! {
			if !os.is_link(path) && os.is_file(path) && (path.ends_with('.v') || path.ends_with('.h')) {
				paths << path
			}
		}
	}
	paths << [root + '/build-support/find-v.sh', root + '/build-support/run-v-tool.sh']
	paths.sort()
	return paths
}

pub fn native_dumps(value json2.Any, sorted bool, pretty bool) !string {
	return native_dump_at(unwrap_filesystem(value)!, sorted, pretty, 0)
}

fn unwrap_filesystem(value json2.Any) !json2.Any {
	if value is []json2.Any {
		mut result := []json2.Any{}
		for item in value { result << unwrap_filesystem(item)! }
		return json2.Any(result)
	}
	if value is map[string]json2.Any {
		if 'filesystem_text' in value {
			return json2.Any(filesystem_text(hex.decode(value['filesystem_text']!.str())!.bytestr()))
		}
		if 'filesystem_map' in value {
			mut result := map[string]json2.Any{}
			for item in value['filesystem_map']!.as_array() {
				pair := item.as_array()
				result[filesystem_text(hex.decode(pair[0].str())!.bytestr())] = unwrap_filesystem(pair[1])!
			}
			return json2.Any(result)
		}
		mut result := map[string]json2.Any{}
		for key, item in value { result[key] = unwrap_filesystem(item)! }
		return json2.Any(result)
	}
	return value
}

fn package_json(package Package) json2.Any {
	return json2.Any({
		'fields': json2.Any({
			'name':         json2.Any(package.name)
			'version':      json2.Any(package.version)
			'architecture': json2.Any(package.architecture)
			'filename':     json2.Any(package.filename)
			'sha256':       json2.Any(package.sha256)
			'size':         json2.Any(package.size)
			'dependencies': json2.Any(package.dependencies.map(json2.Any(it.map(json2.Any(it)))))
			'provides':     json2.Any(package.provides.map(json2.Any(it)))
		})
	})
}

fn package_from(value json2.Any) Package {
	fields := field(value.as_map(), 'fields').as_map()
	return Package{ name: text(fields, 'name'), version: text(fields, 'version'), architecture: text(fields, 'architecture'), filename: text(fields, 'filename'), sha256: text(fields, 'sha256'), size: field(fields, 'size').i64(), dependencies: field(fields, 'dependencies').as_array().map(it.as_array().map(it.str())), provides: field(fields, 'provides').as_array().map(it.str()) }
}

fn (mut context VulkanContext) method(target json2.Any, name string, arguments []json2.Any) !json2.Any {
	descriptor := target.as_map()
	if 'path_hex' in descriptor {
		path := value_path(target)!
		if name == 'relative_to' {
			base := value_path(arguments[0])!.trim_right('/')
			if !path.starts_with(base + '/') { return error('path outside base') }
			return tagged_path(path[base.len + 1..])
		}
	}
	module_name := text(descriptor, 'module')
	if module_name == 'debian' {
		return match name {
			'Package' {
				package_json(Package{ name: arguments[0].str(), version: arguments[1].str(), architecture: arguments[2].str(), filename: arguments[3].str(), sha256: arguments[4].str(), size: arguments[5].i64() })
			}
			'parse_index' {
				json2.Any(parse_packages(os.read_file(value_path(arguments[0])!)!)!.map(package_json(it)))
			}
			'resolve' {
				packages := arguments[0].as_array().map(package_from(it))
				roots := arguments[1].as_array().map(it.str())
				ignored := field(arguments[2].as_map(), 'set').as_array().map(it.str())
				json2.Any(resolve(packages, roots, ignored)!.map(package_json(it)))
			}
			'download' {
				tagged_path(download_package(context.tools, arguments[0].str(), package_from(arguments[1]), value_path(arguments[2])!)!)
			}
			'extract_deb' {
				extract_deb(value_path(arguments[0])!, value_path(arguments[1])!)!
				json2.Any(json2.Null{})
			}
			else { return error('unknown native Debian method: ' + name) }
		}
	}
	if module_name == 'mesa' && name == 'load_inputs' {
		return json2.Any(load_mesa_inputs(context.tools.root)!)
	}
	return error('unknown native builder method: ' + module_name + '.' + name)
}

fn (context &VulkanContext) attribute(target json2.Any, name string) !json2.Any {
	module_name := text(target.as_map(), 'module')
	if module_name == 'mesa' && name == 'SUPPORT' {
		return tagged_path(context.tools.root + '/build-support/dota2/mesa')
	}
	if module_name == 'venus' {
		return match name {
			'VERSION' { json2.Any('25.0.5') }
			'SOURCE_SHA256' {
				json2.Any('c0d245dea0aa4b49f74b3d474b16542e4a8799791cd33d676c69f650ad4378d0')
			}
			'PATCHES' { json2.Any(venus_patches(context.tools.root)!.map(tagged_path(it))) }
			else { return error('unknown Venus attribute: ' + name) }
		}
	}
	return error('unknown native builder attribute: ' + module_name + '.' + name)
}

fn (mut context VulkanContext) public(name string, arguments []json2.Any) !json2.Any {
	return match name {
		'file_sha256' { json2.Any(gamehost.digest(value_path(arguments[0])!)!) }
		'clone_tree' {
			vulkanbuild.clone_tree(value_path(arguments[0])!, value_path(arguments[1])!, if os.user_os() == 'macos' {
				'darwin'
			} else {
				os.user_os()
			})!
			json2.Any(json2.Null{})
		}
		'compatibility_inputs' {
			vulkanbuild.compatibility_inputs(context.tools.root, arguments[0].str(), arguments[1].str(), if arguments.len > 2 {
				arguments[2]
			} else {
				json2.Any([]json2.Any{})
			})!
		}
		'early_client_inputs' {
			vulkanbuild.compatibility_inputs(context.tools.root, 'earlycore', 'early-client-abi.h', json2.Any([]json2.Any{}))!
		}
		'mmap32_inputs' {
			vulkanbuild.compatibility_inputs(context.tools.root, 'mmapcore', 'mmap32-abi.h', json2.Any([tagged_path(context.tools.root + '/build-support/dota2/mmap32.exports')]))!
		}
		'package_files' { vulkanbuild.package_files(value_path(arguments[0])!)! }
		'load_mesa_builder' { json2.Any({
			'module': json2.Any('mesa')
		}) }
		'load_venus_builder' { json2.Any({
			'module': json2.Any('venus')
		}) }
		'load_glibc_pin' { json2.Any(load_glibc_pin(context.tools.root)!) }
		'lavapipe_inputs' { vulkanbuild.lavapipe_inputs()! }
		'venus_inputs' { vulkanbuild.venus_inputs()! }
		'glibc_package_valid' {
			json2.Any(glibc_valid(value_path(arguments[0])!, arguments[1], context.callback({
				'kind': json2.Any('global')
				'name': json2.Any('GLIBC_ALIAS_POLICY')
			})!.str())!)
		}
		'lavapipe_valid' { json2.Any(driver_valid(value_path(arguments[0])!, arguments[1], false)) }
		'venus_valid' { json2.Any(driver_valid(value_path(arguments[0])!, arguments[1], true)) }
		'build_lavapipe', 'build_venus' {
			venus := name == 'build_venus'
			base := value_path(arguments[0])!
			work := value_path(arguments[1])!
			outputs := if context.driver_hook != unsafe { nil } {
				context.driver_hook(venus, base, work, context.driver_context)!
			} else {
				build_driver(context.tools, venus, base, work, runtime.nr_cpus(), false)!
			}
			if venus { json2.Any(outputs.map(tagged_path(it))) } else { tagged_path(outputs[0]) }
		}
		'stage_lavapipe' {
			vulkanbuild.stage_lavapipe(arguments[0].as_array(), value_path(arguments[1])!, value_path(arguments[2])!, arguments[3].as_map())!
			json2.Any(json2.Null{})
		}
		'stage_venus' {
			vulkanbuild.stage_venus(value_path(arguments[0])!, value_path(arguments[1])!, arguments[2].str(), arguments[3].as_map())!
			json2.Any(json2.Null{})
		}
		'stage_glibc_package' {
			vulkanbuild.stage_glibc_package(arguments[0], arguments[1].as_map(), value_path(arguments[2])!, value_path(arguments[3])!)!
			json2.Any(json2.Null{})
		}
		'build_mmap32', 'build_early_client' {
			vulkanbuild.build_compat(context.tools.root, '', value_path(arguments[0])!, value_path(arguments[1])!, name == 'build_early_client')!
			json2.Any(json2.Null{})
		}
		else { return error('unknown native Vulkan API: ' + name) }
	}
}
