import os
fn main() {
 b := 'build/android-maps/'
 os.write_file(b+'attempt219.json',os.read_file(b+'attempt218.json')!.replace('attempt218','attempt219'))!
 os.write_file(b+'interact219.v',os.read_file(b+'interact218.v')!.replace('218','219'))!
 run := os.read_file(b+'run218.v')!.replace('framework217/api','framework217-observer2/api').replace('b544bd1b332feb6d7bcb43cbbc7e2ae73498da8eb6626ca4046aa78d89f888ab','acd7c4ca1ab2447f528879b2ecc8533d38129627f50e867cc8a586b557978593').replace(" mut runner :=", " os.cp(b+'libnative219.so',b+'native218/libvinix-android-native.so')!\n mut runner :=").replace('attempt218','attempt219').replace('interact218','interact219')
 os.write_file(b+'run219.v',run)!
}
