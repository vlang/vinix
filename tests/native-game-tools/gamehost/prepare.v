// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

import androidrun
import androidhost as ah
import cachecli
import hosttest
import os
import strconv

pub struct Options {
pub:
 repo string
 build string
 desktop string
 kernel string
 work string
 engine string
 venus_runtime string
 cpus int = 4
 seconds int = 60
 warmup int = 10
 min_fps f64 = 55
 timeout int = 900
 venus bool
}

pub fn parse_options(root string, argv []string) !Options {
 return options_inner(root,argv) or { return error_with_code(err.msg(),2) }
}

fn options_inner(root string, argv []string) !Options {
 args := cachecli.arguments(argv,['--repo','--build','--desktop','--kernel-dir','--work','--seconds','--engine','--cpus','--venus-runtime','--warmup','--min-fps','--timeout'],[],['--venus'],0,0,'Play OpenGothic in a Vinix desktop under QEMU.\nUsage: run --work DIR [--repo DIR --build DIR --desktop FILE --kernel-dir DIR --seconds 60 --engine FILE --cpus 4 --venus --venus-runtime DIR --warmup 10 --min-fps 55 --timeout 900]')!
 repo := hosttest.module_resolve(args.value('--repo',root))!
 options := Options{
  repo:repo
  build:hosttest.module_resolve(args.value('--build',path(repo,'build/opengothic')))!
  desktop:hosttest.module_resolve(args.value('--desktop',path(root,'build/vinix-desktop')))!
  kernel:hosttest.module_resolve(args.value('--kernel-dir',path(repo,'kernel')))!
  work:hosttest.module_resolve(args.required('--work')!)!
  engine:args.value('--engine','')
  venus_runtime:hosttest.module_resolve(args.value('--venus-runtime',path(repo,'build-aarch64-venus/staging')))!
  cpus:strconv.atoi(args.value('--cpus','4'))!
  seconds:strconv.atoi(args.value('--seconds','60'))!
  warmup:strconv.atoi(args.value('--warmup','10'))!
  min_fps:strconv.atof64(args.value('--min-fps','55'))!
  timeout:strconv.atoi(args.value('--timeout','900'))!
  venus:'--venus' in args.options
 }
 if options.cpus < 1 || options.cpus > 8 { return error_with_code('--cpus must be between 1 and 8',2) }
 if options.seconds < 1 || options.warmup < 0 || options.min_fps <= 0 || options.timeout < 1 { return error_with_code('durations and --min-fps must be positive; --warmup can be zero',2) }
 return options
}

pub fn (tools Tools) prepare(options Options) !string {
 root := path(options.work,'root')
 if !os.exists(path(root,'.prepared')) {
  remove(root)!
  copy_tree(path(options.repo,'build-aarch64-x11/staging'),root,false)!
  userland := path(options.repo,'build-aarch64-userland/staging')
  for directory in ['lib','usr/lib'] {
   from := path(userland,directory)
   if !os.is_dir(from) { continue }
   for name in os.ls(from)! {
    if !name.match_glob('*.so*') { continue }
    target := path(root,directory + '/' + name)
    if !os.exists(target) && !os.is_link(target) { copy_file(path(from,name),target)! }
   }
  }
  mkdir(path(root,'bin'))!; hosttest.module_copy_file_preserving_stat(path(userland,'bin/busybox'),path(root,'bin/busybox'))!
  for name in ['sh','cat','mkdir','chmod','sleep','uname','grep','ps','tail'] { os.symlink('busybox',path(root,'bin/' + name))! }
  for name in ['sbin','proc','dev','sys','tmp','root','run','etc'] { mkdir(path(root,name))! }
  os.write_file(path(root,'etc/passwd'),'root:x:0:0:root:/root:/bin/sh\n')!
  os.write_file(path(root,'etc/group'),'root:x:0:root\n')!
  os.write_file(path(root,'.prepared'),'')!
 }
 for name in ['opt/opengothic','usr/share/games/gothic2'] { remove(path(root,name))! }
 copy_tree(path(options.build,'staging'),root,false)!
 if options.engine != '' { hosttest.module_copy_file_preserving_stat(options.engine,path(root,'opt/opengothic/Gothic2Notr'))! }
 for file in files(path(root,'usr/share/games/gothic2'))! { if file.all_after_last('/').to_lower() == 'intro.bik' { os.rm(file)! } }
 hosttest.module_copy_file_preserving_stat(options.desktop,path(root,'usr/bin/vinix-desktop'))!
 link := path(root,'usr/bin/vinix-opengothic'); remove(link)!; os.symlink('vinix-desktop',link)!
 sysroot := path(options.repo,'build-aarch64-x11/sysroot'); core := path(root,'wine-host-core.c')
 tools.run([path(tools.root,'build-support/xorg-server/compile-v-host'),'winehost',core,'--arch','arm64'])!
 tools.run(['aarch64-linux-musl-gcc','-O2','-w','-D__vinix__','-I${sysroot}/usr/include',core,'-I' + path(tools.root,'build-support/xorg-server'),'-L${sysroot}/usr/lib','-L${sysroot}/lib','-Wl,--allow-shlib-undefined','-lXtst','-lXdamage','-lX11','-lXext','-lxcb','-o',path(root,'usr/bin/vinix-wine-host')])!
 if options.venus {
  copy_tree(options.venus_runtime,root,false)!
  launcher := os.read_file(path(tools.root,'build-support/opengothic/run-opengothic'))!
  target := path(root,'usr/bin/run-opengothic'); os.rm(target)!
  os.write_file(target,launcher.replace('set -eu','set -eu\nexport VK_INSTANCE_LAYERS=VK_LAYER_MESA_overlay\nexport VK_LAYER_PATH=/opt/venus/share/vulkan/explicit_layer.d\nexport VK_LAYER_MESA_OVERLAY_CONFIG=fps,frame_timing,position=top-left,output_file=/tmp/gothic-fps.csv,fps_sampling_period=500'))!
  os.chmod(target,0o755)!
 }
 copy_file(path(tools.root,'tests/opengothic/guest-init.sh'),path(root,'sbin/init'))!
 os.chmod(path(root,'sbin/init'),0o755)!
 return root
}

pub fn press(socket string, key string, seconds f64) ! {
 mut monitor := androidrun.connect_monitor(socket,0)!
 defer { monitor.close() }
 for down in [true,false] {
  monitor.command('input-send-event',{'events':ah.Value([androidrun.key_press(key,down)])})!
  pause(if down { seconds } else { 0.12 })!
 }
}

pub fn run_cli(root string, argv []string) !int {
 options := parse_options(root,argv)!
 if !os.is_dir(path(options.build,'staging/usr/share/games/gothic2/_work/Data')) { return error_with_code('no game data is staged: run scripts/build-opengothic-aarch64.sh with --demo or --game',2) }
 mkdir(options.work)!
 tools := Tools{root:root}
 private := tools.prepare(options)!
 screenshot := run_guest(options,private)!
 println('OpenGothic rendered the world for ${options.seconds} s: ${screenshot}')
 return 0
}
