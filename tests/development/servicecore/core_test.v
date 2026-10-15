// SPDX-License-Identifier: GPL-2.0-or-later
module servicecore

import desktop.sessioncore
import encoding.hex
import json2

fn lifecycle_proof() !Proof {
	unit := '[Service]\nType=simple\nExecStart="/usr/bin/vinix-jobs" watch "/home/developer/service-state"\n'
		+ 'Restart=on-failure\nRestartSec=1s\nTimeoutStopSec=10s\n'
	mut supervisor := sessioncore.Supervisor{count: 1}
	supervisor.services[0] = sessioncore.import_linux_service('vinix-jobs.service', unit, false)!
	disabled := hex.encode(supervisor.encode().bytes())
	supervisor.enable(0, true)!
	return Proof{schema: 1, uid: 1000, guardians: [10, 20, 30], watchers: [11, 21, 31],
		stop_millis: [u64(10), 20, 30], disabled: disabled, enabled: hex.encode(supervisor.encode().bytes()),
		removed: hex.encode('vinix-services\t1\n'.bytes())}
}

fn test_native_proof_requires_three_distinct_watchers_with_bounded_stops() {
	proof := lifecycle_proof()!
	verify(json2.encode(proof))!
	for changed in [Proof{...proof, uid: 0}, Proof{...proof, schema: 2},
		Proof{...proof, watchers: [11, 21]}, Proof{...proof, watchers: [11, 21, 11]},
		Proof{...proof, guardians: [10, 21, 30]}, Proof{...proof, guardians: [10, 1, 30]},
		Proof{...proof, stop_millis: [u64(10), 10000, 30]}] {
		if _ := verify(json2.encode(changed)) { assert false, 'incomplete service lifecycle accepted' }
	}
}

fn test_native_proof_requires_exact_enabled_disabled_and_removed_configuration() {
	proof := lifecycle_proof()!
	for changed in [Proof{...proof, enabled: proof.disabled}, Proof{...proof, disabled: proof.enabled},
		Proof{...proof, removed: proof.disabled}, Proof{...proof, enabled: 'bad hex'},
		Proof{...proof, disabled: hex.encode(hex.decode(proof.disabled)!.bytestr().replace('10000', '1000').bytes())}] {
		if _ := verify(json2.encode(changed)) { assert false, 'changed persisted service configuration accepted' }
	}
}
