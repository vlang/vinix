import gpu.agx.file
import drm

fn main() { file.run_checks(); drm.check_prime_policy(); file.run_modern_checks() }
