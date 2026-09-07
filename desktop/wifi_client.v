// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Native userspace client for the fixed-size /dev/wlan0 control ABI.
module main

const wifi_path = '/dev/wlan0'
const wifi_ioctl_status = u64(0x5700)
const wifi_ioctl_radio = u64(0x5705)
const wifi_ioctl_scan = u64(0x5706)
const wifi_ioctl_networks = u64(0x5707)
const wifi_status_size = 256
const wifi_network_max = 32
const wifi_network_entry_size = 48
const wifi_networks_size = 16 + wifi_network_max * wifi_network_entry_size
const wifi_retries = 4

enum WifiResult {
	ok
	unavailable
	permission
	not_ready
	disabled
	invalid
	io
}

struct WifiNetwork {
mut:
	ssid_len int
	ssid     [32]u8
	bssid    [6]u8
	secure   bool
	channel  int
	rssi     int
}

struct WifiState {
mut:
	driver_state int
	driver_error int
	radio_on     bool
	scanning     bool
	scan_error   int
	writable     bool
	count        int
	networks     [32]WifiNetwork
}

fn wifi_le16(bytes []u8, offset int) u16 {
	return u16(bytes[offset]) | (u16(bytes[offset + 1]) << 8)
}

fn wifi_le32(bytes []u8, offset int) u32 {
	return u32(bytes[offset]) | (u32(bytes[offset + 1]) << 8) | (u32(bytes[offset + 2]) << 16) | (u32(bytes[offset + 3]) << 24)
}

fn wifi_put32(mut bytes []u8, value u32) {
	for i in 0 .. 4 {
		bytes[i] = u8(value >> (i * 8))
	}
}

fn wifi_device_result(result DeviceError) WifiResult {
	return match result {
		.unavailable { .unavailable }
		.permission { .permission }
		else { .io }
	}
}

fn parse_wifi_status(bytes []u8, writable bool) ?WifiState {
	if bytes.len != wifi_status_size {
		return none
	}
	driver_state := int(wifi_le32(bytes, 0))
	radio := wifi_le32(bytes, 160)
	scanning := wifi_le32(bytes, 164)
	count := int(wifi_le32(bytes, 168))
	if driver_state < 0 || driver_state > 6 || radio > 1 || scanning > 1 || count < 0
		|| count > wifi_network_max {
		return none
	}
	return WifiState{
		driver_state: driver_state
		driver_error: int(i32(wifi_le32(bytes, 4)))
		radio_on: radio != 0
		scanning: scanning != 0
		scan_error: int(i32(wifi_le32(bytes, 172)))
		writable: writable
		count: count
	}
}

fn parse_wifi_networks(bytes []u8, mut state WifiState) bool {
	if bytes.len != wifi_networks_size || wifi_le32(bytes, 0) != 1 {
		return false
	}
	count := int(wifi_le32(bytes, 4))
	scanning := wifi_le32(bytes, 8)
	if count < 0 || count > wifi_network_max || scanning > 1 {
		return false
	}
	state.count = count
	state.scanning = scanning != 0
	state.scan_error = int(i32(wifi_le32(bytes, 12)))
	for i in 0 .. count {
		offset := 16 + i * wifi_network_entry_size
		ssid_len := int(bytes[offset])
		secure := bytes[offset + 1]
		channel := int(wifi_le16(bytes, offset + 2))
		rssi := int(i16(wifi_le16(bytes, offset + 4)))
		if ssid_len < 0 || ssid_len > 32 || secure > 1 || channel < 1 || channel > 233
			|| rssi < -127 || rssi > 0 {
			return false
		}
		mut network := WifiNetwork{
			ssid_len: ssid_len
			secure: secure != 0
			channel: channel
			rssi: rssi
		}
		for j in 0 .. 6 {
			network.bssid[j] = bytes[offset + 8 + j]
		}
		for j in 0 .. ssid_len {
			network.ssid[j] = bytes[offset + 16 + j]
		}
		state.networks[i] = network
	}
	return true
}

