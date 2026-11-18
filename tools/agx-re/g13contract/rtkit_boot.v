// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import os

fn check_rtkit_boot(transport string, linux string, asahi_linux string, repo string) ! {
	linux_driver := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/driver.rs'))!
	require_order(linux_driver, ['regs::Resources::start_cpu(pdev)?', 'gpu::GpuManagerG13V12_3::new',
		'gpu::GpuManagerG13V13_5::new'], 'Asahi releases the ASC before constructing either G13 firmware ABI')!
	linux_gpu := read(os.join_path(asahi_linux, 'drivers/gpu/drm/asahi/gpu.rs'))!
	require_order(linux_gpu.all_after('fn init(&self) -> Result {'),
		['DeviceControlMsg::ver::Initialize', 'rtk.as_mut().boot()?', 'start_endpoint(EP_FIRMWARE)',
		'start_endpoint(EP_DOORBELL)'], 'Asahi G13 waits for the already-started ASC before starting application endpoints')!
	rust := read(os.join_path(asahi_linux, 'rust/kernel/soc/apple/rtkit.rs'))!
	require_order(rust.all_after('pub fn boot(self:'), ['bindings::apple_rtkit_boot(self.rtk)', 'pub fn start_endpoint'],
		'Asahi G13 uses the RTKit boot entry point')!
	linux_boot := section(linux, 'static int apple_rtkit_boot_common(', 'EXPORT_SYMBOL_GPL(apple_rtkit_boot);', 'Asahi RTKit boot')!
	require_order(linux_boot, ['apple_rtkit_wait(rtk, &rtk->epmap_completion)', 'apple_rtkit_wait(rtk, &rtk->iop_pwr_ack_completion)',
		'apple_rtkit_set_ap_power_state(rtk, APPLE_RTKIT_PWR_STATE_ON)', 'return apple_rtkit_boot_common(rtk, false);'],
		'Asahi waits for endpoint and IOP readiness before AP ON without an INIT send')!
	require(!linux_boot.contains('APPLE_RTKIT_PWR_STATE_INIT'), 'Asahi boot has no IOP INIT wake request')!
	require(linux.contains('wait_for_completion_interruptible_timeout(c,\n\t\t\t\t\t\t      msecs_to_jiffies(1000))'),
		'Asahi RTKit uses a one-second completion wait')!
	power := section(linux, 'static int apple_rtkit_set_ap_power_state(', 'static int apple_rtkit_set_iop_power_state(', 'Asahi AP power request')!
	require_order(power, ['reinit_completion(&rtk->ap_pwr_ack_completion)', 'APPLE_RTKIT_MGMT_SET_AP_PWR_STATE',
		'if (ret)\n\t\treturn ret;', 'apple_rtkit_wait(rtk, &rtk->ap_pwr_ack_completion)',
		'rtk->ap_power_state != state'], 'Asahi requires a successful AP send and a new acknowledgement with the complete state')!
	epmap := section(linux, 'static void apple_rtkit_management_rx_epmap(', 'static void apple_rtkit_management_rx_iop_pwr_ack(', 'Asahi EPMAP')!
	require(linux.contains('APPLE_RTKIT_MGMT_EPMAP_BASE   GENMASK_ULL(34, 32)'), 'Asahi endpoint map base is three bits')!
	require_order(epmap, ['reply = FIELD_PREP(APPLE_RTKIT_MGMT_EPMAP_BASE, base)', 'APPLE_RTKIT_MGMT_EPMAP_REPLY_MORE',
		'apple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_EPMAP_REPLY, reply)', 'case APPLE_RTKIT_EP_TRACEKIT:',
		'ret = apple_rtkit_start_ep(rtk, ep)'], 'Asahi echoes the decoded base and starts advertised TraceKit')!
	hello := section(linux, 'static void apple_rtkit_management_rx_hello(', 'static void apple_rtkit_management_rx_epmap(', 'Asahi HELLO')!
	require(hello.contains('\n\tapple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_HELLO_REPLY, reply);\n\n\treturn;')
		&& epmap.contains('\n\tapple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_EPMAP_REPLY, reply);\n\n\tif (!(msg & APPLE_RTKIT_MGMT_EPMAP_LAST))'),
		'Asahi HELLO and EPMAP handlers leave a failed reply local to the management sender')!
	require_order(epmap.all_after('ret = apple_rtkit_start_ep(rtk, ep);'),
		['if (ret) {', 'rtk->boot_result = ret;', 'complete_all(&rtk->epmap_completion);', 'return;'],
		'Asahi aborts discovery after a required system endpoint start fails')!
	start := section(linux, 'int apple_rtkit_start_ep(', 'EXPORT_SYMBOL_GPL(apple_rtkit_start_ep);', 'Asahi endpoint start')!
	require_order(start, ['ret = apple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_STARTEP, msg);',
		'if (ret == -ETIMEDOUT)', 'ret = apple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_STARTEP, msg);',
		'return ret;'], 'Asahi retries an unsent system or application endpoint start once')!

	manager := read(os.join_path(repo, 'kernel/gpu/agx/gpu/gpu.v'))!
	role := section(manager, 'fn (mut mgr GpuManager) boot_firmware_role(', 'fn (mut mgr GpuManager) start_firmware_endpoint(', 'Vinix RTKit boot dispatch')!
	require(role.contains('if mgr.hw_config.gpu_gen == .g13 { mgr.rtk.boot_started() } else { mgr.rtk.boot() }'),
		'Vinix selects the already-started handshake for G13')!
	require_order(manager.all_after('pub fn (mut mgr GpuManager) init()'), ['mgr.res.start_cpu(role)',
		'if !mgr.boot_firmware_role(role)', 'return mgr.fail_g13_initialization()', 'mgr.start_firmware_endpoint(role, u8(ep_firmware))'],
		'Vinix enters the G13 handshake after releasing the ASC and unwinds failures before starting firmware endpoints')!
	boot := section(transport, 'pub fn (mut rtk RTKit) boot()', '// Only the system endpoints', 'Vinix RTKit handshake')!
	require_order(boot, ['return rtk.boot_transport(true)', 'return rtk.boot_transport(false)',
		'if request_wake && !rtk.send_management(msg_set_iop_power, u64(power_state_init))',
		'mut phase_started := if request_wake { u64(0) } else { timer.get_ns() }',
		'timer.get_ns() - phase_started >= boot_phase_timeout_ns', 'timer.busywait_us(10)',
		'reply_group := if request_wake { group } else { block }', 'start_system_endpoints(mut rtk, !request_wake)',
		'if !request_wake && !endpoint_map_done', 'phase_started = timer.get_ns()',
		'ap_power_requested && rtk.ap_power_state != power_state_on', 'rtk.ap_power_state = 0',
		'rtk.send_management(msg_set_ap_power, u64(power_state_on))', 'if !request_wake { phase_started = timer.get_ns() }',
		'rtk.state = .running'], 'Vinix uses elapsed-time phase budgets, discards stale AP state and requires exact ON')!
	require(transport.contains('const boot_phase_timeout_ns = u64(1_000_000_000)')
		&& transport.contains('[ep_crashlog, ep_syslog, ep_debug, ep_ioreport, ep_oslog, ep_tracekit]!'),
		'Vinix uses one-second phase deadlines and includes TraceKit in G13 endpoint startup')!
	require_order(boot, ['rtk.firmware_led_boot = !request_wake',
		'rtk.reply_boot_management(msg_hello_ack, payload, request_wake)',
		'rtk.reply_boot_management(msg_epmap_reply, reply, request_wake)', 'if !start_system_endpoints',
		'if !rtk.send_management(msg_set_ap_power, u64(power_state_on))',
		"return rtk.fail(c'failed to request AP power state')"], 'Vinix keeps endpoint starts and AP requests on their own failure paths')!
	reply := section(transport, 'fn (mut rtk RTKit) reply_boot_management(', 'fn (mut rtk RTKit) fail(', 'Vinix boot reply')!
	require_order(reply, ['if rtk.send_management(kind, payload)', 'if request_wake {', 'return false',
		'management reply type 0x%llx timed out', 'return true'], 'Vinix logs and continues past failed G13 discovery replies')!
	require(transport.contains('return rtk.firmware_led_boot && rtk.send_management(msg_start_ep, payload)'),
		'Vinix retries an unsent endpoint start only on the firmware-led transport')!
	check_rtkit_iop_confirmation(transport, linux, linux_boot, boot, start)!
	check_rtkit_mailbox_send(transport, asahi_linux, repo)!
}

