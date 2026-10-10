import os
import recoverycli

fn main() {
	recoverycli.run('recover_g17_abi', os.args[1..])
}