fn wifi_ioctl_with(mut io DeviceIO, fd int, request u64, mut buffer []u8) DeviceError {
	for _ in 0 .. wifi_retries {
		result := io.ioctl(fd, request, mut buffer)
		if result != .interrupted {
			return result
		}
	}
	return .io
}

fn open_wifi(mut io DeviceIO, writable_required bool) (int, bool, WifiResult) {
	mut writable := true
	mut fd, mut open_error := io.open(wifi_path, true)
	if fd < 0 && open_error == .permission && !writable_required {
		writable = false
		fd, open_error = io.open(wifi_path, false)
	}
	if fd < 0 {
		return -1, false, wifi_device_result(open_error)
	}
	character, stat_error := io.is_character(fd)
	if stat_error != .none || !character {
		io.close(fd)
		return -1, false, if stat_error == .none { WifiResult.invalid } else { WifiResult.io }
	}
	return fd, writable, WifiResult.ok
}

fn read_wifi_with(mut io DeviceIO, mut out WifiState) WifiResult {
	fd, writable, result := open_wifi(mut io, false)
	if result != .ok {
		return result
	}
	defer { io.close(fd) }
	mut status_storage := [wifi_status_size]u8{}
	mut status := unsafe { (&status_storage[0]).vbytes(status_storage.len) }
	status_error := wifi_ioctl_with(mut io, fd, wifi_ioctl_status, mut status)
	if status_error != .none {
		return wifi_device_result(status_error)
	}
	mut next := parse_wifi_status(status, writable) or { return .invalid }
	mut network_storage := [wifi_networks_size]u8{}
	mut networks := unsafe { (&network_storage[0]).vbytes(network_storage.len) }
	network_error := wifi_ioctl_with(mut io, fd, wifi_ioctl_networks, mut networks)
	if network_error != .none {
		return wifi_device_result(network_error)
	}
	if !parse_wifi_networks(networks, mut next) {
		return .invalid
	}
	out = next
	return .ok
}

enum WifiAction {
	radio_off
	radio_on
	scan
}

fn wifi_action_with(mut io DeviceIO, action WifiAction) WifiResult {
	fd, _, result := open_wifi(mut io, true)
	if result != .ok {
		return result
	}
	defer { io.close(fd) }
	mut status_storage := [wifi_status_size]u8{}
	mut status_bytes := unsafe { (&status_storage[0]).vbytes(status_storage.len) }
	status_error := wifi_ioctl_with(mut io, fd, wifi_ioctl_status, mut status_bytes)
	if status_error != .none {
		return wifi_device_result(status_error)
	}
	status := parse_wifi_status(status_bytes, true) or { return .invalid }
	if status.driver_state < 3 || status.driver_state > 5 {
		return .not_ready
	}
	match action {
		.radio_off, .radio_on {
			enabled := action == .radio_on
			if status.radio_on == enabled {
				return .ok
			}
			mut request := []u8{len: 4}
			wifi_put32(mut request, if enabled { u32(1) } else { u32(0) })
			radio_error := wifi_ioctl_with(mut io, fd, wifi_ioctl_radio, mut request)
			if radio_error != .none {
				return wifi_device_result(radio_error)
			}
		}
		.scan {
			if !status.radio_on {
				return .disabled
			}
			if status.scanning {
				return .ok
			}
			mut empty := []u8{}
			scan_error := wifi_ioctl_with(mut io, fd, wifi_ioctl_scan, mut empty)
			if scan_error != .none {
				return wifi_device_result(scan_error)
			}
		}
	}
	return .ok
}

fn read_wifi(mut out WifiState) WifiResult {
	mut io := PosixDeviceIO{}
	return read_wifi_with(mut io, mut out)
}

fn set_wifi_radio(enabled bool) WifiResult {
	mut io := PosixDeviceIO{}
	return wifi_action_with(mut io, if enabled { WifiAction.radio_on } else { WifiAction.radio_off })
}

fn scan_wifi() WifiResult {
	mut io := PosixDeviceIO{}
	return wifi_action_with(mut io, WifiAction.scan)
}