fn check_rtkit_mailbox_send(transport string, asahi_linux string, repo string) ! {
	linux := read(os.join_path(asahi_linux, 'drivers/soc/apple/mailbox.c'))!
	require(linux.contains('#define APPLE_MBOX_TX_TIMEOUT 500\n'), 'Asahi ASC transmit gives the FIFO 500ms to make space')!
	send := section(linux, 'int apple_mbox_send(', 'EXPORT_SYMBOL(apple_mbox_send);', 'Asahi mailbox transmit')!
	require_order(send, ['while (mbox_ctrl & mbox->hw->control_full)', 'if (atomic || mbox->irq_send_empty < 0)',
		'readl_poll_timeout_atomic(', 'control_full), 100,', 'APPLE_MBOX_TX_TIMEOUT * 1000',
		'wait_for_completion_interruptible_timeout(', 'msecs_to_jiffies(APPLE_MBOX_TX_TIMEOUT)',
		'writeq_relaxed(msg.msg0', 'writeq_relaxed(FIELD_PREP(APPLE_MBOX_MSG1_MSG, msg.msg1)'],
		'Asahi has bounded polling and IRQ paths before publishing either mailbox word')!

	local := read(os.join_path(repo, 'kernel/apple/mailbox/mailbox.v'))!
	require(local.contains('const send_timeout_us = u64(500_000)') && local.contains('const send_poll_us = u64(100)'),
		'Vinix uses the Asahi ASC transmit duration and polling interval')!
	timed := section(local, 'pub fn (mut mbox Mailbox) send_timed(', '// Receive a message', 'Vinix timed mailbox transmit')!
	require_order(timed, ['mbox.try_send(msg)', 'started := timer.get_us()', 'elapsed := timer.get_us() - started',
		'elapsed >= send_timeout_us', 'remaining := send_timeout_us - elapsed', 'timer.busywait_us',
		'mbox.try_send(msg)', 'return false'], 'Vinix measures a fresh wait only when the FIFO is full')!
	try_send := section(local, 'fn (mut mbox Mailbox) try_send(msg', '// Use the polled ASC timeout', 'Vinix mailbox locking')!
	require_order(try_send, ['mbox.lock.acquire()', 'defer { mbox.lock.release() }', 'return mbox.try_send_locked(msg)'],
		'Vinix holds the lock for each mailbox attempt')!
	publish := section(local, 'fn (mbox &Mailbox) try_send_locked(', '// Send a message to the coprocessor', 'Vinix mailbox publication')!
	require_order(publish, ['mbox.read_reg(mbox_a2i_ctrl) & mbox_full != 0', 'return false',
		'cpu.dmb_sy()', 'mbox.write_reg64(mbox_a2i_send0, msg.data0)', 'mbox.write_reg64(mbox_a2i_send1, msg.data1)'],
		'Vinix checks FIFO space and orders shared writes before publishing a complete mailbox item')!
	management := section(transport, 'fn (mut rtk RTKit) send_management(', 'fn (mut rtk RTKit) send_start_endpoint(', 'Vinix RTKit management transmit')!
	require(management.contains('return rtk.send_message(ep_mgmt, management_message(kind, payload))'),
		'Vinix management and application traffic use the same transmit policy')!
	local_send := section(transport, 'pub fn (mut rtk RTKit) send_message(', 'pub fn (mut rtk RTKit) recv_msg(', 'Vinix RTKit transmit dispatch')!
	require_order(local_send, ['if rtk.firmware_led_boot {', 'return rtk.mbox.send_timed(message)', 'return rtk.mbox.send(message)'],
		'Vinix selects elapsed-time transmit only for firmware-led G13 RTKit')!
}

