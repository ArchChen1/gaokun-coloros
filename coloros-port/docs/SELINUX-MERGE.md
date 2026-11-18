# SELinux merge for the ColorOS 17 / gaokun3 port

The ColorOS ODM ships a complete precompiled policy but not its ODM CIL source.
Rebuilding from only the platform/vendor source files silently drops ColorOS
ODM-only rules. The working baseline is therefore:

1. dump the original ColorOS ODM precompiled policy back to CIL;
2. compile that CIL together with gaokun's versioned vendor policy and vendor
   CIL;
3. install the result as /odm/etc/selinux/precompiled_sepolicy;
4. keep the /odm/etc/selinux/precompiled_sepolicy.*.sha256 files unchanged,
   because the system/system_ext/product CIL and mapping inputs did not change.

## Baseline

~~~text
ColorOS ODM policy:
  sha256 2fb03bea... (original ODM precompiled, retained for reference)
  source CIL sha256 9229e3996ac24f48e85241aa3e0d91b1fb521fd99e6255472cb6dcb052df62bc

Merged policy:
  size   2391186 bytes
  sha256 3fb220b5ee9f0edb132b760c2c2ca54b597a1a05a2d3f03ca28885d12ef70288

checkpolicy summary:
  5348 types
  108 classes
  132502 rules
~~~

The merge keeps all types and rules from the original ColorOS policy and adds
the gaokun vendor types/rules. A merge that only adds the eight missing
property types is not a release baseline: it can pass property initialization
but lacks the ColorOS ODM service rules needed later in boot.

## Reproduce

Run in WSL as root, after the toolchain/input paths are prepared:

~~~bash
bash scripts/wsl_dump_precompiled_policy.sh
bash scripts/wsl_merge_policy.sh
bash scripts/wsl_build_odm_policy.sh
bash scripts/wsl_build_super_c.sh
bash scripts/wsl_verify_policy_super.sh
~~~

Required tools:

- WSL kernel with EROFS and loop-mount support;
- erofs-utils 1.9.4 (1.7 fails on this ODM);
- SELinux secilc/checkpolicy 3.11;
- otatools lpmake/img2simg.

## Why this is safe to test

- system_a and vendor_a are byte-identical between super-a and super-c;
- the odm_a partition is independently fsck.erofs-verified;
- the policy file has security.selinux u:object_r:sepolicy_file:s0;
- the new policy binary header reports version 8, same as the original ODM;
- zstd -t verifies the final super stream decodes to exactly 12884901888 bytes.

This policy has not yet been boot-tested on the Gaokun E Go.
