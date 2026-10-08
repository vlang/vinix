// SPDX-License-Identifier: GPL-2.0-or-later
module auditfixture
import hosttest
import json2

struct Context {
 directory string
 root string
 source string
 archive string
 here string
 sha256 string
 python string
 overflow bool
}
struct Observation {
 commands []json2.Any
 generation []string
 bounds []json2.Any
 compiler []json2.Any
 generated []string
}
fn setup(directory string, python string) !Context {
 root := directory + '/linux'
 mkdir(root)!
 metadata := primitive('metadata', {})!.as_map()
 upstream := decoded(metadata['upstream']!)!
 for name in ['include', 'arch'] { link(upstream + '/' + name, root + '/' + name)! }
 source := root + '/drivers/gpu/drm/i915/adapter_caller.c'
 write(source, caller)!
 return Context{directory, root, source, decoded(metadata['archive']!)!, decoded(metadata['here']!)!, metadata['sha256']!.str(), python, metadata['overflow']!.bool()}
}
fn invoke(context Context, name string, compiler string, here string) !(map[string]json2.Any, Observation) {
 result := primitive_observed('invoke', {'root': path(context.root), 'source': path(context.source), 'archive': path(context.archive), 'compiler': path(compiler), 'output': path(context.directory + '/' + name + '.json'), 'here': path(here)}, fn [context] (row map[string]json2.Any) ! {
  argv := row['argv']!.as_array().map(it.str())
  if context.source !in argv { return }
  include := argv[argv.index('-I') + 1]
  snapshot := row['snapshots']!.as_map()[include]!.as_map()
  truth(snapshot['vinix/spinlock_adapters.h']!.bool())!
  truth(snapshot['vinix/atomic_exchange.h']!.bool())!
  if context.overflow { truth(snapshot['vinix/integer_policy.h']!.bool())! }
  for header_name in ['generated/bounds.h', 'generated/bounds.h.d', 'generated/bounds.h.json'] { truth(snapshot[header_name]!.bool())! }
  falsehood(argv.any('obj' in it.split('/')))!
 })!.as_map()
 mut generation := []string{}; mut bounds := []json2.Any{}; mut compilers := []json2.Any{}; mut generated := []string{}
 commands := result['commands']!.as_array()
 for item in commands {
  row := item.as_map(); argv := row['argv']!.as_array().map(it.str())
  if argv.len > 1 && argv[1].all_after_last('/') == 'generate-abi.py' { generation << argv.last().all_before_last('/').all_before_last('/') }
  if '-S' in argv { bounds << row['argv']! }
  if context.source in argv {
   compilers << row['argv']!
   index := argv.index('-I')
   include := argv[index + 1]
   generated << include
  }
 }
 return result, Observation{commands, generation, bounds, compilers, generated}
}
fn failure_result(result map[string]json2.Any, observed Observation, bounds int, generations int) ! {
 message := json2.Any(result['stdout']!.str() + result['stderr']!.str())
 equal(result['status']!, json2.Any(2), message)!
 contain('JSONDecodeError', result['stderr']!.str())!
 falsehood(result['output_exists']!.bool())!
 equal(json2.Any(observed.compiler), json2.Any([]json2.Any{}), json2.Null{})!
 equal(json2.Any(hosttest.strings(observed.generated)), json2.Any([]json2.Any{}), json2.Null{})!
 equal(json2.Any(observed.bounds.len), json2.Any(bounds), json2.Null{})!
 equal(json2.Any(observed.generation.len), json2.Any(generations), json2.Null{})!
 falsehood(exists(observed.generation[0].all_before_last('/'))!)!
}
fn run(context Context, name string) ! {
 if name == 'test_each_invocation_generates_and_removes_its_own_headers' {
  mut compilers := 0; mut bounds := 0; mut generated := []string{}
  for invocation in ['first', 'second'] {
   result, observed := invoke(context, invocation, 'clang', context.here)!
   equal(result['status']!, json2.Any(0), json2.Any(result['stdout']!.str() + result['stderr']!.str()))!
   report := result['report']!.as_map()
   counts := [report['compiled']!, report['total']!]
   equal_tuple(counts, [json2.Any(1), json2.Any(1)], result['report']!)!
   profile := report['bounds']!.as_map()
   equal(profile['configuration']!.as_map()['CONFIG_MMU']!, json2.Any('1'), json2.Null{})!
   equal(profile['archive_sha256']!, json2.Any(context.sha256), json2.Null{})!
   compilers += observed.compiler.len; bounds += observed.bounds.len; generated << observed.generated
  }
  equal(json2.Any(compilers), json2.Any(2), json2.Null{})!
  equal(json2.Any(bounds), json2.Any(2), json2.Null{})!
  mut unique := map[string]bool{}; for item in generated { unique[item] = true }
  equal(json2.Any(unique.len), json2.Any(2), json2.Null{})!
  for directory in generated { falsehood(exists(directory.all_before_last('/'))!)! }
 } else if name == 'test_bounds_compiler_failure_stops_before_driver_compilation' {
  compiler := context.directory + '/reject-bounds.py'
  write(compiler, '#!' + context.python + '\nimport os, sys\nif \'-S\' in sys.argv:\n    print(\'injected bounds compiler failure\', file=sys.stderr)\n    sys.exit(1)\nos.execvp(\'clang\', [\'clang\'] + sys.argv[1:])\n')!
  primitive('chmod', {'path': path(compiler), 'mode': json2.Any(0o755)})!
  result, observed := invoke(context, 'bounds-failure', compiler, context.here)!
  equal(result['status']!, json2.Any(2), json2.Any(result['stdout']!.str() + result['stderr']!.str()))!
  contain('injected bounds compiler failure', result['stderr']!.str())!
  falsehood(result['output_exists']!.bool())!
  equal(json2.Any(observed.compiler), json2.Any([]json2.Any{}), json2.Null{})!
  equal(json2.Any(observed.bounds.len), json2.Any(1), json2.Null{})!
  for directory in observed.generation { falsehood(exists(directory.all_before_last('/'))!)! }
 } else if name == 'test_invalid_metadata_stops_before_the_compiler' {
  invalid := context.directory + '/invalid-metadata'
  mkdir(invalid + '/abi')!
  link(context.here + '/generate-abi.py', invalid + '/generate-abi.py')!
  write(invalid + '/abi/spinlock.json', '{ malformed metadata')!
  result, observed := invoke(context, 'failure', 'clang', invalid)!
  failure_result(result, observed, 0, 1)!
 } else if name == 'test_invalid_optional_integer_metadata_stops_before_the_compiler' {
  if !context.overflow { primitive('skip', {'reason': json2.Any('integer-policy metadata is absent in this source snapshot')})! }
  invalid := context.directory + '/invalid-integer-metadata'
  mkdir(invalid + '/abi')!
  link(context.here + '/generate-abi.py', invalid + '/generate-abi.py')!
  for schema in ['spinlock.json', 'atomic-exchange.json'] { link(context.here + '/abi/' + schema, invalid + '/abi/' + schema)! }
  write(invalid + '/abi/overflow.json', '{ malformed metadata')!
  result, observed := invoke(context, 'integer-failure', 'clang', invalid)!
  failure_result(result, observed, 0, 3)!
 } else { return error('Unknown audit fixture: ' + name) }
}
pub fn fixture(name string, python string) ! {
 directory := decoded(primitive('temporary', {'prefix': json2.Any('vinix-audit-generation-test-')})!)!
 context := setup(directory, python) or { failure := err; primitive('retire', {'path': path(directory)})!; return failure }
 run(context, name) or { failure := err; primitive('retire', {'path': path(directory)})!; return failure }
 primitive('retire', {'path': path(directory)})!
}