fn check_rtkit_iop_confirmation(transport string, linux string, linux_boot string, boot string, start string) ! {
	ack := section(linux, 'static void apple_rtkit_management_rx_iop_pwr_ack(', 'static void apple_rtkit_management_rx_ap_pwr_ack(', 'Asahi IOP ACK')!
	require_order(ack, ['rtk->iop_power_state = new_state;', 'complete_all(&rtk->iop_pwr_ack_completion);'],
		'Asahi stores the IOP state and completes its wait for every acknowledgement')!
	require(!linux_boot.contains('rtk->iop_power_state'), 'Asahi boot waits for ACK completion without checking the IOP state word')!
	running := section(linux, 'bool apple_rtkit_is_running(', 'EXPORT_SYMBOL_GPL(apple_rtkit_is_running);', 'Asahi running predicate')!
	require_order(running, ['if (rtk->crashed)', '(rtk->iop_power_state & 0xff) != APPLE_RTKIT_PWR_STATE_ON',
		'(rtk->ap_power_state & 0xff) != APPLE_RTKIT_PWR_STATE_ON'], 'Asahi application readiness requires both power low bytes and a live coprocessor')!
	send := section(linux, 'int apple_rtkit_send_message(', 'EXPORT_SYMBOL_GPL(apple_rtkit_send_message);', 'Asahi application send')!
	require(start.contains('endpoint >= APPLE_RTKIT_APP_ENDPOINT_START &&\n\t    !apple_rtkit_is_running(rtk)')
		&& send.contains('ep >= APPLE_RTKIT_APP_ENDPOINT_START &&\n\t    !apple_rtkit_is_running(rtk)'),
		'Asahi checks current application readiness at both start and send')!

	require_order(boot, ['mut iop_acknowledged := false', 'msg_iop_power_ack {',
		'rtk.iop_power_state = u16(msg.data0 & 0xffff)', 'iop_acknowledged = true',
		'iop_ready := if request_wake', '(rtk.iop_power_state & 0xff) == power_state_on',
		'iop_acknowledged', 'if endpoint_map_done && iop_ready && !ap_power_requested',
		'rtk.send_management(msg_set_ap_power, u64(power_state_on))',
		'if ap_power_requested && iop_ready', 'rtk.state = .running', 'rtk.refresh_application_ready()'],
		'Vinix G13 uses ACK receipt to advance boot and publishes current application readiness after AP acknowledgement')!
	refresh := section(transport, 'fn (mut rtk RTKit) refresh_application_ready(', '// Handle one RTKit transport message', 'Vinix readiness update')!
	require_order(refresh, ['katomic.store(mut rtk.application_ready, rtk.state == .running',
		'(rtk.iop_power_state & 0xff) == power_state_on', '(rtk.ap_power_state & 0xff) == power_state_on'],
		'Vinix publishes both ON predicates together')!
	local_start := section(transport, 'pub fn (mut rtk RTKit) start_endpoint(', '// Send a protocol-defined payload', 'Vinix application start')!
	local_send := section(transport, 'pub fn (mut rtk RTKit) send_message(', 'pub fn (mut rtk RTKit) recv_msg(', 'Vinix application send')!
	require_order(local_start, ['ep >= app_endpoint_start', 'katomic.load(&rtk.application_ready)',
		'if !ready', 'return false', 'rtk.send_start_endpoint(ep)'], 'Vinix checks readiness before starting application endpoints')!
	require_order(local_send, ['ep >= app_endpoint_start', '!katomic.load(&rtk.application_ready)',
		'return false', 'rtk.mbox.send'], 'Vinix checks readiness before application mailbox writes')!
}
