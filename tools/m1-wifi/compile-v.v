// SPDX-License-Identifier: ISC
import os
import wifihost

fn main() { wifihost.run_generator(os.args[1..], true) }
