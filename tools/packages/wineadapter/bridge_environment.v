// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

// Before setting the signed runtime paths and executing its loader. Call only
// in the launching process, with no concurrent environment mutation. A top-level
// entry must discover its own server; nested aliases preserve Wine's descriptor
// handoff byte-for-byte. Never interpret or close an inherited FD number here.
pub fn clear_bridge_overrides(mode string) ! {
	if mode !in ['wine-runner', 'wine', 'wine64', 'wineserver'] { return error('unknown Wine adapter mode') }
	if mode == 'wine-runner' && os.unsetenv('WINESERVERSOCKET') != 0 {
		return error('cannot clear inherited Wine server socket')
	}
	for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV', 'QEMU_UNSET_ENV', 'VINIX_ALLOW_WX', 'WINEDLLOVERRIDES', 'WINEDEBUG']! {
		if os.unsetenv(key) != 0 { return error('cannot clear inherited Wine override ' + key) }
	}
}
