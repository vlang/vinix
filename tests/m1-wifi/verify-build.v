// SPDX-License-Identifier: GPL-2.0-or-later
import os
import wifihost

fn main() { wifihost.run_verifier(os.args[1..], false) }
