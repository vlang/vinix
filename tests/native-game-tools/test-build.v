// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidrun
import androidhost as ah
import cachecli
import gamehost
import hosttest
import os
import sourcecommand
import sync
import tarcore
import tarstream

#include <fcntl.h>
fn C.link(&char, &char) int
fn C.getdtablesize() int

struct BuildFixture {
mut:
 mutex sync.Mutex
 root string
 fixture string
 commands [][]string
 fail string
}

struct PoolFixture {
mut:
 mutex sync.Mutex
 active int
 peak int
 completed int
}

fn pool_fixture(argv []string, _ bool, pointer voidptr) !sourcecommand.Output {
 mut fixture := unsafe { &PoolFixture(pointer) }
 fixture.mutex.lock(); fixture.active++; if fixture.active > fixture.peak { fixture.peak = fixture.active }; fixture.mutex.unlock()
 gamehost.pause(0.08)!
 fixture.mutex.lock(); fixture.active--; fixture.completed++; fixture.mutex.unlock()
 if argv[5].ends_with('/1.apk.part') || argv[5].ends_with('/8.apk.part') { return error('failure: ' + argv[5]) }
 os.write_file(argv[5],'download')!
 return sourcecommand.Output{}
}

fn pool_cases(work string) ! {
 gamehost.mkdir(work + '/pool')!
 mut fixture := PoolFixture{}
 tools := gamehost.Tools{command_hook:pool_fixture,context:&fixture}
 mut lines := []string{}
 for index in 0 .. 12 { lines << 'main\t${index}.apk' }
 mut refused := false
 tools.fetch_archives(work + '/pool',lines) or { refused = true; assert err.msg().ends_with('/1.apk.part') }
 assert refused && fixture.completed == 12 && fixture.active == 0 && fixture.peak == 6
}

fn archive_fixture(destination string, entries map[string]string) ! {
 mut tar := tarcore.create_gzip(destination)!; defer { tar.close() }
 for name, data in entries { tar.add(tarcore.Member{name:name,size:data.len},data.bytes())! }
 tar.finish()!; tar.close_checked()!
}

fn compiler_fixture(argv []string, _ bool, pointer voidptr) !sourcecommand.Output {
 mut fixture := unsafe { &BuildFixture(pointer) }
 fixture.mutex.lock(); defer { fixture.mutex.unlock() }
 fixture.commands << argv.clone()
 command := argv[0].all_after_last('/')
 if fixture.fail == command { return sourcecommand.Output{status:19} }
 if command == 'curl' {
  target := argv[5]; url := argv[6]
  original := if url.contains('APKINDEX') { if url.contains('/main/') { 'main-index.tar.gz' } else { 'community-index.tar.gz' } } else { 'package.apk' }
  os.cp(gamehost.path(fixture.fixture,original),target)!
 } else if command == 'git' {
  if argv[1] == 'clone' {
   directory := argv.last(); gamehost.mkdir(directory)!
   if directory.ends_with('/source') { os.write_file(directory + '/CMakeLists.txt','original\n')!; gamehost.mkdir(directory + '/lib/Tempest')! }
  } else if 'rev-parse' in argv { return sourcecommand.Output{stdout:if argv[2].ends_with('/source') { gamehost.engine_commit + '\n' } else { gamehost.headers_commit + '\n' }} }
 } else if command == 'alpine-resolve' {
  assert argv[1..] == ['--index','main',fixture.root + '/downloads/main-index','--index','community',fixture.root + '/downloads/community-index','mesa-vulkan-swrast','vulkan-loader','libx11','libxcursor','libstdc++']
  return sourcecommand.Output{stdout:'main\truntime-1.apk\n'}
 } else if command == 'tar' {
  assert argv[1..3] == ['--ignore-zeros','-xzf']
  // Use the same real system archive reader, with an inherited stderr stream.
  result := sourcecommand.run_preferred(argv,os.environ(),cachecli.cancelled,'')!
  assert result.status == 0
 } else if command == 'compile-v-module' {
  assert argv[3..] == ['--arch','arm64','--header',fixture.root + '/sysroot/usr/include/execinfo.h']
  os.write_file(argv[2],'/* native fixture */\n')!
 } else if command == 'aarch64-linux-musl-gcc' {
  assert argv[1..7] == ['-D_GNU_SOURCE','-D__V_HAVE_EXECINFO_H=1','-O2','-c',fixture.root + '/execinfo.c','-o']
  os.write_file(argv.last(),'object')!
 } else if command == 'aarch64-linux-musl-ar' { os.write_file(argv[2],'archive')! }
 else if command == 'cmake' && argv[1] == '--build' {
  assert argv == ['cmake','--build',fixture.root + '/cmake','--target','Gothic2Notr','-j','8']
  gamehost.mkdir(fixture.root + '/cmake/opengothic')!
  os.write_file(fixture.root + '/cmake/opengothic/Gothic2Notr','engine')!
 } else if command == 'cmake' {
  assert argv[1..9] == ['-S',fixture.root + '/source','-B',fixture.root + '/cmake','-G','Ninja','-DCMAKE_SYSTEM_NAME=Linux','-DCMAKE_SYSTEM_PROCESSOR=aarch64']
  for flag in ['-DCMAKE_BUILD_TYPE=Release','-DCMAKE_POLICY_VERSION_MINIMUM=3.5','-DGLSLANGVALIDATOR=/fixture/glslang','-DCMAKE_C_COMPILER=aarch64-linux-musl-gcc','-DCMAKE_CXX_COMPILER=aarch64-linux-musl-g++','-DCMAKE_EXE_LINKER_FLAGS=-L${fixture.root}/sysroot/usr/lib -Wl,--allow-shlib-undefined','-DCMAKE_C_FLAGS=-I${fixture.root}/sysroot/usr/include','-DALSOFT_BACKEND_ALSA=OFF','-DALSOFT_BACKEND_PULSEAUDIO=OFF','-DALSOFT_BACKEND_JACK=OFF','-DALSOFT_BACKEND_PIPEWIRE=OFF','-DALSOFT_BACKEND_OSS=OFF'] { assert flag in argv }
  assert '-DCMAKE_CXX_FLAGS=-I${fixture.root}/sysroot/usr/include -I${fixture.root}/vulkan-headers/include -fno-omit-frame-pointer -Wno-error=stringop-overflow' in argv
 } else { return error('unexpected fixture command: ' + hosttest.shell_join(argv)) }
 return sourcecommand.Output{}
}

