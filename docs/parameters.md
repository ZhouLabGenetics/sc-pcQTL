# Parameters

## Required inputs

| Parameter | Meaning |
|---|---|
| `input` | CSV samplesheet with `celltype,counts` |
| `gene_annotation` | Autosomal gene-coordinate TSV |
| `genotype_prefix` | PLINK prefix containing `{chr}`; required when `run_qtl=true` |

## Default analysis configuration

| Parameter | Default | Meaning |
|---|---:|---|
| `min_cells` | 10000 | Minimum cells for an analyzed cell type |
| `min_nonzero_fraction` | 0.01 | Required gene nonzero-cell fraction |
| `pair_scope` | `fast` | `fast` block scheduler or cluster-complete scheduler |
| `pair_test` | `component_union` | `component_union` or `joint_score` |
| `count_family` | `poisson` | `poisson` or `negative_binomial` |
| `pair_alpha` | 0.05 | Family-wise alpha for the pair screen |
| `max_cluster_genes` | 50 | Maximum sliding-window size |
| `min_cluster_genes` | 2 | Minimum cluster size |
| `cluster_density` | 0.70 | Required significant-edge fraction |
| `pca_variance` | 0.95 | Cumulative variance retained by cluster PCs |
| `cis_window` | 500000 | Bases added to each side of the cluster span |
| `qtl_maf` | 0.05 | SAIGE-QTL minimum MAF |
| `qtl_fdr` | 0.05 | Within-phenotype variant BH threshold |

The component-union threshold is `pair_alpha/M`. The joint-score threshold is
`pair_alpha/(2M)`. `M` always counts all possible within-chromosome autosomal
unordered pairs after gene filtering, even when `fast` computes only a subset.

`joint_score` currently requires Poisson counts and fasthurdle 1.2.0 or newer.
The optional negative-binomial family applies to `component_union` only.

## Input-column defaults

| Parameter | Default |
|---|---|
| `donor_col` | `individual` |
| `cell_id_col` | `barcode` |
| `gene_col` | `gene_name` |
| `chromosome_col` | `chromosome` |
| `start_col` | `start` |
| `end_col` | `end` |
| `covariates` | `age,sex,pc1,pc2,pc3,pc4,pc5,pc6,pf1,pf2` |
| `categorical_covariates` | `sex` |
| `total_library_col` | `total_read_counts` |
| `log_library_col` | `log_total_read_counts` |

The covariate defaults provide a reference configuration; they are not a fixed
input schema. Replace `covariates` with a comma-separated list of donor-level
columns present in the input, and list the categorical subset in
`categorical_covariates`. Both may be set to an empty string when no additional
donor covariates are required. Library size is configured separately and is
still modeled.

## Standard execution parameters

| Parameter | Default | Meaning |
|---|---:|---|
| `outdir` | `results` | Published output directory |
| `run_qtl` | `true` | Run SAIGE-QTL after phenotype construction |
| `saige_params` | unset | Custom SAIGE-QTL parameter table |
| `variance_ratio_prefix` | unset | Existing variance-ratio PLINK marker prefix |
| `save_directional_tests` | `false` | Publish all directional pair-test records |
| `count_block_size` | 100 | Genes per prepared expression block |
| `pair_responses_per_task` | 10 | Response genes per pair task in either scheduling mode |
| `vr_n_markers` | 10000 | Maximum auto-selected variance-ratio markers |
| `vr_seed` | 1 | Deterministic marker-selection seed |
| `vr_geno` | 0.05 | PLINK missingness threshold |
| `vr_prune_window` | 200 | PLINK LD-pruning window |
| `vr_prune_step` | 50 | PLINK LD-pruning step |
| `vr_prune_r2` | 0.2 | PLINK LD-pruning r-squared threshold |

## Example-only parameters

| Parameter | Default | Meaning |
|---|---:|---|
| `example_pair_max_forks` | 2 | Concurrent pair tasks in the bundled example only |
| `example_qtl_max_forks` | 1 | Concurrent QTL tasks in the bundled example only |

Use a custom Nextflow config to override process memory, time, CPU, queue, or
executor settings. Statistical parameters should be passed on the command
line or in a Nextflow parameter file.

## Advanced staged-execution parameters

These manifest parameters are not used by the standard `sc-pcqtl run`
command. They are inputs to the advanced stage subcommands documented in the
[staged-execution guide](staged-execution.md).

| Parameter | Default | Advanced use |
|---|---:|---|
| `qtl_manifest` | unset | Cluster-PC task manifest for SAIGE-QTL Step 1 |
| `step1_manifest` | unset | Completed null-model manifest for SAIGE-QTL Step 2 |
| `step2_manifest` | unset | Completed association manifest for SAIGE-QTL Step 3 |
| `upstream_step1_manifest` | unset | Completed preparation/pair manifest for upstream Step 2 |
| `upstream_step2_manifest` | unset | Completed cluster manifest for upstream Step 3 |

The launcher manages internal stage-selection and intermediate-publication
parameters. Users should invoke staged runs through `sc-pcqtl upstream` or
`sc-pcqtl saige`, rather than setting those internal parameters directly. See
[advanced staged execution](staged-execution.md) and
[SAIGE-QTL execution](saigeqtl.md).
