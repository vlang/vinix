import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'

fn main() {
 mut text := os.read_file(old + '/publish-second.v')!.replace('prioquery-20261023', 'priochange-20261023').replace('prioquery-evidence', 'priochange-evidence')
 text = text.replace('compile-second-', 'compile-fourth-').replace('baseline-first-', 'baseline-second-').replace('linux-first-', 'linux-second-').replace('candidate-second-', 'candidate-first-').replace('kernel-second-', 'kernel-third-')
 start := text.index('  maintained :=') or { panic('Missing maintained start') }
 end := text.index('\n }\n directory(area + "/frozen-second"') or { panic('Missing maintained end') }
 text = text[..start] + '  directory(area + "/states/m" + suffix, suffix + "/maintained", mut manifest)!\n  for name in ["compile-first-", "compile-second-", "compile-third-", "baseline-first-", "linux-first-", "kernel-first-", "kernel-second-"] {\n   ending := if name == "baseline-first-" { "-guest" } else if name.starts_with("kernel-") { "-prod" } else { "" }\n   path := area + "/states/" + name + suffix + ending\n   if os.is_dir(path) { directory(path, "attempts/" + name + suffix, mut manifest)! }\n  }' + text[end..]
 text = text.replace('directory(area + "/frozen-second", "source/fixture", mut manifest)!', 'directory(area + "/frozen-fourth", "source/fixture", mut manifest)!\n directory(area + "/frozen-second", "attempts/frozen-second", mut manifest)!\n directory(area + "/frozen-third", "attempts/frozen-third", mut manifest)!')
 text = text.replace('for name in ["threadnice",', 'for name in ["prioquery", "threadnice",').replace('"prioquery-reference.v", "priochange-evidence.v",', '"priochange-reference.v", "priochange-evidence.v",')
 start_tools := text.index(' for name in ["compile.v",') or { panic('Missing tools start') }
 end_tools := text.index(' copy_file(area + "/report.md"') or { panic('Missing tools end') }
 text = text[..start_tools] + ' for name in os.ls(area)! {\n  if name.ends_with(".v") || name in ["removed-media.json"] { copy_file(area + "/" + name, "tooling/private/" + name, mut manifest)! }\n }\n' + text[end_tools..]
 os.write_file(area + '/publish-first.v', text)!
 mut finalizer := os.read_file(old + '/finalize-second.v')!.replace('prioquery-20261023', 'priochange-20261023').replace('prioquery-evidence', 'priochange-evidence').replace('evidence-audit-second', 'evidence-audit-first').replace('publish-second', 'publish-first').replace('evidence-controls-fifth', 'evidence-controls-second').replace('evidence-fifth', 'evidence-second').replace('prioquery-reference.v', 'priochange-reference.v')
 finalizer = finalizer.replace('"prioqueryfixture", "prioqueryreferenceinit",', '"priochangefixture", "priochangereferenceinit", "prioqueryfixture",')
 os.write_file(area + '/finalize-first.v', finalizer)!
 mut removed := map[string]string{}
 if os.exists(area + '/removed-media.json') { removed = json2.decode[map[string]string](os.read_file(area + '/removed-media.json')!)! }
 for name in ['baseline-first-arm-guest', 'baseline-first-x86-guest', 'baseline-second-arm-guest', 'baseline-second-x86-guest', 'candidate-first-arm-guest', 'candidate-first-x86-guest', 'linux-first-arm', 'linux-first-x86', 'linux-second-arm', 'linux-second-x86'] {
  assert os.exists(area + '/states/' + name + '/serial.log'), 'No completed serial: ' + name
  for path in os.walk_ext(area + '/states/' + name, '') {
   if !os.is_file(path) || (!path.ends_with('.iso') && !path.ends_with('initramfs.tar') && !path.ends_with('initramfs.cpio') && !path.ends_with('.fd')) { continue }
   removed[path] = sha256.sum(os.read_bytes(path)!).hex()
   os.write_file(area + '/removed-media.json', json2.encode(removed, prettify: true) + '\n')!
   os.rm(path)!
  }
 }
 println('Prepared publisher/finalizer and pruned completed boot media with retained hashes')
}
