# Three-stage upstream execution

The expression-to-phenotype portion of sc-pcQTL can be run as three separate,
manifest-driven submissions. This is intended for large datasets or HPC sites
where preparation and pair testing, cluster calling, and phenotype construction
need different scheduler allocations.

The stages are:

1. prepare cell-type inputs and run the hurdle pair screen;
2. call local gene clusters; and
3. construct cluster-PC phenotypes and the SAIGE-QTL task manifest.

Each command remains internally parallel. Step 1 schedules preparation by cell
type and pair tests by cell type and response-gene chunk. Steps 2 and 3 schedule
one task per cell type. Users should not launch one driver per pair or cell type.

## Step 1: preparation and pair testing

```bash
sc-pcqtl upstream step1 \
  --input /data/project/samplesheet.csv \
  --gene_annotation /data/project/genes.tsv \
  --outdir results/analysis \
  -work-dir work/upstream-step1 \
  -resume
```

This stage applies cell-type and gene filters, prepares reusable expression
blocks and covariates, runs all hurdle pair-test chunks, and writes:

```text
results/analysis/upstream/manifests/step1.tsv
```

## Step 2: cluster calling

```bash
sc-pcqtl upstream step2 \
  --upstream_step1_manifest results/analysis/upstream/manifests/step1.tsv \
  --outdir results/analysis \
  -work-dir work/upstream-step2 \
  -resume
```

This stage calls non-overlapping local clusters and writes:

```text
results/analysis/upstream/manifests/step2.tsv
```

## Step 3: cluster-PC phenotypes

```bash
sc-pcqtl upstream step3 \
  --upstream_step2_manifest results/analysis/upstream/manifests/step2.tsv \
  --outdir results/analysis \
  -work-dir work/upstream-step3 \
  -resume
```

This stage performs cluster PCA, publishes retained PC phenotypes and cis
regions, and writes the same downstream task manifest as the end-to-end path:

```text
results/analysis/phenotypes/qtl_tasks.tsv
results/analysis/upstream/manifests/step3.tsv
```

The first file can be passed directly to `sc-pcqtl saige step1`.

## Parameter ownership

Use the same parameter file or institutional Nextflow configuration for all
three commands. Step 1 owns expression filtering and pair-test settings. Step 2
owns cluster density and minimum cluster size, but its `max_cluster_genes` must
match Step 1 because that value affects pair scheduling. Step 3 owns
`pca_variance` and `cis_window`, while its covariate list must match Step 1.
The workflow checks these cross-stage dependencies before submitting tasks.

The three commands may use different process resources, queues, concurrency
limits, and persistent work directories. Keep one shared `--outdir`; manifests
contain absolute paths to required published intermediates. All paths must
therefore remain visible to later jobs, which normally means using a shared
filesystem on HPC.

## Recovery and completion

Rerun an interrupted stage with the same command, `-work-dir`, `--outdir`, and
`-resume`. A stage manifest is written only after every task required by that
stage completes. Do not start the next stage if its input manifest is absent.
Each stage writes independent provenance under:

```text
pipeline_info/upstream_step1/
pipeline_info/upstream_step2/
pipeline_info/upstream_step3/
```

For scheduler resource examples and the subsequent staged SAIGE-QTL commands,
see [large-scale and HPC execution](large-scale.md).
