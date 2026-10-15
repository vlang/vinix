// SPDX-License-Identifier: GPL-2.0-or-later
module servicecore

import crypto.sha256
import desktop.sessioncore
import encoding.hex
import json2
import os

pub struct Proof {
pub:
	schema int
	uid int
	guardians []int
	watchers []int
	stop_millis []u64
	enabled string
	disabled string
	removed string
}

// Prepared brokers are explicit inputs, copied and pinned before the guest
// starts. Qualification never substitutes a mock broker or bypasses its IPC.
pub fn stage(source string, root string, arch string) !string {
	bytes := os.read_bytes(source)!
	machine := if arch == 'aarch64' { u16(183) } else { u16(62) }
	if arch !in ['aarch64', 'x86_64'] || bytes.len < 20
		|| bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| (u16(bytes[18]) | (u16(bytes[19]) << 8)) != machine {
		return error('service broker needs a matching native ELF64 executable')
	}
	hash := sha256.sum(bytes).hex()
	path := root + '/usr/bin/vinix-desktop'
	os.write_file_array(path, bytes)!
	os.chmod(path, 0o755)!
	if sha256.sum(os.read_bytes(path)!).hex() != hash { return error('service broker copy changed') }
	return hash
}

pub fn verify(body string) ! {
	proof := json2.decode[Proof](body, strict: true)!
	if proof.schema != 1 || proof.uid != 1000 || proof.guardians.len != 3
		|| proof.watchers.len != 3 || proof.stop_millis.len != 3 {
		return error('invalid native service lifecycle proof')
	}
	mut seen := map[int]bool{}
	for i in 0 .. 3 {
		for pid in [proof.guardians[i], proof.watchers[i]] {
			if pid <= 1 || pid in seen { return error('service process identities were reused') }
			seen[pid] = true
		}
		if proof.stop_millis[i] >= 10000 { return error('service retirement exceeded the exported stop window') }
	}
	unit := '[Unit]\nDescription=Vinix scheduled jobs\n[Service]\nType=simple\n'
		+ 'ExecStart="/usr/bin/vinix-jobs" watch "/home/developer/service-state"\n'
		+ 'Restart=on-failure\nRestartSec=1s\nTimeoutStopSec=10s\n[Install]\nWantedBy=default.target\n'
	for enabled in [false, true] {
		mut supervisor := sessioncore.Supervisor{count: 1}
		supervisor.services[0] = sessioncore.import_linux_service('vinix-jobs.service', unit, enabled)!
		supervisor.validate()!
		record := hex.decode(if enabled { proof.enabled } else { proof.disabled })!.bytestr()
		if record != supervisor.encode() { return error('persisted scheduler service definition changed') }
	}
	if hex.decode(proof.removed)!.bytestr() != 'vinix-services\t1\n' {
		return error('service removal left a persistent definition')
	}
}
