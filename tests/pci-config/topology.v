// SPDX-License-Identifier: GPL-2.0-or-later
// Independent host observer for the unchanged production PCI topology core.
module main

import os
import time
import crypto.sha256
import json2
import encoding.utf8

#include <signal.h>
#include <stdlib.h>

fn C.kill(i32, i32) i32
fn C.mkdtemp(&char) &char

const scope = 'Execute native PCI topology/capability V against explicit host observers. Production algorithms remain unchanged; only allocation, fixed-array indexing and synchronous config transport are modeled. This validates private snapshots and quiescent destruction, not hardware discovery or Linux PCI registration.'

struct Outcome {
	stdout string
	stderr string
	code   int
}

fn capture(argv []string, log string, env map[string]string) !Outcome {
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..])
	child.set_environment(env)
	child.set_redirect_stdio()
	defer { child.close() }
	child.run()
	if child.pid <= 0 { return error('Cannot start command: ' + argv[0]) }
	start := time.sys_mono_now()
	mut output := ''
	mut diagnostic := ''
	mut expired := false
	for {
		output += child.stdout_read()
		diagnostic += child.stderr_read()
		if !child.is_alive() { break }
		if time.sys_mono_now() - start >= u64(120) * u64(time.second) {
			unsafe { C.kill(i32(child.pid), 9) }
			child.wait()
			expired = true
			break
		}
		time.sleep(time.millisecond)
	}
	output += child.stdout_slurp()
	diagnostic += child.stderr_slurp()
	os.write_file(log, json2.encode(argv) + '\n' + output + diagnostic)!
	if expired { return error('Command timed out after 120 seconds; see ' + log) }
	if child.code != 0 { return error('Command failed; see ' + log) }
	return Outcome{output, diagnostic, child.code}
}