fn build_cases(root string, work string) ! {
 gamehost.mkdir(work)!
 names := ['vulkan-loader-dev','libx11-dev','libxcursor-dev','libxfixes-dev','libxrender-dev','xorgproto']
 index := names.map('P:' + it + '\nV:1\n').join('\n')
 archive_fixture(work + '/main-index.tar.gz',{'APKINDEX':index})!
 archive_fixture(work + '/community-index.tar.gz',{'APKINDEX':''})!
 archive_fixture(work + '/package.apk',{'usr/lib/libvulkan_lvp.so':'vulkan','usr/lib/libX11.so.6':'x11','usr/share/vulkan/icd.d/lvp_icd.aarch64.json':'{"ICD":{"library_path":"/usr/lib/libvulkan_lvp.so","api_version":"1.3"},"file_format_version":"1.0.0"}'})!
 os.setenv('GLSLANGVALIDATOR','/fixture/glslang',true)
 for mode in ['complete','compiler-failure'] {
  directory := work + '/' + mode
  os.setenv('VINIX_OPENGOTHIC_BUILD_DIR',directory,true)
  mut fixture := BuildFixture{root:directory,fixture:work,fail:if mode == 'complete' { '' } else { 'cmake' }}
  tools := gamehost.Tools{root:root,command_hook:compiler_fixture,context:&fixture}
  mut refused := false
  tools.build(false,'') or { refused = true; assert err.msg().contains('19') }
  assert refused == (mode != 'complete')
  assert os.read_file(directory + '/packages.tsv')! == 'main\truntime-1.apk\n'
  assert os.is_file(directory + '/sysroot/usr/lib/libX11.so.6')
  assert os.is_file(directory + '/runtime/usr/lib/libvulkan_lvp.so')
  if !refused {
   staged := directory + '/staging'
   assert os.read_file(staged + '/opt/opengothic/Gothic2Notr')! == 'engine'
   assert os.stat(staged + '/usr/bin/run-opengothic')!.mode & 0o777 == 0o755
   icd := androidrun.load_json(os.read_file(staged + '/opt/opengothic/icd/lvp.json')!)!.object()
   assert ah.field(ah.field(icd,'ICD').object(),'library_path').text() == '/opt/opengothic/lib/libvulkan_lvp.so'
   assert os.read_file(staged + '/opt/opengothic/SOURCES.txt')! == 'OpenGothic 26b7159230834780fc6a8fc9aa0d060863cb443f\nVulkan-Headers 3c65a01745e4a1134d32b9c2c456472212dba16d\nMesa 24.2.8 / LLVM 19.1.4 (Alpine 3.21)\n'
   tools.build(false,'')!
   assert os.read_file(directory + '/source/CMakeLists.txt')!.count('# Vinix execinfo compatibility') == 1
  } else { assert !os.exists(directory + '/staging/opt/opengothic/Gothic2Notr') }
  os.write_file(directory + '/commands.json',androidrun.dump_json(ah.Value(fixture.commands.map(ah.Value(it.map(ah.Value(it))))),2))!
 }
}

