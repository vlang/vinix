// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <sys/mount.h>
#include <unistd.h>
fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount(&char) int
fn C.sync()

struct PackageResult {
 phase string
 device string
 root string
 previous_version string
 current_version string
 installed bool
 reopened bool
 upgraded bool
 removed bool
 unmounted bool
}

fn mount_package_store(device string, directory string) ! {
 $if linux {
  if unsafe { C.mount(device.str, directory.str, c'ext2', 0, nil) } != 0 {
   return error('package-store ext2 mount failed: ' + os.last_error().msg())
  }
 } $else { return error('unsupported: package transactions require a Vinix guest disk') }
}

fn unmount_package_store(directory string) ! {
 $if linux {
  C.sync()
  if unsafe { C.umount(directory.str) } != 0 {
   return error('package-store unmount failed: ' + os.last_error().msg())
  }
 } $else { return error('unsupported: package transactions require a Vinix guest disk') }
}

fn (mut suite Suite) package_lifecycle() ! {
 if suite.path.starts_with('translated-') || suite.data_device == '' {
  return error('unsupported: package transactions require a native guest and an explicit private ext2 disk')
 }
 store := '/mnt/linux-compat-packages'
 root := store + '/root'
 os.mkdir_all(store)!
 mount_package_store(suite.data_device, store)!
 mut mounted := true
 mut result := PackageResult{device: suite.data_device, root: root}
 defer {
  if mounted {
   unmount_package_store(store) or { eprintln(err.msg()) }
  }
 }
 suite.execute('busybox', ['--install', '-s', '/bin'])!
 suite.environment['VINIX_PKG_ROOT'] = root
 suite.environment['VINIX_PKG_NETWORK_RETRIES'] = '1'
 suite.environment['VINIX_PKG_NETWORK_WAIT_SECONDS'] = '0'
 suite.environment['VINIX_PKG_NETWORK_RETRY_DELAY'] = '0'
 repos := '/usr/share/linux-compat-repos/'
 marker := store + '/installed.version'
 if !os.exists(marker) {
  result = PackageResult{phase: 'install', device: suite.data_device, root: root}
  for directory in ['etc/apk/keys', 'etc/vinix-pkg', 'var/cache/apk', 'var/lib/vinix-pkg', 'data'] {
   os.mkdir_all(root + '/' + directory)!
  }
  expect(!os.exists(root + '/usr/bin/sqlite3'), 'installation needs a target without SQLite')!
  // APK resolves local repository paths relative to its --root. Keep both
  // unchanged signed mirrors on the test disk, so reboot/update stay offline.
  for version in ['v3.20', 'v3.21'] {
   arch := if suite.path == 'native-aarch64' { 'aarch64' } else { 'x86_64' }
   os.mkdir_all(root + repos + version + '/' + arch)!
   for name in os.ls(repos + version + '/' + arch)! {
    os.cp(repos + version + '/' + arch + '/' + name, root + repos + version + '/' + arch + '/' + name)!
   }
  }
  for name in os.ls('/etc/apk/keys')! {
   if os.is_file('/etc/apk/keys/' + name) { os.cp('/etc/apk/keys/' + name, root + '/etc/apk/keys/' + name)! }
  }
  os.write_file(root + '/etc/apk/repositories', repos + 'v3.20\n')!
  os.write_file(root + '/etc/vinix-pkg/base-world', 'musl\n')!
  // The selected repository is local/offline. The existing frontend checks
  // for a configured resolver before transactions; it never contacts this one.
  os.write_file(root + '/etc/resolv.conf', 'nameserver 127.0.0.1\n')!
  suite.execute('/sbin/apk', ['--root', root, '--initdb', '--no-network', 'add'])!
  suite.execute('/usr/bin/pkg', ['install', 'sqlite'])!
  version := suite.execute('busybox', ['chroot', root, '/usr/bin/sqlite3', '--version'])!
  expected := os.read_file(repos + 'v3.20/sqlite.version')!.trim_space().all_before('-r')
  expect(version.starts_with(expected + ' '), 'installed SQLite did not match the older signed repository')!
  result = PackageResult{phase: 'install', device: suite.data_device, root: root, current_version: expected, installed: true}
  data := suite.execute('busybox', ['chroot', root, '/usr/bin/sqlite3', '-batch', '/data/saved.db',
   'PRAGMA journal_mode=WAL; CREATE TABLE t(v INTEGER); INSERT INTO t VALUES(42); SELECT sum(v) FROM t;'])!
  expect(data.trim_space() == 'wal\n42', 'installed SQLite did not commit saved data')!
  os.write_file(marker, expected + '\n')!
 } else {
  previous := os.read_file(marker)!.trim_space()
  result = PackageResult{phase: 'upgrade-remove', device: suite.data_device, root: root, previous_version: previous}
  before := suite.execute('busybox', ['chroot', root, '/usr/bin/sqlite3', '--version'])!
  expect(before.starts_with(previous + ' '), 'installed version did not survive the guest reboot')!
  reopened := suite.execute('busybox', ['chroot', root, '/usr/bin/sqlite3', '-batch', '/data/saved.db',
   'PRAGMA integrity_check; SELECT sum(v) FROM t;'])!
  expect(reopened.trim_space() == 'ok\n42', 'saved database did not survive the guest reboot')!
  os.write_file(root + '/etc/apk/repositories', repos + 'v3.21\n')!
  suite.execute('/usr/bin/pkg', ['update'])!
  suite.execute('/usr/bin/pkg', ['upgrade'])!
  expected := os.read_file(repos + 'v3.21/sqlite.version')!.trim_space().all_before('-r')
  expect(expected != previous, 'upgrade inputs must contain a real new SQLite version')!
  after := suite.execute('busybox', ['chroot', root, '/usr/bin/sqlite3', '--version'])!
  expect(after.starts_with(expected + ' '), 'APK upgrade did not replace SQLite with the newer version')!
  data := suite.execute('busybox', ['chroot', root, '/usr/bin/sqlite3', '-batch', '/data/saved.db',
   'PRAGMA integrity_check; SELECT sum(v) FROM t;'])!
  expect(data.trim_space() == 'ok\n42', 'upgrade damaged the saved database')!
  suite.execute('/usr/bin/pkg', ['remove', 'sqlite'])!
  expect(!os.exists(root + '/usr/bin/sqlite3') && os.exists(root + '/data/saved.db'), 'package removal did not preserve user data and remove the executable')!
  installed := suite.execute('/sbin/apk', ['--root', root, 'info'])!
  expect('sqlite' !in installed.split_into_lines() && 'musl' in installed.split_into_lines(), 'package removal left SQLite registered or removed the base runtime')!
  result = PackageResult{phase: 'upgrade-remove', device: suite.data_device, root: root,
   previous_version: previous, current_version: expected, installed: true, reopened: true, upgraded: true, removed: true}
 }
 unmount_package_store(store)!
 mounted = false
 suite.packages << PackageResult{...result, unmounted: true}
}
