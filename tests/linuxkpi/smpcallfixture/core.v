// SPDX-License-Identifier: GPL-2.0-or-later
// Independent observable scenarios, context and IPI transport; no queue model.
@[translated]
module smpcallfixture

#include "smpcall_host_contract.h"

@[typedef] struct C.pthread_key_t {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.call_single_data_t {}
@[typedef] struct C.smph_const_charp {}
struct C.cpumask {}
fn C.pthread_key_create(&C.pthread_key_t, voidptr) i32
fn C.pthread_getspecific(C.pthread_key_t) voidptr
fn C.pthread_setspecific(C.pthread_key_t, voidptr) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, &voidptr) i32
fn C.sched_yield() i32
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.free(voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.printf(&char, ...) i32
fn C.fprintf(voidptr, &char, ...) i32
@[c_extern] __global C.stderr voidptr
@[noreturn] fn C.abort()
fn C.atoi(&char) i32
fn C.smph_load32(&u32) u32
fn C.smph_store32(&u32, u32)
fn C.smph_add32(&u32, u32) u32
fn C.smph_load_flags(&C.call_single_data_t) u32
fn C.smph_set_flags(&C.call_single_data_t, u32)
fn C.smph_init(&C.call_single_data_t, fn (voidptr), voidptr)
fn C.smph_csd_bytes() usize
fn C.smph_csd_alignment() usize
fn C.smph_line_value(string) &char
fn C.smph_mask_bits(&C.cpumask) &usize
fn C.vks_smp_bootstrap(u32) i32
fn C.vks_smp_ready() bool
fn C.vks_smp_drain(u32)
fn C.vks_smp_single(u32, i32, fn (voidptr), voidptr, voidptr) i32
fn C.vks_smp_async(i32, voidptr) i32
fn C.vks_smp_many(voidptr, fn (voidptr), voidptr, bool, bool, fn (i32, voidptr) bool)
fn C.vkm_cpu_masks_bootstrap(u32) i32
fn C.smp_call_function_single(i32, fn (voidptr), voidptr, i32) i32
fn C.smp_call_function_single_async(i32, voidptr) i32
fn C.smp_call_function_many(&C.cpumask, fn (voidptr), voidptr, bool)
fn C.smp_call_function(fn (voidptr), voidptr, i32)
fn C.on_each_cpu_cond_mask(fn (i32, voidptr) bool, fn (voidptr), voidptr, bool, &C.cpumask)

struct Context {
mut:
	cpu u32
	flags u64 = 0x202
	depth u32
	pins u32
	spins u32
	constructor bool = true
}

struct Observation {
mut:
	expected_cpu u32
	expected_depth u32 = 1
	expected_pins u32
	count u32
	terminal u32
	entered u32
	release u32 = 1
	order u32
	value u32
	owner voidptr
	free_self bool
}

// The native typedef supplies its real 32-byte alignment, including in arrays.
struct Owner {
mut:
	csd C.call_single_data_t
	argument Observation
}

struct SyncProducer {
mut:
	context Context
	csd C.call_single_data_t
	argument &Observation = unsafe { nil }
	target i32
	returned u32
	result i32
}

struct Handler {
mut:
	cpu u32
	restored u32
}

@[cinit]
__global (
	context_key C.pthread_key_t
	assertions u32
	ipis [256]u32
	handler_returns [256]u32
	callbacks [256]u32
	condition_calls [256]u32
	immediate u32
	allocation_calls u32
	allocation_live u32
	fail_after i32 = -1
	batch [2200]Owner
	sequence u32
	condition_mask [4]u64
	mutate_once u32
	nested_callbacks [256]u32
	condition_order u32
)

fn check(value bool, line string) {
	unsafe {
		C.smph_add32(&assertions, 1)
		if !value { C.fprintf(C.stderr, c'SMP assertion line %s; number %u\n', C.smph_line_value(line), assertions); C.abort() }
	}
}

fn context() &Context { return unsafe { &Context(C.pthread_getspecific(context_key)) } }

fn install(ctx &Context) { check(unsafe { C.pthread_setspecific(context_key, ctx) } == 0, @LINE) }

fn await_word(word &u32, expected u32) {
	for turns := u32(0); turns < 20000000; turns++ {
		if C.smph_load32(word) >= expected { return }
		C.sched_yield()
	}
	check(false, @LINE)
}

@[export: 'vinix_linuxkpi_cpu_id']
pub fn cpu_id() u32 { return context().cpu }
@[export: 'vinix_linuxkpi_preempt_count']
pub fn preempt_count() u32 { return context().pins }
@[export: 'vinix_linuxkpi_preempt_disable']
pub fn preempt_disable() { unsafe { context().pins++ } }
@[export: 'vinix_linuxkpi_preempt_enable']
pub fn preempt_enable() { unsafe { check(context().pins != 0, @LINE); context().pins-- } }
@[export: 'vinix_linuxkpi_irq_flags']
pub fn irq_flags() usize { return usize(context().flags) }
@[export: 'vinix_linuxkpi_irq_save']
pub fn irq_save() usize { unsafe { old := context().flags; context().flags &= ~u64(512); return usize(old) } }
@[export: 'vinix_linuxkpi_irq_restore']
pub fn irq_restore(flags usize) { unsafe { context().flags = u64(flags) } }
@[export: 'vinix_linuxkpi_maskable_irq_depth']
pub fn irq_depth() u32 { return context().depth }
@[export: 'vinix_linuxkpi_smp_boot_context']
pub fn boot_context() bool { return context().constructor && context().pins == 0 && context().depth == 0 && (context().flags & 512) != 0 }
@[export: 'vinix_linuxkpi_smp_task_present']
pub fn task_present() bool { return context().constructor }
@[export: 'vinix_linuxkpi_spin_wait']
pub fn spin_wait() { unsafe { C.smph_add32(&context().spins, 1) }; C.sched_yield() }
@[export: 'vinix_linuxkpi_bug'; noreturn]
pub fn bug(reason C.smph_const_charp, line i32) { unsafe { C.fprintf(C.stderr, c'SMP invariant: %s:%d\n', reason, line) }; C.abort() }

@[export: 'kmalloc']
pub fn allocate(bytes usize, flags u32) voidptr {
	unsafe {
		check(flags == 3264 && boot_context(), @LINE)
		allocation_calls++
		if fail_after == 0 { return nil }
		if fail_after > 0 { fail_after-- }
		mut result := voidptr(nil)
		check(C.posix_memalign(&result, 32, bytes) == 0, @LINE)
		C.memset(result, 0xa5, bytes)
		allocation_live++
		return result
	}
}
@[export: 'kfree']
pub fn deallocate(pointer voidptr) {
	unsafe { check(pointer != nil && allocation_live != 0, @LINE); allocation_live--; C.free(pointer) }
}

fn deliver(cpu u32) {
	unsafe {
		old := context()
		mut interrupt := Context{cpu: cpu, flags: 2, depth: 1, constructor: false}
		install(&interrupt)
		C.vks_smp_drain(cpu)
		check(interrupt.cpu == cpu && interrupt.flags == 2 && interrupt.depth == 1 && interrupt.pins == 0, @LINE)
		install(old)
		// This is after host context restoration; native retirement needs IRET.
		C.smph_add32(&handler_returns[cpu], 1)
	}
}

@[export: 'vinix_linuxkpi_smp_send_ipi']
pub fn send_ipi(cpu u32) {
	unsafe {
		check(cpu < 256, @LINE)
		C.smph_add32(&ipis[cpu], 1)
		if C.smph_load32(&immediate) != 0 { deliver(cpu) }
	}
}

fn observe(argument voidptr) {
	unsafe {
		arg := &Observation(argument)
		ctx := context()
		check(ctx.cpu == arg.expected_cpu && ctx.depth == arg.expected_depth && ctx.pins == arg.expected_pins && (ctx.flags & 512) == 0, @LINE)
		C.smph_add32(&arg.count, 1)
		arg.order = C.smph_add32(&sequence, 1)
		C.smph_store32(&arg.entered, 1)
		await_word(&arg.release, 1)
		owner := arg.owner
		free_self := arg.free_self
		if free_self { C.free(owner) }
		// Borrowed arguments are separate from self-freed CSD storage.
		C.smph_store32(&arg.terminal, 1)
	}
}

fn count_cpu(argument voidptr) {
	unsafe {
		ctx := context()
		check((ctx.flags & 512) == 0 && ctx.depth <= 1, @LINE)
		C.smph_add32(&callbacks[ctx.cpu], 1)
	}
}

fn nested_count(argument voidptr) {
	unsafe { C.smph_add32(&nested_callbacks[context().cpu], 1) }
}

fn mutating_condition(cpu i32, argument voidptr) bool {
	unsafe {
		check(context().pins > 0 && context().depth == 0 && (context().flags & 512) != 0, @LINE)
		// Outer candidates and local membership belong to the entry snapshot.
		// Conditions can mutate their borrowed mask and recursively call many.
		C.smph_add32(&mutate_once, 1)
		if cpu == 2 {
			original := &C.cpumask(argument)
			words := C.smph_mask_bits(original)
			for word := 0; word < 4; word++ { words[word] = 0 }
			mut nested := C.cpumask{}
			inner := C.smph_mask_bits(&nested)
			inner[0] = usize(1) << 1
			// Outer target 1 was already queued. Recursion must reclaim its
			// same source/target slot after that earlier IPI unlocked it.
			C.vks_smp_many(&nested, nested_count, nil, true, false, nil)
		}
		if u32(cpu) == context().cpu {
			check(condition_order == 7, @LINE)
		} else {
			check(u32(cpu) > condition_order || condition_order == 0, @LINE)
			condition_order = u32(cpu)
		}
		C.smph_add32(&condition_calls[cpu], 1)
		return true
	}
}

fn condition(cpu i32, argument voidptr) bool {
	unsafe {
		check(context().depth == 0 && context().pins > 0 && (context().flags & 512) != 0 && cpu >= 0 && cpu < 256, @LINE)
		C.smph_add32(&condition_calls[cpu], 1)
		return (condition_mask[u32(cpu) / 64] & (u64(1) << (u32(cpu) % 64))) != 0
	}
}

fn sync_producer(argument voidptr) voidptr {
	unsafe {
		producer := &SyncProducer(argument)
		install(&producer.context)
		original_pins := producer.context.pins
		C.smph_init(&producer.csd, observe, producer.argument)
		producer.result = C.vks_smp_single(1, producer.target, observe, producer.argument, &producer.csd)
		check(producer.context.flags == 0x202 && producer.context.pins == original_pins && producer.context.depth == 0, @LINE)
		C.smph_store32(&producer.returned, 1)
		return nil
	}
}

fn handler_actor(argument voidptr) voidptr {
	unsafe {
		handler := &Handler(argument)
		mut base := Context{cpu: handler.cpu}
		install(&base)
		deliver(handler.cpu)
		check(base.flags == 0x202 && base.depth == 0 && base.pins == 0, @LINE)
		C.smph_store32(&handler.restored, 1)
		return nil
	}
}

fn initialise(owner &Owner, cpu u32) {
	unsafe { *owner = Owner{}; owner.argument.expected_cpu = cpu; C.smph_init(&owner.csd, observe, &owner.argument) }
}

fn test_local_and_errors() {
	unsafe {
		mut local := Observation{expected_cpu: 0, expected_depth: 0, expected_pins: 1}
		mut node := C.call_single_data_t{}
		C.smph_init(&node, observe, &local)
		check(C.smp_call_function_single_async(0, &node) == 0, @LINE)
		check(local.count == 1 && local.terminal == 1 && C.smph_load_flags(&node) == 0, @LINE)
		check(context().flags == 0x202 && context().pins == 0, @LINE)
		C.smph_store32(&immediate, 1)
		context().pins = 2
		for round := 0; round < 100; round++ {
			mut sync_arg := Observation{expected_cpu: 1, value: u32(round)}
			check(C.smp_call_function_single(1, observe, &sync_arg, 1) == 0 && sync_arg.terminal == 1 && sync_arg.count == 1, @LINE)
			check(context().flags == 0x202 && context().pins == 2 && context().depth == 0, @LINE)
		}
		check(C.smp_call_function_single(-1, nil, nil, 0) == -6 && context().pins == 2, @LINE)
		check(C.smp_call_function_single(256, nil, nil, 1) == -6 && context().pins == 2, @LINE)
		context().pins = 0
		C.smph_store32(&immediate, 0)
		C.smph_set_flags(&node, 1)
		check(C.vks_smp_async(-1, &node) == -16 && C.smph_load_flags(&node) == 1, @LINE)
		C.smph_init(&node, nil, nil)
		C.smph_set_flags(&node, 1)
		check(C.vks_smp_async(-1, &node) == -16 && C.smph_load_flags(&node) == 1, @LINE)
		C.smph_set_flags(&node, 0)
		check(C.vks_smp_async(-1, &node) == -6 && C.smph_load_flags(&node) == 0 && local.count == 1, @LINE)
		check(C.vks_smp_async(256, &node) == -6 && C.smph_load_flags(&node) == 0, @LINE)
		C.smph_init(&node, observe, &local)
		context().flags = 2; context().depth = 1; context().pins = 2
		local.expected_depth = 1; local.expected_pins = 3
		check(C.vks_smp_async(0, &node) == 0, @LINE)
		check(context().flags == 2 && context().depth == 1 && context().pins == 2, @LINE)
		context().depth = 0; local.expected_depth = 0
		check(C.vks_smp_async(0, &node) == 0 && context().flags == 2 && context().depth == 0 && context().pins == 2, @LINE)
		context().flags = 0x202; context().depth = 0; context().pins = 0
	}
}

fn test_sync_hold() {
	unsafe {
		mut result := Observation{expected_cpu: 1, release: 0}
		mut producer := SyncProducer{context: Context{cpu: 2, pins: 2}, argument: &result, target: 1}
		mut sender := C.pthread_t{}
		before := C.smph_load32(&ipis[1])
		check(C.pthread_create(&sender, nil, sync_producer, &producer) == 0, @LINE)
		// Empty->nonempty IPI is an actual publication witness for this fresh head.
		await_word(&ipis[1], before + 1)
		mut handler := Handler{cpu: 1}
		mut receiver := C.pthread_t{}
		check(C.pthread_create(&receiver, nil, handler_actor, &handler) == 0, @LINE)
		await_word(&result.entered, 1)
		check((C.smph_load_flags(&producer.csd) & 1) != 0 && C.smph_load32(&producer.returned) == 0 && result.terminal == 0, @LINE)
		C.smph_store32(&result.release, 1)
		check(C.pthread_join(sender, nil) == 0 && C.pthread_join(receiver, nil) == 0, @LINE)
		check(producer.result == 0 && producer.returned == 1 && result.terminal == 1 && handler.restored == 1 && producer.context.pins == 2, @LINE)
	}
}

fn test_intrusive_capacity() {
	unsafe {
		before := ipis[1]
		for index := u32(0); index < 2200; index++ {
			initialise(&batch[index], 1)
			check(C.vks_smp_async(1, &batch[index].csd) == 0, @LINE)
		}
		check(ipis[1] == before + 1, @LINE)
		deliver(1)
		for index := u32(0); index < 2200; index++ {
			check(batch[index].argument.count == 1 && batch[index].argument.terminal == 1 && C.smph_load_flags(&batch[index].csd) == 0, @LINE)
			if index != 0 { check(batch[index - 1].argument.order + 1 == batch[index].argument.order, @LINE) }
		}
	}
}

fn test_marker_and_reuse() {
	unsafe {
		mut paused := Observation{expected_cpu: 1, release: 0}
		mut marker := Observation{expected_cpu: 1}
		mut later := Observation{expected_cpu: 1}
		mut csd := C.call_single_data_t{}
		mut later_csd := C.call_single_data_t{}
		C.smph_init(&csd, observe, &paused)
		before_ipi := ipis[1]
		check(C.vks_smp_async(1, &csd) == 0, @LINE)
		check(ipis[1] == before_ipi + 1, @LINE)
		mut producer := SyncProducer{argument: &marker, target: 1}
		mut sender := C.pthread_t{}
		check(C.pthread_create(&sender, nil, sync_producer, &producer) == 0, @LINE)
		// Fresh known-zero CSD: the actual first wait happens after enqueue.
		// LOCK alone is insufficient evidence that the detached batch contains it.
		await_word(&producer.context.spins, 1)
		mut other_args := [Observation{expected_cpu: 1}, Observation{expected_cpu: 1}]!
		mut others := [SyncProducer{context: Context{cpu: 2}, argument: &other_args[0], target: 1},
			SyncProducer{context: Context{cpu: 3}, argument: &other_args[1], target: 1}]!
		mut senders := [2]C.pthread_t{}
		for index := 0; index < 2; index++ {
			check(C.pthread_create(&senders[index], nil, sync_producer, &others[index]) == 0, @LINE)
			await_word(&others[index].context.spins, 1)
		}
		C.smph_init(&later_csd, observe, &later)
		check(C.vks_smp_async(1, &later_csd) == 0, @LINE)
		mut handler := Handler{cpu: 1}
		mut receiver := C.pthread_t{}
		check(C.pthread_create(&receiver, nil, handler_actor, &handler) == 0, @LINE)
		await_word(&paused.entered, 1)
		await_word(&producer.returned, 1)
		for index := 0; index < 2; index++ { await_word(&others[index].returned, 1) }
		check(producer.result == 0 && marker.terminal == 1 && paused.terminal == 0 && later.count == 0, @LINE)
		check(marker.order < paused.order && C.smph_load_flags(&csd) == 0, @LINE)
		check(marker.order + 1 == other_args[0].order && other_args[0].order + 1 == other_args[1].order && other_args[1].order < paused.order, @LINE)
		// Reuse the already-unlocked original CSD while its first callback pauses.
		mut reused := Observation{expected_cpu: 2}
		C.smph_init(&csd, observe, &reused)
		C.smph_store32(&immediate, 1)
		check(C.vks_smp_async(2, &csd) == 0 && reused.terminal == 1 && paused.terminal == 0, @LINE)
		C.smph_store32(&immediate, 0)
		C.smph_store32(&paused.release, 1)
		check(C.pthread_join(sender, nil) == 0 && C.pthread_join(receiver, nil) == 0, @LINE)
		for index := 0; index < 2; index++ { check(C.pthread_join(senders[index], nil) == 0 && others[index].result == 0, @LINE) }
		check(handler.restored == 1 && paused.terminal == 1 && later.terminal == 1 && later.order > paused.order, @LINE)
	}
}

fn test_self_free() {
	unsafe {
		for round := u32(0); round < 200; round++ {
			mut storage := voidptr(nil)
			check(C.posix_memalign(&storage, 32, C.smph_csd_bytes()) == 0, @LINE)
			mut result := Observation{expected_cpu: 1, owner: storage, free_self: true}
			C.smph_init(&C.call_single_data_t(storage), observe, &result)
			before := handler_returns[1]
			if round % 2 == 0 { C.smph_store32(&immediate, 1) }
			check(C.vks_smp_async(1, storage) == 0, @LINE)
			if round % 2 != 0 { deliver(1) }
			C.smph_store32(&immediate, 0)
			check(result.terminal == 1 && result.count == 1 && handler_returns[1] == before + 1, @LINE)
			// No node read after callback; the next allocation may reuse its address.
		}
	}
}

fn test_caller_free() {
	unsafe {
		mut storage := voidptr(nil)
		check(C.posix_memalign(&storage, 32, C.smph_csd_bytes()) == 0, @LINE)
		mut result := Observation{expected_cpu: 1, release: 0}
		C.smph_init(&C.call_single_data_t(storage), observe, &result)
		check(C.vks_smp_async(1, storage) == 0, @LINE)
		mut handler := Handler{cpu: 1}
		mut receiver := C.pthread_t{}
		check(C.pthread_create(&receiver, nil, handler_actor, &handler) == 0, @LINE)
		await_word(&result.entered, 1)
		check(C.smph_load_flags(&C.call_single_data_t(storage)) == 0 && result.terminal == 0 && handler.restored == 0, @LINE)
		// The release-unlocked CSD can retire independently of callback info.
		C.free(storage)
		C.smph_store32(&result.release, 1)
		check(C.pthread_join(receiver, nil) == 0 && result.terminal == 1 && handler.restored == 1, @LINE)
		// The argument lives through terminal callback use and restored-handler ACK.
	}
}

fn test_async_many() {
	unsafe {
		mut mask := C.cpumask{}
		C.smph_mask_bits(&mask)[0] = 15
		for cpu := 0; cpu < 4; cpu++ { callbacks[cpu] = 0 }
		context().pins = 1
		C.vks_smp_many(&mask, count_cpu, nil, false, false, nil)
		check(callbacks[0] == 0 && callbacks[1] == 0 && callbacks[2] == 0 && callbacks[3] == 0 && context().pins == 1, @LINE)
		context().pins = 0
		for cpu := u32(1); cpu < 4; cpu++ { deliver(cpu) }
		check(callbacks[0] == 0 && callbacks[1] == 1 && callbacks[2] == 1 && callbacks[3] == 1, @LINE)
		for cpu := 0; cpu < 4; cpu++ { callbacks[cpu] = 0 }
	}
}

fn test_condition_snapshot() {
	unsafe {
		mut mask := C.cpumask{}
		words := C.smph_mask_bits(&mask)
		words[0] = 0xff
		for cpu := 0; cpu < 256; cpu++ { callbacks[cpu] = 0; condition_calls[cpu] = 0; nested_callbacks[cpu] = 0 }
		context().cpu = 3; context().pins = 1
		condition_order = 0; mutate_once = 0
		C.smph_store32(&immediate, 1)
		C.vks_smp_many(&mask, count_cpu, &mask, true, true, mutating_condition)
		check(mutate_once == 8 && nested_callbacks[1] == 1, @LINE)
		for cpu := 0; cpu < 256; cpu++ {
			check(callbacks[cpu] == (if cpu < 8 { u32(1) } else { u32(0) }) && condition_calls[cpu] == (if cpu < 8 { u32(1) } else { u32(0) }), @LINE)
		}
		check(words[0] == 0 && words[1] == 0 && words[2] == 0 && words[3] == 0, @LINE)
		// Empty selection and rejected conditions do not invoke a NULL callback.
		C.vks_smp_many(&mask, nil, nil, true, true, nil)
		for word := 0; word < 4; word++ { condition_mask[word] = 0; words[word] = ~usize(0) }
		C.vks_smp_many(&mask, nil, nil, true, true, condition)
		check(context().pins == 1 && context().depth == 0 && context().flags == 0x202, @LINE)
		context().pins = 0; context().cpu = 0
		C.smph_store32(&immediate, 0)
	}
}

fn test_many(count u32) {
	unsafe {
		mut mask := C.cpumask{}
		bits := C.smph_mask_bits(&mask)
		for word := u32(0); word < 4; word++ { bits[word] = ~usize(0); condition_mask[word] = u64(1) | (u64(1) << 63) }
		C.smph_store32(&immediate, 1)
		context().cpu = if count == 256 { u32(128) } else { u32(0) }
		context().pins = 1
		C.vks_smp_many(&mask, count_cpu, nil, true, false, condition)
		for cpu := u32(0); cpu < count; cpu++ {
			selected := cpu != context().cpu && (cpu % 64 == 0 || cpu % 64 == 63)
			check(callbacks[cpu] == (if selected { u32(1) } else { u32(0) }), @LINE)
			check(condition_calls[cpu] == (if cpu == context().cpu { u32(0) } else { u32(1) }), @LINE)
			callbacks[cpu] = 0; condition_calls[cpu] = 0
		}
		C.vks_smp_many(&mask, count_cpu, nil, true, true, condition)
		for cpu := u32(0); cpu < count; cpu++ {
			selected := cpu % 64 == 0 || cpu % 64 == 63
			check(callbacks[cpu] == (if selected { u32(1) } else { u32(0) }) && condition_calls[cpu] == 1, @LINE)
		}
		check(context().pins == 1 && context().depth == 0 && context().flags == 0x202, @LINE)
		context().pins = 2
		for cpu := u32(0); cpu < count; cpu++ { callbacks[cpu] = 0 }
		C.smp_call_function_many(&mask, count_cpu, nil, true)
		for cpu := u32(0); cpu < count; cpu++ { check(callbacks[cpu] == (if cpu != context().cpu { u32(1) } else { u32(0) }), @LINE); callbacks[cpu] = 0 }
		check(context().pins == 2, @LINE)
		C.smp_call_function(count_cpu, nil, 1)
		for cpu := u32(0); cpu < count; cpu++ { check(callbacks[cpu] == (if cpu != context().cpu { u32(1) } else { u32(0) }), @LINE); callbacks[cpu] = 0; condition_calls[cpu] = 0 }
		check(context().pins == 2, @LINE)
		C.on_each_cpu_cond_mask(condition, count_cpu, nil, true, &mask)
		for cpu := u32(0); cpu < count; cpu++ { check(callbacks[cpu] == (if cpu % 64 == 0 || cpu % 64 == 63 { u32(1) } else { u32(0) }) && condition_calls[cpu] == 1, @LINE) }
		check(context().pins == 2 && context().depth == 0 && context().flags == 0x202, @LINE)
		context().pins = 0; context().cpu = 0
		C.smph_store32(&immediate, 0)
	}
}

fn construction(count u32, mode i32) {
	unsafe {
		check(!C.vks_smp_ready(), @LINE)
		check(C.vks_smp_bootstrap(0) == -22 && C.vks_smp_bootstrap(257) == -22 && allocation_calls == 0, @LINE)
		check(C.vkm_cpu_masks_bootstrap(count) == 0, @LINE)
		context().flags = 2
		check(C.vks_smp_bootstrap(count) == -1 && allocation_calls == 0 && !C.vks_smp_ready(), @LINE)
		context().flags = 0x202; context().pins = 1
		check(C.vks_smp_bootstrap(count) == -1 && allocation_calls == 0, @LINE)
		context().pins = 0; context().depth = 1
		check(C.vks_smp_bootstrap(count) == -1 && allocation_calls == 0, @LINE)
		context().depth = 0
		context().constructor = false
		check(C.vks_smp_bootstrap(count) == -1 && allocation_calls == 0, @LINE)
		context().constructor = true
		if mode == 1 || mode == 2 {
			fail_after = mode - 1
			check(C.vks_smp_bootstrap(count) == -12 && allocation_live == 0 && !C.vks_smp_ready(), @LINE)
			fail_after = -1
		}
		check(C.vks_smp_bootstrap(count) == 0 && C.vks_smp_ready() && allocation_live == 2, @LINE)
		before := allocation_calls
		check(C.vks_smp_bootstrap(count) == -114 && allocation_calls == before, @LINE)
		check(C.vks_smp_bootstrap(0) == -22 && allocation_calls == before, @LINE)
		check(C.vks_smp_bootstrap(if count == 256 { u32(255) } else { count + 1 }) == -22 && allocation_calls == before, @LINE)
	}
}

@[export: 'main']
pub fn main_entry(argc i32, argv &&char) i32 {
	unsafe {
		check(argc == 3, @LINE)
		count := u32(C.atoi(argv[1])); mode := C.atoi(argv[2])
		check(count >= 4 && count <= 256, @LINE)
		check(C.pthread_key_create(&context_key, nil) == 0, @LINE)
		mut base := Context{}
		install(&base)
		construction(count, mode)
		if count == 4 { test_local_and_errors(); test_intrusive_capacity(); test_sync_hold(); test_marker_and_reuse(); test_self_free(); test_caller_free(); test_async_many() }
		test_many(count)
		if count == 256 { test_condition_snapshot() }
		check(base.flags == 0x202 && base.pins == 0 && base.depth == 0, @LINE)
		C.printf(c'PASS: %u original-record SMP callback assertions; cpus=%u mode=%d\n', assertions, count, mode)
		return 0
	}
}