fn tree_cases(work string) ! {
 installation := work + '/installation'
 for name in ['dAtA','_WoRk/dAtA','_WoRk/Video','sYsTeM'] { gamehost.mkdir(installation + '/' + name)!; os.write_file(installation + '/' + name + '/file','original:' + name)! }
 os.write_file(installation + '/_WoRk/settings','settings')!
 os.symlink('file',installation + '/dAtA/copied-link')!
 os.chmod(installation + '/dAtA/file',0o751)!
 os.utime(installation + '/dAtA/file',1700000000,1700000001)!
 destination := work + '/game'
 gamehost.stage_game(installation,destination)!
 assert os.read_file(destination + '/Data/copied-link')! == 'original:dAtA'
 assert !os.is_link(destination + '/Data/copied-link')
 assert os.stat(destination + '/Data/file')!.mode & 0o777 == 0o751
 assert os.stat(destination + '/Data/file')!.mtime == 1700000001
 assert os.read_file(destination + '/_work/settings')! == 'settings'
 assert os.is_dir(destination + '/_work/Data') && os.is_dir(destination + '/System')
 os.write_file(destination + '/stale','stale')!
 gamehost.stage_game(installation,destination)!
 assert !os.exists(destination + '/stale')
 os.symlink('/not/present',installation + '/dangling')!
 gamehost.copy_tree(installation,work + '/layer',false)!
 assert os.readlink(work + '/layer/dangling')! == '/not/present'
 assert os.readlink(work + '/layer/dAtA/copied-link')! == 'file'
 gamehost.copy_tree(installation,work + '/layer',false)!
 gamehost.mkdir(work + '/invalid')!
 gamehost.stage_game(work + '/invalid',destination) or { assert os.exists(destination + '/Data/file'); return }
 return error('invalid installation accepted')
}

fn real_commands(work string) ! {
 tools := gamehost.Tools{}
 directory := work + '/git'; gamehost.mkdir(directory)!
 tools.run(['git','-C',directory,'init','-q'])!
 tools.run(['git','-C',directory,'-c','user.name=Native Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','fixture'])!
 commit := tools.output(['git','-C',directory,'rev-parse','HEAD'])!.trim_space()
 tools.checkout('',directory,commit,false)!
 mut refused := false; tools.checkout('',directory,'bad-pin',false) or { refused = true }; assert refused
 source := work + '/download-source'; os.write_file(source,'native-download')!
 tools.download('file://' + source,work + '/download')!
 assert os.read_file(work + '/download')! == 'native-download'
 os.write_file(source,'modified')!; tools.download('file://' + source,work + '/download')!
 assert os.read_file(work + '/download')! == 'native-download'
 tools.download('file://' + work + '/missing',work + '/failed-download') or { assert !os.exists(work + '/failed-download'); return }
 return error('failed download accepted')
}

fn archive_cases(work string) ! {
 root := work + '/archive-root'; gamehost.mkdir(root)!
 os.write_file(root + '/a','same bytes')!
 os.write_file(root + '/b','same bytes')!
 assert C.link((root + '/a').str,(root + '/hard').str) == 0
 os.symlink('missing',root + '/link')!
 os.write_file(root + '/literal\\é','literal')!
 archive := work + '/tree.tar'; gamehost.archive(root,archive)!
 mut reader := tarstream.open(archive)!; defer { reader.close() }
 mut names := []string{}; mut kinds := []u8{}
 for {
  member := reader.next() or { if err is tarstream.End { break }; return err }
  names << member.name; kinds << member.kind
  if member.name == './hard' { assert member.linkname == './a' }
  if member.name == './link' { assert member.linkname == 'missing' }
 }
 // HFS+ returns decomposed Unicode names; preserve the filesystem's actual
 // spelling in the archive, just as Path.iterdir did on the original host.
 actual_literal := os.ls(root)!.filter(it.starts_with('literal\\'))[0]
 assert names == ['.','./a','./b','./hard','./link','./' + actual_literal]
 assert kinds == [u8(`5`),`0`,`0`,`1`,`2`,`0`]
 result := gamehost.Tools{}.output(['tar','-tf',archive])!
 assert result.split_into_lines().len == 6
 // Failed output-name validation still retires the native stream owner.
 os.write_file(root + '/' + 'z'.repeat(101),'too-long')!
 mut before := 0
 for fd in 0 .. C.getdtablesize() { if C.fcntl(fd,C.F_GETFD) >= 0 { before++ } }
 for _ in 0 .. 100 { gamehost.archive(root,work + '/failed.tar') or { continue }; return error('oversized ustar name accepted') }
 mut after := 0
 for fd in 0 .. C.getdtablesize() { if C.fcntl(fd,C.F_GETFD) >= 0 { after++ } }
 assert before == after
}

fn main() {
 guard := cachecli.own_commands(); defer { guard.close() }
 if os.args.len != 2 { exit(2) }
 work := os.args[1]; root := os.real_path(os.dir(@FILE) + '/../..')
 build_cases(root,work) or { eprintln(err); exit(1) }
 tree_cases(work) or { eprintln(err); exit(1) }
 real_commands(work) or { eprintln(err); exit(1) }
 archive_cases(work) or { eprintln(err); exit(1) }
 pool_cases(work) or { eprintln(err); exit(1) }
 os.write_file(work + '/passed','PASS\n') or { panic(err) }
 eprintln('NATIVE GOTHIC BUILD / complete recipe, rerun, compiler failure, APKs and ICD; installation and literal trees; real git pins and curl cache/failure: PASS')
}
