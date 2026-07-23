# Contributing

This branch is a shallow fork of Linux stable `v6.18.39`. Keep kernel changes
separate from Lima tooling changes so reviewers can audit both layers.

## Kernel changes

1. Preserve Apple's copyright and permission notice in modified TSO code.
2. Keep the rebased patch under `lima-rosetta/kernel/patches/` in sync with the
   source commit.
3. Run the static checks and kernel configuration assertions. The generated
   mail patch is excluded from the outer `git diff --check` because its unified
   diff context intentionally contains leading whitespace.
4. Build with `lima-rosetta/kernel/build-kernel.sh`.
5. Include `Signed-off-by` as required by the Linux Developer Certificate of
   Origin.

## Lima changes

1. Do not commit a rendered host path. The source template must keep
   `@@KERNEL_IMAGE@@` and `@@KERNEL_SHA256@@`.
2. Do not weaken the outer/inner ownership of `binfmt_misc`.
3. Test interactive PTY and noninteractive pipe paths separately.
4. Validate both systemd system and user managers after package upgrades.

Run the local checks:

```sh
./lima-rosetta/tests/static-checks.sh
./lima-rosetta/lima/verify-runtime.sh fedora-x86
```

When porting to another Linux version, start from Apple's published patch,
reconcile task/thread and `prctl` API changes explicitly, and record the new
upstream commit, compiler, final configuration, and runtime results.
