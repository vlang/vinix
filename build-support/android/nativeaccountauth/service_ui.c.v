// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

// The dedicated UI control socket carries root-authorized SCM_RIGHTS only.
// Keep it protected through identity drop and APK extraction; native-entry
// independently checks the root peer and restores CLOEXEC before loading ART.
pub fn protect_ui_channel(fd int) ! {
	if fd < 3 { return error('UI control requires a private descriptor') }
	peer := peer_credentials(fd)!
	if peer.uid != 0 || peer.gid != 0 { return error('UI control requires a Unix root peer') }
	flags := C.fcntl(i32(fd), C.F_GETFD)
	if flags < 0 || C.fcntl(i32(fd), C.F_SETFD, flags | C.FD_CLOEXEC) != 0 {
		return error('cannot protect UI control descriptor')
	}
}

pub fn inherit_ui_channel(fd int) ! {
	protect_ui_channel(fd)!
	flags := C.fcntl(i32(fd), C.F_GETFD)
	if flags < 0 || C.fcntl(i32(fd), C.F_SETFD, flags & ~C.FD_CLOEXEC) != 0 {
		return error('cannot preserve UI control descriptor')
	}
}
