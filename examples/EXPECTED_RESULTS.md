# Expected example results

These checks describe the deterministic example generated with seed
`20260814`. They verify workflow execution and implanted-signal recovery; they
must not be interpreted as estimates of calibration, power, or biological
effect size.

## Input checks

- 503 unique donors and 12,000 cells in `sim_immune`.
- 40 non-negative integer-valued expression genes.
- Identical donor IDs and ordering in all chromosome and variance-ratio FAM
  files.
- 160 genotype variants on each chromosome 1-21 and 3,160 on chromosome 22.
- 3,000 LD-pruned variance-ratio markers.

## Component-union mode

Expected output under the default `-profile apptainer,example` run:

- 780 unordered gene pairs tested, with 19 significant module-internal edges.
- Five local clusters with 2, 2, 2, 4, and 5 genes.
- 12 cluster-PC phenotypes tested by SAIGE-QTL.
- Six cluster-PC phenotypes with at least one within-phenotype BH-adjusted
  variant q-value below 0.05.
- At least one significant pcQTL in each of the four genetic modules and no
  significant pcQTL in the two-gene negative-control module.

The strongest association in three genetic modules is the implanted causal
variant. In the remaining four-gene module, the strongest variant is a nearby
proxy with EUR LD r-squared of approximately 0.984 with the implanted variant.

## Joint-score mode

With `--pair_test joint_score`, the expected workflow-level counts are also:

- 19 significant edges and the same five clusters.
- 12 tested cluster-PC phenotypes.
- Six significant cluster-PC phenotypes.
- All four genetic modules detected and the negative-control module not
  significant.

Minor floating-point differences in SAIGE-QTL p-values can occur across CPU
and BLAS implementations without changing these checks.
