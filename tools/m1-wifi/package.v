// SPDX-License-Identifier: ISC
import os
import wifihost

fn main() { wifihost.run_package(os.args[1..]) }
