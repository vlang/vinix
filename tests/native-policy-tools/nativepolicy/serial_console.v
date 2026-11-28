module nativepolicy

import hosttest
import os

fn serial_console_position(text string, needle string) !int {
	return text.index(needle) or { return error('Missing boot-order anchor: ' + needle) }
}

// As in the print/native boundary fixtures, stage the production V bodies
// unchanged except for module/import names and the hardware boundary.
fn serial_console() ! {
	work := private_work('vinix-serial-console-')!
	defer { retire(work) }
	hosttest.module_copy_tree(root() + '/tests/kernel-print/serial-fixture', work + '/fixture')!
	os.mkdir_all(work + '/x86/kio')!
	os.rename(work + '/fixture/kio.v', work + '/x86/kio/core.v')!
	os.mkdir(work + '/klock')!
	os.rename(work + '/fixture/klock.v', work + '/klock/core.v')!
	for name, source in {
		'console': 'kernel/dev/serial/console.v'
		'resume': 'kernel/dev/serial/resume.v'
		'uart': 'kernel/aarch64/uart/uart.v'
		'route': 'kernel/kprint/kprint_amd64.v'
		'firmware': 'kernel/aarch64/firmware/firmware.v'
	} {
		mut text := read(root() + '/' + source)!
		for module_name in ['serial', 'uart', 'kprint', 'firmware'] {
			text = text.replace('module ' + module_name + '\n', 'module fixture\n')
		}
		text = text.replace('import dev.serial\n', '').replace('import term\n', '')
			.replace('serial.out(', 'out(').replace('term.print(', 'terminal(')
			.replace('import limine\n', '').replace('import memory\n', '')
			.replace('limine.LimineRSDPRequest', 'TestRSDPRequest')
			.replace('memory.get_hhdm_offset()', 'test_hhdm_offset()')
			.replace('memory.bootloader_hhdm_offset()', 'test_bootloader_hhdm_offset()')
			.replace("@[_linker_section: '.requests']\n", '')
		write(work + '/fixture/' + name + '.v', text)!
	}
	write(work + '/v.mod', "Module { name: 'serial_console_test' }\n")!
	write(work + '/entry.v', 'module main\nimport fixture as _\n')!
	// Also guard the entry-point and page-table ordering not runnable on a host.
	x86 := read(root() + '/kernel/main_amd64.v')!
	arm := read(root() + '/kernel/main_arm64.v')!
	if serial_console_position(x86, 'serial.early_initialise()')! >= serial_console_position(x86, 'memory.pmm_init()')!
		|| serial_console_position(arm, 'firmware.boot_console_uart(qemu_console)')! >= serial_console_position(arm, 'memory.pmm_init()')!
		|| serial_console_position(arm, 'firmware.boot_console_uart(qemu_console)')! >= serial_console_position(arm, 'term.early_screen_fill(1)')! {
		return error('serial setup must precede allocator/runtime and early framebuffer output')
	}
	vmm := read(root() + '/kernel/memory/virtual_arm64.v')!
	if serial_console_position(vmm, 'map_mmio(uart.get_base() - higher_half, 0x1000)')!
		>= serial_console_position(vmm, '\n\tvmm_activate_on_cpu()')! {
		return error('UART mapping must precede page-table activation')
	}
	for prod in [false, true] {
		generated := work + '/console.c'
		generate_project(work, generated, arch(), prod, []string{})!
		obj := work + '/console.o'
		flags := concat(['clang'], clang_arch(arch()), ['-std=gnu11', '-O2', '-g',
			'-ffreestanding', '-fno-builtin', '-fsanitize=address,undefined',
			'-fno-omit-frame-pointer', '-Wno-unused-function', '-Wno-unused-parameter'])
		run(concat(flags, ['-c', generated, '-o', obj]))!
		no_allocators(output(['nm', '-u', obj])!)!
		run(concat(flags, [obj, '-o', work + '/test']))!
		timed_inherited([work + '/test'], 10)!
	}
	println('Serial console: debug/production dual routing, CRLF, pre/post _vinit, absent/stuck UARTs, RX/resume and ACPI/QEMU qualification; no allocator imports')
}
