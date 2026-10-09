# Sampler fixture controller

`sampler-query.v` runs the build and execution policy from `test_v_sampler.py`.
The Python entry point retains argparse, Python assertion syntax and bindings
to the actual standard-library objects. Paths, compiler flags, generator
functions, exceptions and context managers cross the controller as borrowed
object handles; they are not reconstructed from text.

The build keeps the original compiler flags, undefined-symbol checks, single
explicit calloc/free pair, original-fixture option and guest serial linkage.
The original sampler and independent fixture remain separate modules. The
small V source literal for the original guest entry is existing generated
source and receives no Python migration credit.

`VINIX_SAMPLER_TEST_QUERY` can select a prebuilt controller for qualification.
Otherwise the shared host controller builds and installs it in a private
temporary directory. Qualification compares a frozen original Python entry
point with the candidate, including failed builds, manager suppression and
cleanup. Actual sanitized fixture executions validate the sampler assertions;
controller comparisons alone do not establish new kernel or guest coverage.
