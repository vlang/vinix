// SPDX-License-Identifier: ISC
@[translated]
module protocolfixture

fn test_nvram_golden() {
	unsafe {
		mut output := [64]u8{}
		mut length := usize(0)
		C.assert(C.bw_nvram_pack(&u8(c' # hi\r\n a=1\n b=two # comment'), 27, &output[0], sizeof(output), &length) == 0)
		C.assert(length == 16)
		C.assert(C.memcmp(&output[0], c'a=1\x00\x62=two\x00\x00\x00', 12) == 0)
		C.assert(le32(&output[12]) == 0xfffc0003)
	}
}

fn test_nvram_reject() {
	unsafe {
		mut output := [64]u8{}
		mut length := usize(0)
		C.assert(C.bw_nvram_pack(&u8(c'a=1\na=2'), 7, &output[0], 64, &length) == i32(C.BW_EINVAL))
		C.assert(C.bw_nvram_pack(&u8(c'=x'), 2, &output[0], 64, &length) == i32(C.BW_EINVAL))
		C.assert(C.bw_nvram_pack(&u8(c'a=123'), 5, &output[0], 8, &length) == i32(C.BW_ENOSPC))
		bad := [u8(97), u8(61), u8(0)]!
		C.assert(C.bw_nvram_pack(&bad[0], 3, &output[0], 64, &length) == i32(C.BW_EINVAL))
	}
}

fn test_otp() {
	unsafe {
		fake := fixture()
		C.assert(C.bw_probe(fake.device) == 0)
		C.assert(C.strcmp(&fake.device.otp.@module[0], c'module') == 0)
		C.assert(fake.device.revision == 3 && fake.device.pcie_revision == 64 && fake.device.state == i32(C.BW_CHIP))
		destroy(fake)
	}
}

fn test_otp_bounds() {
	unsafe {
		bytes := [u8(0x15), u8(255), u8(8)]!
		mut otp := C.bw_otp{}
		C.assert(C.bw_otp_parse(&bytes[0], sizeof(bytes), &otp) == i32(C.BW_EPROTO))
		C.assert(C.bw_otp_parse(nil, 0, &otp) == i32(C.BW_EINVAL))
	}
}

fn test_device_gate() {
	unsafe {
		fake := fixture()
		fake.cfg[0] = 0x123414e4
		C.assert(C.bw_probe(fake.device) == i32(C.BW_ENOTSUP))
		C.assert(fake.stopped == 0)
		destroy(fake)
	}
}

fn test_bad_erom() {
	unsafe {
		fake := fixture()
		w32(fake.bp + 0xfc, 0xffffffff)
		C.assert(C.bw_probe(fake.device) == i32(C.BW_EPROTO))
		destroy(fake)
	}
}

fn test_probe_revision() {
	unsafe {
		fake := fixture()
		w32(fake.bp, 0x100f4378)
		C.assert(C.bw_probe(fake.device) == i32(C.BW_ENOTSUP))
		destroy(fake)
	}
}

fn test_boot_and_rings() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		C.assert(fake.device.state == i32(C.BW_READY) && fake.rx_n == 255 && fake.event_n == 8 && fake.ctl_n == 8)
		C.assert(fake.device.allocated < u32(C.BW_POOL_MIN) && fake.commands >= 9 && fake.syncs > 100)
		C.assert(fake.device.rings[3].item == 24 && fake.device.rings[4].item == 40)
		destroy(fake)
	}
}

fn test_firmware_timeout() {
	unsafe {
		fake := fixture()
		fake.boot_timeout = 1
		C.assert(start(fake) == i32(C.BW_ETIME))
		C.assert(fake.stopped == 1 && fake.device.state == i32(C.BW_FAULT) && fake.time < 6000000)
		destroy(fake)
	}
}

