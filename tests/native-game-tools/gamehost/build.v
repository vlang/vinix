// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

import androidrun
import androidhost as ah
import cachecli
import hosttest
import os
import tarstream

pub const engine_commit = '26b7159230834780fc6a8fc9aa0d060863cb443f'
pub const headers_commit = '3c65a01745e4a1134d32b9c2c456472212dba16d'
pub const rewise_commit = 'c3d3b68903a90ec53ff7b0a4ae704adc6302814b'
pub const mirror = 'https://dl-cdn.alpinelinux.org/alpine/v3.21'
pub const demo_url = 'https://www.worldofgothic.de/download.php?id=122'
pub const demo_sha = '380d2ae52e4e2eac3beea55e729eb7eb2ea04ffa13521cd22e9fe22fcbe96353'

pub fn (tools Tools) download(url string, destination string) ! {
 if os.is_file(destination) && os.file_size(destination) > 0 { return }
 temporary := destination + '.part'
 tools.run(['curl','-fL','--retry','3','-o',temporary,url])!
 if C.rename(temporary.str,destination.str) != 0 { return os.error_posix() }
}

pub fn (tools Tools) checkout(url string, destination string, commit string, submodules bool) ! {
 if !os.exists(destination) {
  tools.run(['git','clone','--no-checkout','--filter=blob:none',url,destination])!
  tools.run(['git','-C',destination,'checkout','--detach',commit])!
 }
 actual := tools.output(['git','-C',destination,'rev-parse','HEAD'])!.trim_space()
 if actual != commit { return error('Expected ${commit} in ${destination}, found ${actual}') }
 if submodules { tools.run(['git','-C',destination,'submodule','update','--init','--recursive'])! }
}

pub fn (tools Tools) apply_patch(source string, name string) ! {
 patch := path(tools.root,'build-support/opengothic/' + name)
 clean := tools.command(['git','-C',source,'apply','--check',patch],true)!
 if clean.status == 0 { tools.run(['git','-C',source,'apply',patch])! }
 else { tools.run(['git','-C',source,'apply','--reverse','--check',patch])! }
}

pub fn stage_game(installation string, destination string) ! {
 mut top := map[string]string{}
 for name in os.ls(installation)! { if os.is_dir(path(installation,name)) { top[name.to_lower()] = path(installation,name) } }
 work := top['_work'] or { '' }
 mut inside := map[string]string{}
 if work != '' { for name in os.ls(work)! { inside[name.to_lower()] = path(work,name) } }
 if 'data' !in top || 'data' !in inside { return error('No Gothic II installation in ${installation}: it needs Data and _work/Data') }
 remove(destination)!
 copy_tree(top['data']!,path(destination,'Data'),true)!
 for name in os.ls(work)! {
  from := path(work,name); to := path(destination,'_work/' + if name.to_lower() == 'data' { 'Data' } else { name })
  if os.is_dir(from) { copy_tree(from,to,true)! } else { copy_file(from,to)! }
 }
 if system := top['system'] { copy_tree(system,path(destination,'System'),true)! }
}

pub fn archive_index(archive string, destination string) ! {
 mut reader := tarstream.open(archive)!; defer { reader.close() }
 for {
  member := reader.next() or { return error('APKINDEX missing: ' + err.msg()) }
  if member.name.trim_left('./') != 'APKINDEX' { continue }
  mut file := os.create(destination)!; defer { file.close() }
  mut buffer := []u8{len: 1024 * 1024}
  for { count := reader.read(mut buffer)!; if count == 0 { break }; unsafe { file.write_full_buffer(buffer.data,usize(count))! } }
  return
 }
}

pub fn development_packages(indexes map[string]string) ![]string {
 mut result := []string{}
 for name in ['vulkan-loader-dev','libx11-dev','libxcursor-dev','libxfixes-dev','libxrender-dev','xorgproto'] {
  mut found := false
  for repo in ['main','community'] {
   for record in indexes[repo].split('\n\n') {
    if !(record + '\n').contains('P:${name}\n') { continue }
    version := record.split_into_lines().filter(it.starts_with('V:'))
    if version.len == 0 { return error('version missing: ' + name) }
    result << repo + '\t' + name + '-' + version[0][2..] + '.apk'
    found = true; break
   }
   if found { break }
  }
  if !found { return error('Development package not found: ' + name) }
 }
 return result
}