fn sha(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn hashes(paths []string) !map[string]string {
	mut result := map[string]string{}
	for path in paths { result[path] = sha(path)! }
	return result
}

fn work_dir(keep string) !string {
	if keep != '' {
		path := os.abs_path(keep)
		if os.exists(path) { return error('Output directory already exists: ' + path) }
		os.mkdir_all(os.dir(path))!
		os.mkdir(path)!
		return os.real_path(path)
	}
	mut pattern := (os.join_path(os.temp_dir(), 'vinix-pci-topology-XXXXXX') + '\x00').bytes()
	unsafe {
		result := C.mkdtemp(&char(pattern.data))
		if result == nil { return error('Cannot create private temporary directory') }
		return cstring_to_vstring(result)
	}
}

// Preserve the original top-level C-body pattern, including its one-line
// signature and column-zero closing brace. Every selected body is retained.
fn bodies(text string) []string {
	mut result := []string{}
	mut offset := 0
	for offset < text.len {
		end := offset + (text[offset..].index('\n') or { text.len - offset })
		line := text[offset..end]
		if opening := line.index('(') {
			if opening > 0 && !line[..opening].contains(';') && line.ends_with(') {') && end < text.len {
				if stop := text[end..].index('\n}') {
					result << text[offset..end + stop + 2]
					closing := end + stop + 2
					offset = closing + (text[closing..].index('\n') or { text.len - closing }) + 1
					continue
				}
			}
		}
		offset = end + 1
	}
	return result
}

fn named(body string, name string) bool {
	mut start := 0
	for start < body.len {
		position := start + (body[start..].index(name + '(') or { return false })
		if position == 0 { return true }
		preceding := body[..position].runes().last()
		if preceding != `_` && !utf8.is_letter(preceding) && !utf8.is_number(preceding) {
			return true
		}
		start = position + 1
	}
	return false
}

fn callback_tuple(raw string) bool {
	marker := 'struct multi_return_u32_i64 {'
	mut position := 0
	for position < raw.len {
		start := position + (raw[position..].index(marker) or { return false })
		tail := raw[start + marker.len..]
		mut tuple := tail[..(tail.index('};') or { return false })]
		mut valid := true
		for field in ['u32 arg0;', 'i64 arg1;'] {
			tuple = tuple.trim_left(' \t\r\n\v\f')
			if !tuple.starts_with(field) {
				valid = false
				break
			}
			tuple = tuple[field.len..]
		}
		if valid && tuple.trim_space() == '' { return true }
		position = start + marker.len
	}
	return false
}

fn compiler_metadata(raw string) !(string, map[string]json2.Any) {
	mut compiled := raw
	mut removed := []string{}
	for name in ['Topology', 'TopologyBus', 'TopologyFunction', 'CapabilityInfo'] {
		line := 'typedef struct pci__' + name + ' pci__' + name + ';\n'
		mut indices := []int{}
		mut start := 0
		for start < compiled.len {
			index := start + (compiled[start..].index(line) or { break })
			indices << index
			start = index + line.len
		}
		if indices.len < 1 || indices.len > 2 {
			return error('Unexpected generated forward declaration: ' + name)
		}
		if indices.len == 2 {
			index := indices[1]
			compiled = compiled[..index] + compiled[index + line.len..]
			removed << line.trim_space()
		}
	}
	before := bodies(raw)
	if before != bodies(compiled) {
		return error('Private typedef metadata changed a generated body')
	}
	selected := before.filter(it.all_before('\n').contains('pci__') || it.all_before('\n').contains('memory__') || it.all_before('\n').contains('topology_test_'))
	for name in ['pci__topology_build', 'pci__topology_destroy', 'pci__capabilities_read',
		'pci__checked_config_read'] {
		if !selected.any(named(it, name)) {
			return error('Production code missing from actual generated bodies')
		}
	}
	if !callback_tuple(raw) {
		return error('Native V callback tuple did not retain its actual u32/i64 ABI')
	}
	if raw.contains('encoding__binary__') || raw.contains('io__Reader') {
		return error('Private observer stage unexpectedly acquired unrelated callback modules')
	}
	return compiled, {
		'removed_second_identical_forward_typedefs': json2.Any(removed.map(json2.Any(it)))
		'unchanged_all_body_count':                  before.len
		'production_observer_wrapper_body_count':    selected.len
		'body_sha256':                               selected.map(json2.Any(sha256.sum(it.bytes()).hex()))
		'native_callback_tuple':                     'actual generated multi_return_u32_i64'
		'scope':                                     'Private identical compiler forward declarations only; raw C and all bodies preserved.'
	}
}

fn run(keep string) ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	production := ['kernel/pci/topology.v', 'kernel/pci/capabilities.v', 'kernel/pci/config_core.v'].map(os.join_path(root, it))
	contract := os.join_path(root, 'kernel/c/pci_config.h')
	mut sources := production.clone()
	sources << [contract, @FILE]
	initial := hashes(sources)!
	work := work_dir(keep)!
	defer { if keep == '' { os.rmdir_all(work) or {} } }
	stage := os.join_path(work, 'stage')
	os.mkdir_all(os.join_path(stage, 'pci'))!
	os.mkdir(os.join_path(stage, 'memory'))!
	os.write_file(os.join_path(stage, 'v.mod'), "Module { name: 'pci_topology_probe' }\n")!
	os.write_file(os.join_path(stage, 'entry.v'), 'module main\nimport pci as _\nfn main() {}\n')!
	for source in production { os.cp(source, os.join_path(stage, 'pci', os.file_name(source)))! }
	os.write_file(os.join_path(stage, 'pci/observer.v'), wrappers)!
	os.write_file(os.join_path(stage, 'memory/observer.v'), memory_observer)!
	os.write_file(os.join_path(work, 'topology_model.h'), model_header)!
	os.cp(contract, os.join_path(work, 'pci_config.h'))!
	requested := os.getenv_opt('V') or { 'v' }
	v := os.real_path(os.find_abs_path_of_executable(requested) or { requested })
	v_hash := sha(v)!
	arch := $if arm64 { 'arm64' } $else { 'amd64' }
	generated := os.join_path(work, 'topology.c')
	argv := [v, '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch, '-target-libc-headers',
		'-gc', 'none', '-manualfree', '-o', generated, stage]
	mut environment := os.environ()
	environment['VCACHE'] = os.join_path(work, 'vcache')
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	capture(argv, os.join_path(work, 'generation.log'), environment)!
	compiled, metadata := compiler_metadata(os.read_file(generated)!)!
	os.write_file(os.join_path(work, 'topology-compile.c'), compiled)!
	os.write_file(os.join_path(work, 'test.c'), c_test)!
	cc := os.getenv_opt('CC') or { 'clang' }
	flags := ['-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing',
		'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-pthread',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I', work]
	mut outcomes := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		object := os.join_path(work, standard + '-core.o')
		mut compile_argv := [cc, '-std=' + standard]
		compile_argv << flags
		compile_argv << [
			'-Dmain=topology_unused_main',
			'-Dmalloc=topology_unexpected_malloc',
			'-Dcalloc=topology_unexpected_calloc',
			'-Drealloc=topology_unexpected_realloc',
			'-Dfree=topology_unexpected_free',
			'-c',
			os.join_path(work, 'topology-compile.c'),
			'-o',
			object,
		]
		capture(compile_argv, os.join_path(work, standard + '-compile.log'), os.environ())!
		executable := os.join_path(work, standard + '-runtime')
		mut link_argv := [cc, '-std=' + standard]
		link_argv << flags
		link_argv << [os.join_path(work, 'test.c'), object, '-o', executable]
		capture(link_argv, os.join_path(work, standard + '-link.log'), os.environ())!
		mut env := os.environ()
		env['UBSAN_OPTIONS'] = 'halt_on_error=1'
		env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		result := capture([executable], os.join_path(work, standard + '-run.log'), env)!
		if result.stderr != '' {
			return error('Unexpected sanitizer/runtime diagnostic: ' + result.stderr)
		}
		println(standard + ': ' + result.stdout.trim_space())
		outcomes << json2.Any({
			'standard':      json2.Any(standard)
			'compile_argv':  compile_argv.map(json2.Any(it))
			'link_argv':     link_argv.map(json2.Any(it))
			'object_sha256': sha(object)!
			'output':        result.stdout.trim_space()
		})
	}
	if hashes(sources)! != initial || sha(v)! != v_hash {
		return error('Production/test/compiler changed during private validation')
	}
	os.write_file(os.join_path(work, 'result.json'), json2.encode(map[string]json2.Any{
		'scope':              json2.Any(scope)
		'source_sha256':      json2.Any(hash_json(initial))
		'V_sha256':           v_hash
		'generation_argv':    argv.map(json2.Any(it))
		'generated_c_sha256': sha(generated)!
		'compiled_c_sha256':  sha(os.join_path(work, 'topology-compile.c'))!
		'compiler_metadata':  metadata
		'host_results':       outcomes
		'observer_contract':  'Only memory allocation, checked fixed-array indexing and synchronous native transport are modeled. Actual topology, capability and config V are unchanged. All eight functions are scanned; no platform root inference. Destruction occurs after private reader quiescence. Host stage does not establish cross-module kernel compiler closure or actual hardware.'
	},
		prettify:      true
		indent_string: '  '
	) + '\n')!
}

fn main() {
	keep := parse_keep(os.args[1..]) or {
		eprintln(err.msg())
		exit(if err.code() == 1 { 1 } else { 2 })
	}
	run(keep) or {
		eprintln(err.msg())
		exit(1)
	}
}

