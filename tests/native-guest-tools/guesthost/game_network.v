// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import hosttest
import os
import policyhost
import time

fn C.mkdtemp(&char) &char

pub struct GameNetwork {
pub:
	socket string
mut:
	pid    i32
	master i32 = -1
	work   string
	closed bool
}

// KekVM's GPU bottle has no slirp. Keep the original stream/hub backend
// in a separate, owned stock QEMU, retiring its process group on every path.
pub fn game_network(qemu string, env map[string]string, log_path string) !&GameNetwork {
	mut template := '/tmp/vinix-game-net-XXXXXX'.bytes()
	template << u8(0)
	if isnil(C.mkdtemp(unsafe { &char(template.data) })) { return posix_error() }
	work := template[..template.len - 1].bytestr()
	socket := work + '/net.sock'
	pid, master := spawn_guest([qemu, '-machine', 'none', '-nodefaults', '-display', 'none', '-monitor',
		'none', '-netdev', 'user,id=slirp', '-netdev',
		'stream,id=link,server=on,addr.type=unix,addr.path=' + socket, '-netdev',
		'hubport,id=slirp_hub,hubid=0,netdev=slirp', '-netdev',
		'hubport,id=link_hub,hubid=0,netdev=link'], env) or {
		hosttest.remove_work_dir(work) or {}
		return err
	}
	mut owner := &GameNetwork{ socket: socket, pid: pid, master: master, work: work }
	mut log := os.create(log_path) or {
		owner.close()
		return err
	}
	defer { log.close() }
	for _ in 0 .. 20 {
		policyhost.command_checkpoint() or {
			owner.close()
			return err
		}
		mut bytes := [8192]u8{}
		count := C.read(master, &bytes[0], bytes.len)
		if count > 0 {
			session_log(mut log, bytes[..count]) or {
				owner.close()
				return err
			}
		}
		if os.exists(socket) { return owner }
		time.sleep(50 * time.millisecond)
	}
	owner.close()
	return error('QEMU network bridge did not start; see ' + log_path)
}

pub fn (mut owner GameNetwork) close() {
	if owner.closed { return }
	owner.closed = true
	if owner.master >= 0 {
		// A capture may have left an interrupt pending; cleanup still owns and
		// reaps this helper even if its normal graceful path is interrupted.
		session_stop(owner.pid, owner.master, false, SessionPolicy{ cleanup_wait: 0, term_wait: 2, kill_wait: 2 }) or {
			C.killpg(owner.pid, C.SIGKILL)
			C.kill(owner.pid, C.SIGKILL)
			wait(owner.pid, false) or {}
		}
		C.close(owner.master)
		owner.master = -1
	}
	hosttest.remove_work_dir(owner.work) or { eprintln(err.msg()) }
}