struct FetchResult { path string failure string }
fn fetch_batch(tools Tools, downloads string, lines []string) []FetchResult {
 mut result := []FetchResult{}
 for line in lines {
  parts := line.fields()
  if parts.len != 2 { result << FetchResult{failure: 'invalid package row'}; continue }
  target := path(downloads,parts[1])
  tools.download('${mirror}/${parts[0]}/aarch64/${parts[1]}',target) or { result << FetchResult{failure:err.msg()}; continue }
  result << FetchResult{path:target}
 }
 return result
}

pub fn (tools Tools) fetch_archives(downloads string, lines []string) ![]string {
 // All workers join before selecting the first failure in submission order.
 mut jobs := []thread []FetchResult{}
 for slot in 0 .. 6 {
  mut assigned := []string{}
  for i := slot; i < lines.len; i += 6 { assigned << lines[i] }
  jobs << spawn fetch_batch(tools,downloads,assigned)
 }
 mut ordered := []FetchResult{len:lines.len}
 for slot, job in jobs {
  for index, result in job.wait() { ordered[slot + index * 6] = result }
 }
 mut paths := []string{}
 for result in ordered { if result.failure != '' { return error(result.failure) }; paths << result.path }
 return paths
}

pub fn (tools Tools) build(demo bool, installation string) ! {
 if installation != '' && !os.is_dir(installation) { return error('Not a directory: ' + installation) }
 build := hosttest.module_resolve(env('VINIX_OPENGOTHIC_BUILD_DIR',path(tools.root,'build/opengothic')))!
 downloads := path(build,'downloads'); sysroot := path(build,'sysroot'); staging := path(build,'staging')
 for directory in [downloads,sysroot,staging] { mkdir(directory)! }
 source := path(build,'source'); headers := path(build,'vulkan-headers')
 tools.checkout('https://github.com/Try/OpenGothic.git',source,engine_commit,true)!
 tools.checkout('https://github.com/KhronosGroup/Vulkan-Headers.git',headers,headers_commit,false)!
 for name in ['active-descriptors.patch','sampled-attachments.patch'] { tools.apply_patch(path(source,'lib/Tempest'),name)! }
 tools.apply_patch(source,'worker-count.patch')!
 mut indexes := map[string]string{}
 mut resolve := [path(tools.root,'build-support/alpine-resolve')]
 for repo in ['main','community'] {
  archive := path(downloads,repo + '-index.tar.gz'); index := path(downloads,repo + '-index')
  tools.download('${mirror}/${repo}/aarch64/APKINDEX.tar.gz',archive)!
  archive_index(archive,index)!
  indexes[repo] = os.read_file(index)!
  resolve << ['--index',repo,index]
 }
 resolve << ['mesa-vulkan-swrast','vulkan-loader','libx11','libxcursor','libstdc++']
 packages := tools.output(resolve)!.split_into_lines()
 os.write_file(path(build,'packages.tsv'),packages.join('\n') + '\n')!
 archives := tools.fetch_archives(downloads,[...packages,...development_packages(indexes)!])!
 runtime := path(build,'runtime'); remove(runtime)!; mkdir(runtime)!
 for index, archive in archives {
  tools.run(['tar','--ignore-zeros','-xzf',archive,'-C',sysroot])!
  if index < packages.len { tools.run(['tar','--ignore-zeros','-xzf',archive,'-C',runtime])! }
 }
 cc := env('VINIX_OPENGOTHIC_CC','aarch64-linux-musl-gcc'); cxx := env('VINIX_OPENGOTHIC_CXX','aarch64-linux-musl-g++')
 tools.run([path(tools.root,'build-support/compile-v-module'),path(tools.root,'desktop/execinfocore'),path(build,'execinfo.c'),'--arch','arm64','--header',path(sysroot,'usr/include/execinfo.h')])!
 tools.run([cc,'-D_GNU_SOURCE','-D__V_HAVE_EXECINFO_H=1','-O2','-c',path(build,'execinfo.c'),'-o',path(build,'execinfo.o')])!
 tools.run([env('VINIX_OPENGOTHIC_AR','aarch64-linux-musl-ar'),'rcs',path(build,'libexecinfo.a'),path(build,'execinfo.o')])!
 cmakefile := path(source,'CMakeLists.txt'); marker := '# Vinix execinfo compatibility'
 mut text := os.read_file(cmakefile)!
 if text.contains(marker) { text = text.all_before(marker).trim_right(' \t\r\n') + '\n' }
 os.write_file(cmakefile,text + '\n${marker}\ntarget_link_libraries(OpenGothic "${path(build,'libexecinfo.a')}")\n')!
 mut validator := env('GLSLANGVALIDATOR','')
 if validator == '' { validator = os.find_abs_path_of_executable('glslangValidator') or { '' } }
 if validator == '' { validator = os.find_abs_path_of_executable('glslang') or { '' } }
 if validator == '' { return error('Install glslang or set GLSLANGVALIDATOR to its host executable') }
 cmake := path(build,'cmake')
 tools.run(['cmake','-S',source,'-B',cmake,'-G','Ninja','-DCMAKE_SYSTEM_NAME=Linux','-DCMAKE_SYSTEM_PROCESSOR=aarch64','-DCMAKE_C_COMPILER=${cc}','-DCMAKE_CXX_COMPILER=${cxx}','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_POLICY_VERSION_MINIMUM=3.5','-DGLSLANGVALIDATOR=${validator}','-DCMAKE_C_FLAGS=-I${sysroot}/usr/include','-DCMAKE_CXX_FLAGS=-I${sysroot}/usr/include -I${headers}/include -fno-omit-frame-pointer -Wno-error=stringop-overflow','-DCMAKE_EXE_LINKER_FLAGS=-L${sysroot}/usr/lib -Wl,--allow-shlib-undefined','-DALSOFT_BACKEND_ALSA=OFF','-DALSOFT_BACKEND_PULSEAUDIO=OFF','-DALSOFT_BACKEND_JACK=OFF','-DALSOFT_BACKEND_PIPEWIRE=OFF','-DALSOFT_BACKEND_OSS=OFF'])!
 tools.run(['cmake','--build',cmake,'--target','Gothic2Notr','-j',env('VINIX_OPENGOTHIC_JOBS','8')])!
 private := path(staging,'opt/opengothic'); remove(path(private,'lib'))!
 for directory in ['lib','usr/lib'] {
  base := path(runtime,directory)
  if !os.is_dir(base) { continue }
  for name in os.ls(base)! { if name.match_glob('*.so*') { copy_file(path(base,name),path(private,'lib/' + name))! } }
 }
 copy_file(path(cmake,'opengothic/Gothic2Notr'),path(private,'Gothic2Notr'))!
 launcher := path(staging,'usr/bin/run-opengothic'); copy_file(path(tools.root,'build-support/opengothic/run-opengothic'),launcher)!; os.chmod(launcher,0o755)!
 mkdir(path(private,'icd'))!
 mut icd := androidrun.load_json(os.read_file(path(runtime,'usr/share/vulkan/icd.d/lvp_icd.aarch64.json'))!)!.object()
 mut library := ah.field(icd,'ICD').object().clone(); library['library_path'] = ah.Value('/opt/opengothic/lib/libvulkan_lvp.so'); icd['ICD'] = ah.Value(library)
 os.write_file(path(private,'icd/lvp.json'),androidrun.dump_json(ah.Value(icd),2) + '\n')!
 game := path(staging,'usr/share/games/gothic2')
 if demo {
  installer := path(downloads,'Gothic2_Demo_DE.exe'); tools.download(demo_url,installer)!
  if digest(installer)! != demo_sha { return error('Gothic II demo checksum mismatch') }
  rewise := path(build,'rewise'); tools.checkout('https://codeberg.org/CYBERDEV/REWise.git',rewise,rewise_commit,false)!
  tools.run(['make','-C',rewise,'CC=' + env('CC','cc'),'CFLAGS=-O2 -Wall -lz'])!
  extracted := path(build,'demo'); mkdir(extracted)!; tools.run([path(rewise,'rewise'),'-x',extracted,installer])!
  remove(game)!; copy_tree(path(extracted,'MAINDIR'),game,true)!
  os.write_file(path(game,'.vinix-demo'),demo_sha + '\n')!
 } else if installation != '' { stage_game(hosttest.module_resolve(installation)!,game)! }
 os.write_file(path(private,'SOURCES.txt'),'OpenGothic ${engine_commit}\nVulkan-Headers ${headers_commit}\nMesa 24.2.8 / LLVM 19.1.4 (Alpine 3.21)\n')!
 println('Staged OpenGothic: ' + staging)
}

pub fn build_cli(root string, argv []string) !int {
 args := cachecli.arguments(argv,['--game'],[],['--demo'],0,0,'Cross-build OpenGothic for ARM64/musl.\nUsage: build [--demo | --game DIR]') or { return error_with_code(err.msg(),2) }
 if '--demo' in args.options && '--game' in args.options { return error_with_code('--demo and --game are mutually exclusive',2) }
 Tools{root:root}.build('--demo' in args.options,args.value('--game',''))!
 return 0
}
