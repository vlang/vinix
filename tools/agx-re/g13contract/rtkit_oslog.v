// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import os

fn check_rtkit_oslog(transport string, linux string, asahi_linux string, repo string) ! {
	require_order(linux, ['#define APPLE_RTKIT_OSLOG_TYPE GENMASK_ULL(63, 56)',
		'#define APPLE_RTKIT_OSLOG_LOG 2', '#define APPLE_RTKIT_OSLOG_LOG_RESERVED GENMASK_ULL(55, 32)'],
		'Asahi OSLog notification type and reserved channel bits')!
	reference := section(linux, 'static void apple_rtkit_oslog_rx(', 'static void apple_rtkit_rx_work(', 'Asahi OSLog receive')!
	require_order(reference, ['rtk->sync_syslog_ack || of_machine_is_compatible("apple,t8140")',
		'of_machine_is_compatible("apple,t8142")', 'return;', 'case APPLE_RTKIT_OSLOG_LOG:',
		'!rtk->oslog_buffer.size && !rtk->oslog_inherited', 'msg & APPLE_RTKIT_OSLOG_LOG_RESERVED',
		'break;', 'err = apple_rtkit_send_message(rtk, APPLE_RTKIT_EP_OSLOG,', 'msg, NULL, false)',
		'if (err)', 'case 3 ... 5:'], 'Asahi echoes the full counter only on the configured channel')!

	dts := read(os.join_path(asahi_linux, 'arch/arm64/boot/dts/apple/t8103.dtsi'))!
	node := section(dts, 'gpu: gpu@206400000 {', '\n\t\t};', 'Asahi base-M1 GPU node')!
	require(node.contains('apple,agx-t8103') && !node.contains('apple,sync-syslog-ack'),
		'Base M1 AGX uses Asahi normal OSLog acknowledgements')!
	asahi_gpu := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/gpu.rs'))!
	asahi_rust := read(os.join_path(asahi_linux, 'rust/kernel/soc/apple/rtkit.rs'))!
	init := section(linux, 'struct apple_rtkit *apple_rtkit_init(', 'EXPORT_SYMBOL_GPL(apple_rtkit_init);', 'Asahi RTKit constructor')!
	require(asahi_gpu.contains('rtkit::RtKit::<GpuManager::ver>::new(')
		&& asahi_rust.contains('from_err_ptr(bindings::apple_rtkit_init(')
		&& init.contains('return __apple_rtkit_init(dev, cookie, mbox_name, mbox_idx, ops, false);'),
		'Asahi AGX uses the normal RTKit constructor without inherited buffers')!
	driver := read(os.join_path(repo, 'kernel/gpu/agx/driver/driver.v'))!
	require_order(driver, ['gpu_rtk := rtkit.new_rtkit(platform.mailbox_base,', 'gpu.new_gpu_manager(&gpu_res, &cfg, &gpu_rtk',
		'probe := mgr.init(receive_irq, send_irq)'], 'Vinix AGX starts its own RTKit session')!

	require_order(transport, ['const oslog_log = u8(2)', 'const oslog_log_reserved = u64(0xff_ffff) << 32',
		'oslog_ack_enabled bool\n'], 'Vinix OSLog wire type, reserved bits and default-disabled policy')!
	oslog := section(transport, '\n\t\tep_oslog {', 'fn start_system_endpoints(', 'Vinix OSLog receive')!
	require_order(oslog, ['kind := u8(msg.data0 >> 56)', 'if kind == buffer_request',
		'return rtk.reply_system_buffer(ep, msg.data0, wait)', 'kind == oslog_log && rtk.oslog_ack_enabled',
		'rtk.system_iovas[ep] == 0 || msg.data0 & oslog_log_reserved != 0', 'return true',
		'if !rtk.send_system_reply(ep, msg.data0, wait)', 'oslog acknowledgement failed', 'return true'],
		'Vinix echoes the exact negotiated-channel message and logs send errors')!
	manager := read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!
	create := section(manager, 'pub fn new_gpu_manager(', 'fn (mut mgr GpuManager) boot_firmware_role(', 'Vinix G13 OSLog policy')!
	require_order(create, ['if cfg.gpu_gen == .g13 {', 'set_shmem_reader(copy_rtkit_shmem)',
		'mgr.rtk.oslog_ack_enabled = true', '\n\t}', 'return mgr'], 'Only the base-M1 G13 manager enables OSLog ACKs')!
}
