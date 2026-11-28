module main

import nativepolicy
import os

fn main() { exit(nativepolicy.command(os.args[1..], 'serial-console')) }