fn parse_keep(args []string) !string {
	mut keep := ''
	mut unknown := []string{}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--' {
			unknown << args[i..]
			break
		}
		if arg == '-h=' {
			return error_with_code('argument -h/--help: ignored explicit argument', 1)
		}
		name := arg.all_before('=')
		if arg.starts_with('-h') && !arg[1..].bytes().all(it == `h`) {
			return error('argument -h/--help: ignored explicit argument')
		}
		if (arg.starts_with('-h') && arg[1..].bytes().all(it == `h`)) || (name.starts_with('--') && '--help'.starts_with(name)) {
			if arg.contains('=') { return error('argument --help: ignored explicit argument') }
			println('Usage: topology.v [--keep-dir DIRECTORY]\n\n' + scope)
			exit(0)
		}
		if name.starts_with('--') && '--keep-dir'.starts_with(name) {
			mut value := ''
			if arg.contains('=') {
				value = arg.all_after('=')
			} else {
				if i + 1 >= args.len { return error('argument --keep-dir: expected one argument') }
				i++
				value = args[i]
				if value.starts_with('-') && value != '-' && !negative_number(value) {
					return error('argument --keep-dir: expected one argument')
				}
			}
			keep = if value == '' { '.' } else { value }
		} else {
			unknown << arg
		}
		i++
	}
	if unknown.len > 0 { return error('unrecognized arguments: ' + unknown.join(' ')) }
	return keep
}

fn negative_number(value string) bool {
	if value.len <= 1 || value[0] != `-` { return false }
	tail := value[1..]
	return tail.bytes().all(it.is_digit()) || (tail.count('.') == 1 && tail.all_after('.').len > 0 && tail.all_before('.').bytes().all(it.is_digit()) && tail.all_after('.').bytes().all(it.is_digit()))
}

const memory_observer = '
module memory
#include "topology_model.h"
fn C.topology_model_allocate(u64) voidptr
fn C.topology_model_free(voidptr)
pub fn malloc_packed_fallible(size u64) voidptr { return C.topology_model_allocate(size) }
pub fn free(pointer voidptr) { C.topology_model_free(pointer) }
'