fn test_shared_pointer() {
	unsafe {
		fake := fixture()
		fake.bad_shared = 1
		C.assert(start(fake) == i32(C.BW_EPROTO) && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_protocol_version() {
	unsafe {
		fake := fixture()
		fake.version = 8
		C.assert(start(fake) == i32(C.BW_ENOTSUP) && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_ioctl_timeout() {
	unsafe {
		fake := fixture()
		fake.no_reply = 1
		C.assert(start(fake) == i32(C.BW_ETIME) && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_ack_required() {
	unsafe {
		fake := fixture()
		fake.no_ack = 1
		C.assert(start(fake) == i32(C.BW_ETIME) && fake.device.request_busy != 0 && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_wpa2_authorization() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		join(fake)
		C.assert(fake.device.state == i32(C.BW_LINK) && fake.device.associated != 0 && fake.device.keyed != 0)
		zero := [8192]u8{}
		C.assert(C.memcmp(fake.device.request.cpu, &zero[0], u32(C.BW_CTL_SIZE)) == 0)
		destroy(fake)
	}
}

fn test_assoc_not_authorized() {
	unsafe {
		fake := fixture()
		fake.withhold_key = 1
		C.assert(start(fake) == 0)
		join(fake)
		C.assert(fake.device.associated != 0 && fake.device.keyed == 0 && fake.device.state == i32(C.BW_JOINING))
		mut packet := [60]u8{}
		frame(&packet[0])
		C.assert(C.bw_transmit(fake.device, &packet[0], 60) == i32(C.BW_ENOLINK))
		inject_rx(fake, 0)
		C.assert(C.bw_poll(fake.device, 64) >= 0 && fake.received == 0)
		fake.time += 31000000
		C.assert(C.bw_poll(fake.device, 64) == i32(C.BW_ETIME))
		destroy(fake)
	}
}

fn test_unsupported_supplicant() {
	unsafe {
		fake := fixture()
		fake.unsupported_supplicant = 1
		C.assert(start(fake) == 0)
		C.assert(C.bw_join_wpa2(fake.device, &u8(c'test'), 4, &u8(c'correct-pass'), 12) == i32(C.BW_EIO) && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_receive() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		join(fake)
		inject_rx(fake, 0)
		C.assert(C.bw_poll(fake.device, 64) >= 0 && fake.received == 1 && fake.rx_n == 255)
		destroy(fake)
	}
}

fn test_rx_bounds() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		join(fake)
		inject_rx(fake, 1)
		C.assert(C.bw_poll(fake.device, 64) == i32(C.BW_EPROTO) && fake.received == 0 && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_tx_flow() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		join(fake)
		mut packet := [60]u8{}
		frame(&packet[0])
		C.assert(C.bw_transmit(fake.device, &packet[0], 60) == i32(C.BW_ENOSPC))
		C.assert(C.bw_poll(fake.device, 64) >= 0 && fake.device.flow_open != 0)
		C.assert(C.bw_transmit(fake.device, &packet[0], 60) == 0)
		C.assert(C.bw_poll(fake.device, 64) >= 0 && fake.tx == 1 && fake.device.tx_frames == 1)
		packet[6] = 4
		C.assert(C.bw_transmit(fake.device, &packet[0], 60) == i32(C.BW_EINVAL))
		destroy(fake)
	}
}

fn test_bad_index() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		w16(dma(fake, fake.indices[2], 2), 65535)
		C.assert(C.bw_poll(fake.device, 64) == i32(C.BW_EPROTO) && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_unknown_packet_id() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		mut message := [40]u8{}
		message[0] = 0x12
		w32(&message[4], 0xdeadbeef)
		finish(fake, 2, &message[0], 32)
		C.assert(C.bw_poll(fake.device, 64) == i32(C.BW_EPROTO))
		destroy(fake)
	}
}

fn test_bad_credentials() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		C.assert(C.bw_join_wpa2(fake.device, &u8(c'test'), 33, &u8(c'123'), 3) == i32(C.BW_EINVAL) && fake.device.state == i32(C.BW_READY))
		destroy(fake)
	}
}

fn test_radio_and_scan() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0 && fake.device.radio_on != 0 && fake.radio_up == 1)
		C.assert(C.bw_scan(fake.device) == 0 && fake.scans == 1 && fake.device.scan_pending == 0 && fake.device.network_count == 2)
		mut output := [1552]u8{}
		C.assert(C.bw_networks(fake.device, &output[0], sizeof(output)) == 0)
		C.assert(le32(&output[0]) == 1 && le32(&output[4]) == 2 && le32(&output[8]) == 0 && le32(&output[12]) == 0)
		C.assert(output[16] == 5 && output[17] == 1 && le16(&output[18]) == 44 && i16(le16(&output[20])) == -42 && C.memcmp(&output[32], c'Vinix', 5) == 0)
		C.assert(output[64] == 5 && output[65] == 0 && le16(&output[66]) == 6)
		C.assert(C.bw_radio(fake.device, 0) == 0 && fake.device.radio_on == 0 && fake.radio_down == 1 && C.bw_scan(fake.device) == i32(C.BW_EINVAL))
		C.assert(C.bw_radio(fake.device, 1) == 0 && fake.device.radio_on != 0 && fake.radio_up == 2)
		destroy(fake)
	}
}

fn test_scan_bounds() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		fake.malformed_scan = 1
		C.assert(C.bw_scan(fake.device) == i32(C.BW_EPROTO) && fake.device.state == i32(C.BW_FAULT) && fake.device.radio_on == 0 && fake.device.scan_pending == 0 && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_link_loss() {
	unsafe {
		fake := fixture()
		C.assert(start(fake) == 0)
		join(fake)
		send_event(fake, 16, 0, 0)
		C.assert(C.bw_poll(fake.device, 64) == i32(C.BW_ENOLINK) && fake.stopped == 1)
		destroy(fake)
	}
}

fn test_parser_mutations() {
	unsafe {
		mut rng := u32(0x98765432)
		mut bytes := [1024]u8{}
		mut output := [2048]u8{}
		mut otp := C.bw_otp{}
		mut used := usize(0)
		for iteration := u32(0); iteration < 100000; iteration++ {
			rng ^= rng << 13
			rng ^= rng >> 17
			rng ^= rng << 5
			length := usize(rng) % sizeof(bytes)
			for i := usize(0); i < length; i++ {
				rng ^= rng << 13
				rng ^= rng >> 17
				rng ^= rng << 5
				bytes[i] = u8(rng)
			}
			C.bw_nvram_pack(&bytes[0], length, &output[0], sizeof(output), &used)
			C.bw_otp_parse(&bytes[0], length, &otp)
		}
	}
}

@[export:'wifi_protocol_main']
pub fn fixture_main() i32 {
	unsafe {
		test_nvram_golden()
		protocol_tests++
		C.printf(c'PASS test_nvram_golden\n')
		test_nvram_reject()
		protocol_tests++
		C.printf(c'PASS test_nvram_reject\n')
		test_otp()
		protocol_tests++
		C.printf(c'PASS test_otp\n')
		test_otp_bounds()
		protocol_tests++
		C.printf(c'PASS test_otp_bounds\n')
		test_device_gate()
		protocol_tests++
		C.printf(c'PASS test_device_gate\n')
		test_bad_erom()
		protocol_tests++
		C.printf(c'PASS test_bad_erom\n')
		test_probe_revision()
		protocol_tests++
		C.printf(c'PASS test_probe_revision\n')
		test_boot_and_rings()
		protocol_tests++
		C.printf(c'PASS test_boot_and_rings\n')
		test_firmware_timeout()
		protocol_tests++
		C.printf(c'PASS test_firmware_timeout\n')
		test_shared_pointer()
		protocol_tests++
		C.printf(c'PASS test_shared_pointer\n')
		test_protocol_version()
		protocol_tests++
		C.printf(c'PASS test_protocol_version\n')
		test_ioctl_timeout()
		protocol_tests++
		C.printf(c'PASS test_ioctl_timeout\n')
		test_ack_required()
		protocol_tests++
		C.printf(c'PASS test_ack_required\n')
		test_wpa2_authorization()
		protocol_tests++
		C.printf(c'PASS test_wpa2_authorization\n')
		test_assoc_not_authorized()
		protocol_tests++
		C.printf(c'PASS test_assoc_not_authorized\n')
		test_unsupported_supplicant()
		protocol_tests++
		C.printf(c'PASS test_unsupported_supplicant\n')
		test_receive()
		protocol_tests++
		C.printf(c'PASS test_receive\n')
		test_rx_bounds()
		protocol_tests++
		C.printf(c'PASS test_rx_bounds\n')
		test_tx_flow()
		protocol_tests++
		C.printf(c'PASS test_tx_flow\n')
		test_bad_index()
		protocol_tests++
		C.printf(c'PASS test_bad_index\n')
		test_unknown_packet_id()
		protocol_tests++
		C.printf(c'PASS test_unknown_packet_id\n')
		test_bad_credentials()
		protocol_tests++
		C.printf(c'PASS test_bad_credentials\n')
		test_radio_and_scan()
		protocol_tests++
		C.printf(c'PASS test_radio_and_scan\n')
		test_scan_bounds()
		protocol_tests++
		C.printf(c'PASS test_scan_bounds\n')
		test_link_loss()
		protocol_tests++
		C.printf(c'PASS test_link_loss\n')
		test_parser_mutations()
		protocol_tests++
		C.printf(c'PASS test_parser_mutations\n')
		C.printf(c'%u groups passed; 100000 parser mutations\n', protocol_tests)
		return 0
	}
}
