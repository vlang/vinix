# Native boot bundle workflow

`bundle_query.v` owns command construction, verified bundle traversal,
authenticated artifact checks, configuration enrollment, signing order and
publication. The public Python entry point retains its parser, constants,
signatures and existing native PE and verified-root APIs.

The generic library bridge borrows actual paths, arguments, modules and
exceptions. It keeps a temporary directory's manager distinct from its entered
value and retires that manager exactly once. The small iterator and three-value
unpacking bindings retain Python language objects; the iterator's decisions
are supplied by V. Genuine signing and runtime fixtures remain independent.