const wrappers = '
module pci
#include "topology_model.h"
fn C.topology_model_prepare(u32, u16, u8)
fn model_read(bdf u32, register u16, width u8) (u32, int) {
    C.topology_model_prepare(bdf, register, width)
    mut value := u32(0)
    result := checked_config_read(0, bdf >> 8, (bdf >> 3) & 31, bdf & 7,
        u64(register), u32(width), unsafe { &value })
    return value, int(result)
}
@[export: \'topology_test_build\']
fn test_build(roots &u8, count u32, fail_after u32, null_read bool, status &i64) voidptr {
    callback := if null_read { TopologyRead(unsafe { nil }) } else { TopologyRead(model_read) }
    snapshot, result := topology_build(roots, count, callback, fail_after)
    unsafe { *status = i64(result) }
    return snapshot
}
@[export: \'topology_test_destroy\']
fn test_destroy(snapshot voidptr) { topology_destroy(unsafe { &Topology(snapshot) }) }
@[export: \'topology_test_first\']
fn test_first(snapshot voidptr, kind u32) voidptr {
    owner := unsafe { &Topology(snapshot) }
    if kind == 0 { return owner.first_bus() }
    return owner.first_function()
}
@[export: \'topology_test_next\']
fn test_next(node voidptr, kind u32) voidptr {
    if kind == 0 { return unsafe { &TopologyBus(node) }.next_bus() }
    return unsafe { &TopologyFunction(node) }.next_function()
}
@[export: \'topology_test_count\']
fn test_count(snapshot voidptr, kind u32) u32 {
    owner := unsafe { &Topology(snapshot) }
    if kind == 0 { return owner.bus_count() }
    return owner.function_count()
}
@[export: \'topology_test_field\']
fn test_field(node voidptr, kind u32, field u32) u64 {
    if kind == 0 {
        bus := unsafe { &TopologyBus(node) }
        match field {
            0 { return bus.number }
            1 { return bus.root_number }
            2 { return u64(i64(bus.parent_bridge_bdf)) }
            3 { return bus.subordinate_limit }
            else { return 0 }
        }
    }
    device := unsafe { &TopologyFunction(node) }
    match field {
        0 { return device.bdf }
        1 { return device.identity }
        2 { return device.class_revision }
        3 { return device.header_type }
        4 { return if device.multifunction { u64(1) } else { u64(0) } }
        5 { return device.irq_pin }
        6 { return device.subsystem_identity }
        7 { return if device.has_subsystem { u64(1) } else { u64(0) } }
        8 { return u64(i64(device.parent_bridge_bdf)) }
        9 { return device.bridge_primary }
        10 { return device.bridge_secondary }
        11 { return device.bridge_subordinate }
        else { return 0 }
    }
}
@[export: \'topology_test_parent\']
fn test_parent(node voidptr, kind u32) voidptr {
    if kind == 0 { return unsafe { &TopologyBus(node) }.parent }
    return unsafe { &TopologyFunction(node) }.bus
}
@[export: \'topology_test_size\']
fn test_size(kind u32) u64 {
    if kind == 0 { return sizeof(Topology) }
    if kind == 1 { return sizeof(TopologyBus) }
    return sizeof(TopologyFunction)
}
@[export: \'topology_test_capabilities\']
fn test_capabilities(bdf u32, header u8, null_read bool, result &u16) i64 {
    callback := if null_read { TopologyRead(unsafe { nil }) } else { TopologyRead(model_read) }
    value, status := capabilities_read(bdf, header, callback)
    unsafe {
        result[0] = value.msi_offset
        result[1] = value.msix_offset
        result[2] = value.msix_entries
    }
    return i64(status)
}
'

const model_header = "
#ifndef VINIX_TOPOLOGY_MODEL_H
#define VINIX_TOPOLOGY_MODEL_H
#include <stdbool.h>
#include <stdint.h>
void *topology_model_allocate(uint64_t size);
void topology_model_free(void *pointer);
void topology_model_prepare(uint32_t bdf, uint16_t offset, uint8_t width);
/* -no-builtin omits V's checked fixed-array indexing helper. The observer
 * checks its complete index contract; no production array expression changes. */
int64_t v_fixed_index(int64_t index, int64_t length);
#endif
"

const c_test = '
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sched.h>
#include "pci_config.h"
#include "topology_model.h"

void *topology_test_build(uint8_t *, uint32_t, uint32_t, bool, int64_t *);
void topology_test_destroy(void *);
void *topology_test_first(void *, uint32_t);
void *topology_test_next(void *, uint32_t);
uint32_t topology_test_count(void *, uint32_t);
uint64_t topology_test_field(void *, uint32_t, uint32_t);
void *topology_test_parent(void *, uint32_t);
uint64_t topology_test_size(uint32_t);
int64_t topology_test_capabilities(uint32_t, uint8_t, bool, uint16_t *);

static unsigned assertions;
#define CHECK(c) do { __atomic_add_fetch(&assertions, 1, __ATOMIC_RELAXED); \\
    if (!(c)) { fprintf(stderr, "Topology assertion line %d: %s\\n", __LINE__, #c); abort(); } } while (0)
#define BDF(b,s,f) (((uint32_t)(b) << 8) | ((uint32_t)(s) << 3) | (uint32_t)(f))
struct Image { uint32_t bdf; uint8_t bytes[256]; unsigned transactions[256]; };
struct Allocation { void *pointer; size_t size; };
static struct Image images[300];
static unsigned image_count, reads, writes, preparations, lock_count, unlock_count;
static unsigned fail_read, unavailable_bus = 256, alloc_attempts, fail_alloc;
static struct Allocation allocations[4096];
static size_t live_objects, live_bytes;
static pthread_mutex_t transport = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t allocator = PTHREAD_MUTEX_INITIALIZER;
static __thread bool irq_enabled = true, locked, saved_irq;
static __thread unsigned pins, saved_pins;
static __thread uint32_t prepared_bdf;
static __thread uint16_t prepared_offset;
static __thread uint8_t prepared_width;
static __thread bool transaction_fails;
static bool parsing_capabilities;

int64_t v_fixed_index(int64_t index, int64_t length) {
    CHECK(index >= 0 && index < length);
    return index;
}

void *topology_unexpected_malloc(size_t size) { (void)size; CHECK(false); return NULL; }
void *topology_unexpected_calloc(size_t count, size_t size) { (void)count; return topology_unexpected_malloc(size); }
void *topology_unexpected_realloc(void *pointer, size_t size) { (void)pointer; return topology_unexpected_malloc(size); }
void topology_unexpected_free(void *pointer) { (void)pointer; CHECK(false); }

void *topology_model_allocate(uint64_t size) {
    CHECK(!locked && size > 0 && size <= SIZE_MAX);
    alloc_attempts++;
    if (fail_alloc && alloc_attempts == fail_alloc) return NULL;
    void *pointer = malloc((size_t)size);
    CHECK(pointer != NULL);
    CHECK(pthread_mutex_lock(&allocator) == 0);
    unsigned slot;
    for (slot = 0; slot < 4096 && allocations[slot].pointer; slot++) {}
    CHECK(slot < 4096);
    allocations[slot] = (struct Allocation){pointer, (size_t)size};
    live_objects++; live_bytes += (size_t)size;
    CHECK(pthread_mutex_unlock(&allocator) == 0);
    /* Poisoning catches fields that the production constructor failed to set. */
    memset(pointer, 0xa5, (size_t)size);
    return pointer;
}
void topology_model_free(void *pointer) {
    CHECK(!locked && pointer != NULL);
    CHECK(pthread_mutex_lock(&allocator) == 0);
    unsigned slot;
    for (slot = 0; slot < 4096 && allocations[slot].pointer != pointer; slot++) {}
    CHECK(slot < 4096);
    live_objects--; live_bytes -= allocations[slot].size;
    allocations[slot] = (struct Allocation){0};
    CHECK(pthread_mutex_unlock(&allocator) == 0);
    free(pointer);
}
void topology_model_prepare(uint32_t bdf, uint16_t offset, uint8_t width) {
    CHECK(!locked && bdf <= 0xffff && (width == 1 || width == 2 || width == 4));
    CHECK(offset < 256 && (offset & (width - 1)) == 0);
    if (!parsing_capabilities) {
        CHECK(width == 4);
        CHECK(offset == 0 || offset == 8 || offset == 12 || offset == 0x3c ||
              offset == 0x2c || offset == 0x40 || offset == 0x18);
        /* No BAR sizing/probing: the only BAR-range read is a bridge\'s
         * genuine primary/secondary/subordinate bus-number register. */
        if (offset == 0x18) {
            bool bridge_header = false;
            for (unsigned i=0;i<image_count;i++) if (images[i].bdf == bdf)
                bridge_header = (images[i].bytes[0x0e] & 0x7f) == 1 ||
                                (images[i].bytes[0x0e] & 0x7f) == 2;
            CHECK(bridge_header);
        }
    }
    prepared_bdf = bdf; prepared_offset = offset; prepared_width = width;
    preparations++;
    transaction_fails = fail_read && preparations == fail_read;
}
void vinix_pci_config_lock(void) {
    CHECK(!locked);
    saved_irq = irq_enabled; saved_pins = pins;
    irq_enabled = false; pins++;
    CHECK(pthread_mutex_lock(&transport) == 0);
    locked = true; lock_count++;
}
void vinix_pci_config_unlock(void) {
    CHECK(locked && !irq_enabled && pins == saved_pins + 1);
    locked = false; unlock_count++;
    CHECK(pthread_mutex_unlock(&transport) == 0);
    pins = saved_pins; irq_enabled = saved_irq;
}
uint32_t vinix_pci_config_limit(uint32_t bus) {
    CHECK(locked && !irq_enabled && pins == saved_pins + 1);
    return transaction_fails || bus == unavailable_bus ? 0 : 256;
}
static struct Image *image(uint32_t bdf) {
    for (unsigned i = 0; i < image_count; i++) if (images[i].bdf == bdf) return &images[i];
    return NULL;
}
uint32_t vinix_pci_config_read_raw(uint32_t bus, uint32_t slot, uint32_t function,
        uint32_t offset, uint32_t width) {
    CHECK(locked && !irq_enabled && pins == saved_pins + 1);
    CHECK(BDF(bus,slot,function) == prepared_bdf && offset == prepared_offset && width == prepared_width);
    CHECK(offset + width <= 256 && (offset & (width - 1)) == 0);
    reads++;
    struct Image *record = image(BDF(bus,slot,function));
    if (!record) return UINT32_MAX;
    record->transactions[offset]++;
    uint32_t value = 0;
    for (uint32_t i = 0; i < width; i++) value |= (uint32_t)record->bytes[offset + i] << (8 * i);
    return value;
}
void vinix_pci_config_write_raw(uint32_t bus, uint32_t slot, uint32_t function,
        uint32_t offset, uint32_t width, uint32_t value) {
    (void)bus; (void)slot; (void)function; (void)offset; (void)width; (void)value;
    writes++; CHECK(false);
}
static void put(struct Image *record, unsigned offset, unsigned width, uint32_t value) {
    CHECK(offset + width <= 256);
    for (unsigned i = 0; i < width; i++) record->bytes[offset+i] = (uint8_t)(value >> (8*i));
}
static struct Image *add(unsigned bus, unsigned slot, unsigned function,
        uint32_t identity, uint32_t class_revision, uint8_t header) {
    CHECK(image_count < 300 && image(BDF(bus,slot,function)) == NULL);
    struct Image *record = &images[image_count++];
    memset(record, 0, sizeof(*record)); record->bdf = BDF(bus,slot,function);
    put(record,0,4,identity); put(record,8,4,class_revision); put(record,12,4,(uint32_t)header<<16);
    put(record,0x3c,4,0x1234); put(record,0x2c,4,0x43218086); put(record,0x40,4,0x56781234);
    return record;
}
static struct Image *endpoint(unsigned bus, unsigned slot, unsigned function) {
    return add(bus,slot,function,0x9a498086,0x03000042,0);
}
static struct Image *bridge(unsigned bus, unsigned slot, unsigned function,
        unsigned primary, unsigned secondary, unsigned subordinate, bool cardbus) {
    struct Image *record = add(bus,slot,function,0x12348086,
        cardbus ? 0x06070001 : 0x06040001, cardbus ? 2 : 1);
    put(record,0x18,4,primary | secondary<<8 | subordinate<<16);
    return record;
}
static void reset(void) {
    CHECK(live_objects == 0 && live_bytes == 0 && !locked);
    memset(images,0,sizeof(images)); image_count = 0;
    reads = writes = preparations = lock_count = unlock_count = 0;
    alloc_attempts = fail_alloc = fail_read = 0; unavailable_bus = 256;
    parsing_capabilities = false;
    irq_enabled = true; pins = 0;
}
static void *build(uint8_t *roots, uint32_t count, uint32_t failure, bool no_read,
        int64_t wanted_status) {
    bool before_irq = irq_enabled; unsigned before_pins = pins;
    unsigned before_reads = preparations;
    int64_t status = INT64_C(0x1234567812345678);
    void *snapshot = topology_test_build(roots,count,failure,no_read,&status);
    CHECK(status == wanted_status && irq_enabled == before_irq && pins == before_pins);
    CHECK(lock_count == unlock_count && writes == 0 && !locked);
    if (status != 0) CHECK(snapshot == NULL && live_objects == 0 && live_bytes == 0);
    else {
        CHECK(snapshot != NULL);
        size_t buses = topology_test_count(snapshot,0), functions = topology_test_count(snapshot,1);
        CHECK(live_objects == 1 + buses + functions);
        CHECK(live_bytes == topology_test_size(0) + buses*topology_test_size(1) + functions*topology_test_size(2));
        CHECK(preparations - before_reads >= buses * 256);
    }
    return snapshot;
}
static void destroy(void *snapshot) {
    unsigned before_reads = preparations;
    topology_test_destroy(snapshot);
    CHECK(live_objects == 0 && live_bytes == 0 && preparations == before_reads && writes == 0);
}
static void *bus_find(void *snapshot, unsigned number) {
    void *node = topology_test_first(snapshot,0);
    unsigned traversed = 0;
    while (node) {
        CHECK(++traversed <= topology_test_count(snapshot,0));
        if (topology_test_field(node,0,0) == number) return node;
        node = topology_test_next(node,0);
    }
    return NULL;
}
static void *function_find(void *snapshot, uint32_t bdf) {
    void *node = topology_test_first(snapshot,1);
    unsigned traversed = 0;
    while (node) {
        CHECK(++traversed <= topology_test_count(snapshot,1));
        if (topology_test_field(node,1,0) == bdf) return node;
        node = topology_test_next(node,1);
    }
    return NULL;
}
static void relationships(void) {
    reset(); uint8_t roots[] = {0, 200};
    endpoint(0,2,7); /* Function zero absent: existing all-eight scan must find seven. */
    add(0,4,1,0x77778086,0x020000ab,0); /* Non-multifunction nonzero function. */
    add(0,4,0,0x66668086,0x020000cd,0x80);
    bridge(0,1,0,0,1,20,false);
    bridge(1,3,0,1,2,10,true);
    endpoint(2,31,7); endpoint(200,0,0);
    bridge(0,6,0,99,0,0,false); /* Unconfigured bridge retained without child. */
    void *snapshot = build(roots,2,0,false,0);
    CHECK(topology_test_count(snapshot,0) == 4 && topology_test_count(snapshot,1) == 8);
    CHECK(alloc_attempts == 13);
    unsigned before_reads = preparations;
    roots[0] = 99; roots[1] = 98; /* No retained caller storage. */
    void *root0 = bus_find(snapshot,0), *root200 = bus_find(snapshot,200);
    void *bus1 = bus_find(snapshot,1), *bus2 = bus_find(snapshot,2);
    CHECK(root0 && root200 && bus1 && bus2 && !bus_find(snapshot,99));
    CHECK(!topology_test_parent(root0,0) && !topology_test_parent(root200,0));
    CHECK(topology_test_field(root0,0,2) == UINT64_MAX && topology_test_field(root0,0,3) == 255);
    CHECK(topology_test_parent(bus1,0) == root0 && topology_test_parent(bus2,0) == bus1);
    CHECK(topology_test_field(bus1,0,2) == BDF(0,1,0) && topology_test_field(bus1,0,3) == 20);
    CHECK(topology_test_field(bus2,0,2) == BDF(1,3,0) && topology_test_field(bus2,0,3) == 10);
    CHECK(topology_test_field(bus2,0,1) == 0 && topology_test_field(root200,0,1) == 200);
    void *device = function_find(snapshot,BDF(2,31,7));
    CHECK(device && topology_test_parent(device,1) == bus2);
    CHECK(topology_test_field(device,1,1) == 0x9a498086 && topology_test_field(device,1,2) == 0x03000042);
    CHECK(topology_test_field(device,1,3) == 0 && topology_test_field(device,1,4) == 0);
    CHECK(topology_test_field(device,1,5) == 0x12 && topology_test_field(device,1,6) == 0x43218086);
    CHECK(topology_test_field(device,1,7) == 1 && topology_test_field(device,1,8) == BDF(1,3,0));
    device = function_find(snapshot,BDF(0,1,0));
    CHECK(device && topology_test_field(device,1,3) == 1 && topology_test_field(device,1,7) == 0);
    CHECK(topology_test_field(device,1,6) == 0 && topology_test_field(device,1,8) == UINT64_MAX);
    CHECK(topology_test_field(device,1,9) == 0 && topology_test_field(device,1,10) == 1 && topology_test_field(device,1,11) == 20);
    device = function_find(snapshot,BDF(1,3,0));
    CHECK(device && topology_test_field(device,1,3) == 2 && topology_test_field(device,1,6) == 0x56781234);
    CHECK(topology_test_field(function_find(snapshot,BDF(0,4,0)),1,4) == 1);
    CHECK(function_find(snapshot,BDF(0,2,7)) && function_find(snapshot,BDF(0,4,1)));
    CHECK(preparations == before_reads); destroy(snapshot);
}
static void absence_and_limits(void) {
    static const uint32_t absent[] = {0xffffffff, 0x1234ffff, 0, 0xffff0000};
    uint8_t root = 0;
    for (unsigned i=0;i<4;i++) {
        reset(); struct Image *record = add(0,0,0,absent[i],0xffffffff,0xff);
        void *snapshot = build(&root,1,0,false,0);
        CHECK(topology_test_count(snapshot,1) == 0 && alloc_attempts == 2);
        for (unsigned offset=1;offset<256;offset++) CHECK(record->transactions[offset] == 0);
        CHECK(preparations == 256); destroy(snapshot);
    }
    reset(); add(0,0,0,0x12340001,0,0); build(&root,1,0,false,-11); CHECK(preparations == 1);
    reset(); int64_t status;
    CHECK(!topology_test_build(NULL,1,0,false,&status) && status == -22);
    CHECK(!topology_test_build(&root,0,0,false,&status) && status == -22);
    CHECK(!topology_test_build(&root,257,0,false,&status) && status == -22);
    CHECK(!topology_test_build(&root,1,0,true,&status) && status == -22);
    uint8_t duplicate[] = {7,7}; build(duplicate,2,0,false,-40);
    CHECK(alloc_attempts == 0 && preparations == 0);
    CHECK(!topology_test_first(NULL,0) && !topology_test_first(NULL,1));
    CHECK(!topology_test_next(NULL,0) && !topology_test_next(NULL,1));
    CHECK(topology_test_count(NULL,0) == 0 && topology_test_count(NULL,1) == 0);
    topology_test_destroy(NULL);
    reset(); uint8_t roots[256]; for(unsigned i=0;i<256;i++) roots[i]=(uint8_t)i;
    void *snapshot = build(roots,256,0,false,0);
    CHECK(topology_test_count(snapshot,0) == 256 && topology_test_count(snapshot,1) == 0);
    CHECK(preparations == 65536 && alloc_attempts == 257 && bus_find(snapshot,255)); destroy(snapshot);
    reset(); root=255; endpoint(255,31,7); snapshot=build(&root,1,0,false,0);
    CHECK(function_find(snapshot,0xffff)); destroy(snapshot);
}
static void malformed(void) {
    uint8_t root=0;
    static const unsigned windows[][3] = {{1,2,3},{0,2,1},{0,0,2},{0,3,0}};
    for(unsigned i=0;i<4;i++) { reset(); bridge(0,0,0,windows[i][0],windows[i][1],windows[i][2],false); build(&root,1,0,false,-71); }
    reset(); bridge(0,0,0,0,1,10,false); bridge(1,0,0,1,2,11,false); build(&root,1,0,false,-71);
    reset(); bridge(0,0,0,0,1,10,false); bridge(1,0,0,1,1,10,false); build(&root,1,0,false,-40);
    reset(); bridge(0,0,0,0,1,10,false); bridge(1,0,0,1,0,10,false); build(&root,1,0,false,-71);
    reset(); bridge(0,0,0,0,1,10,false); bridge(0,1,0,0,3,9,false); build(&root,1,0,false,-71);
    reset(); bridge(0,0,0,0,1,10,false); bridge(0,1,0,0,1,5,false); build(&root,1,0,false,-40);
    reset(); bridge(0,0,0,0,1,10,false); uint8_t roots[]={0,5}; build(roots,2,0,false,-40);
    static const uint8_t headers[] = {3,0x7f,1,2,0};
    static const uint32_t classes[] = {0x03000000,0x03000000,0x02000000,0x06040000,0x06070000};
    for(unsigned i=0;i<5;i++) { reset(); add(0,0,0,0x12348086,classes[i],headers[i]); build(&root,1,0,false,-71); }
    /* Exhaustively fail each of this successful snapshot\'s real config transactions. */
    reset(); endpoint(0,0,0); void *snapshot=build(&root,1,0,false,0); unsigned count=preparations; destroy(snapshot);
    for(unsigned i=1;i<=count;i++) { reset(); endpoint(0,0,0); fail_read=i; build(&root,1,0,false,-5); CHECK(preparations==i); }
    reset(); unavailable_bus=0; build(&root,1,0,false,-5); CHECK(preparations==1);
    reset(); bridge(0,0,0,0,1,10,true); snapshot=build(&root,1,0,false,0); count=preparations; destroy(snapshot);
    for(unsigned i=1;i<=count;i++) { reset(); bridge(0,0,0,0,1,10,true); fail_read=i; build(&root,1,0,false,-5); CHECK(preparations==i); }
}
static void allocation_failures(void) {
    uint8_t root=0;
    reset(); bridge(0,0,0,0,1,10,false); endpoint(0,1,1); bridge(1,0,0,1,2,5,false); endpoint(2,1,0);
    void *snapshot=build(&root,1,0,false,0); unsigned count=alloc_attempts; CHECK(count==8); destroy(snapshot);
    for(unsigned policy=0;policy<2;policy++) for(unsigned failure=1;failure<=count;failure++) {
        reset(); bridge(0,0,0,0,1,10,false); endpoint(0,1,1); bridge(1,0,0,1,2,5,false); endpoint(2,1,0);
        if(policy) fail_alloc=failure;
        build(&root,1,policy ? 0 : failure,false,-12);
        CHECK(alloc_attempts==failure-(policy ? 0 : 1));
    }
    reset(); for(unsigned devfn=0;devfn<256;devfn++) endpoint(0,devfn>>3,devfn&7);
    snapshot=build(&root,1,0,false,0); CHECK(alloc_attempts==258 && topology_test_count(snapshot,1)==256); destroy(snapshot);
    for(unsigned round=0;round<200;round++) {
        alloc_attempts=0; snapshot=build(&root,1,0,false,0); CHECK(alloc_attempts==258); destroy(snapshot);
    }
    /* Successful checked transport preserves both already-off IRQ and a pin. */
    irq_enabled=false; pins=9; snapshot=build(&root,1,0,false,0); destroy(snapshot);
    CHECK(!irq_enabled && pins==9); irq_enabled=true; pins=0;
}
static unsigned reader_ready, reader_stop, reader_passes;
static void *reader(void *snapshot) {
    __atomic_store_n(&reader_ready,1,__ATOMIC_RELEASE);
    while(!__atomic_load_n(&reader_stop,__ATOMIC_ACQUIRE)) {
        if (__atomic_load_n(&reader_passes,__ATOMIC_RELAXED) >= 4096) {
            sched_yield(); continue;
        }
        CHECK(topology_test_count(snapshot,0)==1 && topology_test_count(snapshot,1)==1);
        void *device=topology_test_first(snapshot,1);
        CHECK(device && topology_test_field(device,1,0)==BDF(0,0,0));
        CHECK(!topology_test_next(device,1));
        __atomic_add_fetch(&reader_passes,1,__ATOMIC_RELEASE);
    }
    return NULL;
}
static void immutable_reader(void) {
    reset(); endpoint(0,0,0); uint8_t root=0; void *old=build(&root,1,0,false,0);
    size_t objects=live_objects, bytes=live_bytes;
    reader_ready=reader_stop=reader_passes=0; pthread_t actor;
    CHECK(pthread_create(&actor,NULL,reader,old)==0);
    for(unsigned spins=0;!__atomic_load_n(&reader_ready,__ATOMIC_ACQUIRE);spins++) { if(spins==10000000) CHECK(false); sched_yield(); }
    for(unsigned i=0;i<200;i++) {
        int64_t status; void *temporary=topology_test_build(&root,1,0,false,&status);
        CHECK(status==0 && temporary && temporary!=old);
        topology_test_destroy(temporary); CHECK(live_objects==objects && live_bytes==bytes);
    }
    for(unsigned spins=0;__atomic_load_n(&reader_passes,__ATOMIC_ACQUIRE)<4096;spins++) { if(spins==10000000) CHECK(false); sched_yield(); }
    __atomic_store_n(&reader_stop,1,__ATOMIC_RELEASE);
    CHECK(pthread_join(actor,NULL)==0); /* Reader quiescence before owner frees old. */
    CHECK(reader_passes>0); destroy(old);
}
static struct Image *cap_device(uint8_t header) {
    reset(); struct Image *record=endpoint(0,0,0); put(record,6,2,0x10);
    put(record,header==2 ? 0x14 : 0x34,1,header==2 ? 0x48 : 0x40);
    return record;
}
static void cap_header(struct Image *record,unsigned offset,unsigned id,unsigned next,unsigned control) {
    put(record,offset,2,id | next<<8); put(record,offset+2,2,control);
}
static void caps(uint32_t bdf,uint8_t header,bool no_read,int64_t status,
        unsigned msi,unsigned msix,unsigned entries) {
    uint16_t result[]={0xaaaa,0xbbbb,0xcccc}; bool before_irq=irq_enabled; unsigned before_pins=pins;
    parsing_capabilities=true;
    CHECK(topology_test_capabilities(bdf,header,no_read,result)==status);
    parsing_capabilities=false;
    CHECK(result[0]==msi && result[1]==msix && result[2]==entries);
    CHECK(live_objects==0 && live_bytes==0 && alloc_attempts==0 && writes==0);
    CHECK(!locked && lock_count==unlock_count && irq_enabled==before_irq && pins==before_pins);
}
static void capability_cases(void) {
    reset(); caps(0x10000,0,false,-22,0,0,0); caps(0,3,false,-22,0,0,0); caps(0,0,true,-22,0,0,0); CHECK(preparations==0);
    struct Image *record=cap_device(0); put(record,6,2,0); caps(0,0,false,0,0,0,0); CHECK(preparations==1);
    record=cap_device(0); put(record,0x34,1,0); caps(0,0,false,0,0,0,0);
    record=cap_device(0); cap_header(record,0x40,5,0x60,0); cap_header(record,0x60,0x11,0,0);
    caps(0,0,false,0,0x40,0x60,1); unsigned count=preparations;
    for(unsigned failure=1;failure<=count;failure++) {
        record=cap_device(0); cap_header(record,0x40,5,0x60,0); cap_header(record,0x60,0x11,0,0);
        fail_read=failure; caps(0,0,false,-5,0,0,0); CHECK(preparations==failure);
    }
    record=cap_device(1); cap_header(record,0x40,0x11,0,0x7ff); caps(0,1,false,0,0,0x40,2048);
    record=cap_device(2); cap_header(record,0x48,5,0x80,0x180); cap_header(record,0x80,0x11,0,7);
    caps(0,2,false,0,0x48,0x80,8); CHECK(record->transactions[0x14]==1 && record->transactions[0x34]==0);
    record=cap_device(2); put(record,0x14,1,0x44); caps(0,2,false,-71,0,0,0); CHECK(preparations==2);
    static const unsigned controls[]={0,0x80,0x100,0x180}, lengths[]={10,14,20,24};
    for(unsigned i=0;i<4;i++) {
        unsigned offset=(256-lengths[i]) & ~3u;
        record=cap_device(0); put(record,0x34,1,offset); cap_header(record,offset,5,0,controls[i]);
        caps(0,0,false,0,offset,0,0);
        record=cap_device(0); put(record,0x34,1,offset+4); cap_header(record,offset+4,5,0,controls[i]);
        caps(0,0,false,-71,0,0,0);
    }
    record=cap_device(0); put(record,0x34,1,0xf4); cap_header(record,0xf4,0x11,0,0); caps(0,0,false,0,0,0xf4,1);
    record=cap_device(0); put(record,0x34,1,0xf8); cap_header(record,0xf8,0x11,0,0); caps(0,0,false,-71,0,0,0);
    static const unsigned pointers[]={1,0x3c,0x41,0xfd,0xff};
    for(unsigned i=0;i<5;i++) { record=cap_device(0); put(record,0x34,1,pointers[i]); caps(0,0,false,-71,0,0,0); CHECK(preparations==2); }
    record=cap_device(0); cap_header(record,0x40,1,0x40,0); caps(0,0,false,-40,0,0,0); CHECK(preparations==3);
    record=cap_device(0); cap_header(record,0x40,1,0x60,0); cap_header(record,0x60,2,0x40,0); caps(0,0,false,-40,0,0,0); CHECK(preparations==4);
    for(unsigned id=5;id<=0x11;id+=12) { record=cap_device(0); cap_header(record,0x40,id,0x80,0); cap_header(record,0x80,id,0,0); caps(0,0,false,-71,0,0,0); }
    record=cap_device(0); cap_header(record,0x40,5,0x44,0x180); cap_header(record,0x44,1,0,0); caps(0,0,false,-71,0,0,0);
    record=cap_device(0); put(record,0x34,1,0x44); cap_header(record,0x44,1,0x40,0); cap_header(record,0x40,5,0,0); caps(0,0,false,-71,0,0,0);
    record=cap_device(0); put(record,0x34,1,0xa0); cap_header(record,0xa0,0x11,0x60,0); cap_header(record,0x60,5,0x40,0x80); cap_header(record,0x40,1,0,0);
    caps(0,0,false,0,0x60,0xa0,1); /* Nonmonotonic but disjoint list is valid. */
    record=cap_device(0);
    for(unsigned offset=0x40;offset<=0xfc;offset+=4) cap_header(record,offset,0x7f,offset==0xfc ? 0 : offset+4,0);
    caps(0,0,false,0,0,0,0); CHECK(preparations==50); /* All 48 possible headers. */
    irq_enabled=false; pins=7; caps(0,0,false,0,0,0,0); CHECK(!irq_enabled && pins==7); irq_enabled=true; pins=0;
}
int main(void) {
    relationships(); absence_and_limits(); malformed(); allocation_failures(); immutable_reader(); capability_cases();
    CHECK(live_objects==0 && live_bytes==0 && writes==0);
    printf("PASS: %u assertions; actual topology/config/capability V, complete rollback and quiescent readers\\n",assertions);
    return 0;
}
'

fn hash_json(values map[string]string) map[string]json2.Any {
	mut result := map[string]json2.Any{}
	for key, value in values { result[key] = value }
	return result
}
