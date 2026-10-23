import qmpclient
import json2
fn main() {
 mut q:=qmpclient.connect('build/android-maps/attempt219/google-maps/qmp.sock')!
 defer { q.close() }
 q.command('quit',map[string]json2.Any{})!
}
