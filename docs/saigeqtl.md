# SAIGE-QTL execution and customization

The default `sc-pcqtl run` command executes SAIGE-QTL automatically after
constructing cluster-PC phenotypes. Built-in settings are used unless the user
provides an optional parameter override table.

## Custom parameter table

sc-pcQTL supports user-defined SAIGE-QTL options through
`--saige_params`. The pinned SAIGE-QTL image is based on version 0.3.4, and
the built-in settings in `assets/saigeqtl_defaults.tsv` are used for options
that are not overridden.

For explanations of individual SAIGE-QTL options, consult the official
[SAIGE-QTL documentation](https://weizhou0.github.io/SAIGE-QTL-doc/),
[quick-start guide](https://weizhou0.github.io/SAIGE-QTL-doc/docs/quickstart.html),
and [parameter reference](https://weizhou0.github.io/SAIGE-QTL-doc/docs/parameters.html).
The settings below describe how those options are supplied through sc-pcQTL.

Create a tab-separated override table such as `overrides.tsv`:

```text
step	parameter	value
step1	maxiter	30
step2	markers_per_chunk	20000
```

Then pass it to the normal workflow command:

```bash
sc-pcqtl run \
  --input samplesheet.csv \
  --gene_annotation genes.tsv \
  --genotype_prefix '/data/cohort/genotype_chr{chr}' \
  --saige_params overrides.tsv \
  --outdir results/analysis
```

`step` must be `step1`, `step2`, or `step3`. The workflow validates duplicate
and unknown parameters. Set `--allow_unknown_saige_params true` only when a
custom compatible image adds a parameter not recognized by this release.

## Workflow-owned arguments

File paths, output prefixes, phenotype and sample identifiers, chromosome,
region, quantitative trait type, covariate lists, and minimum MAF cannot be
overridden in the table. Use the corresponding sc-pcQTL parameter instead,
for example `--covariates` or `--qtl_maf`. This prevents a parameter table from
silently disconnecting SAIGE-QTL from workflow-managed inputs.

The fully resolved parameter table is written to
`pipeline_info/resolved_saigeqtl_params.tsv` for an end-to-end run. In the
advanced staged mode, it is written to
`pipeline_info/saige_step1/resolved_saigeqtl_params.tsv` and propagated to the
later stages through their manifests.

## Advanced: independent batch stages

Large QTL scans can be divided into three independently resumable batch runs.
Every command processes all rows in its input manifest; users do not need to
launch one command per phenotype. The standard `sc-pcqtl run` command remains
the recommended interface when separate scheduler allocations are not needed.

For Slurm resource configuration, concurrency limits, scheduler chaining,
monitoring, and recovery, see the
[large-scale and HPC batch guide](large-scale.md). A complete upstream-to-QTL
staged example is provided in the
[example documentation](../examples/README.md#run-the-complete-workflow-step-by-step).

First construct cluster-PC phenotypes without running QTL association tests:

```bash
sc-pcqtl run \
  --input samplesheet.csv \
  --gene_annotation genes.tsv \
  --run_qtl false \
  --outdir results/analysis
```

Alternatively, the three upstream stages can generate the same
`phenotypes/qtl_tasks.tsv` input. Then run the three SAIGE-QTL stages:

```bash
sc-pcqtl saige step1 \
  --qtl_manifest results/analysis/phenotypes/qtl_tasks.tsv \
  --variance_ratio_prefix /data/cohort/saige_variance_ratio \
  --outdir results/analysis
```

```bash
sc-pcqtl saige step2 \
  --step1_manifest results/analysis/qtl/manifests/step1.tsv \
  --genotype_prefix '/data/cohort/genotype_chr{chr}' \
  --outdir results/analysis
```

```bash
sc-pcqtl saige step3 \
  --step2_manifest results/analysis/qtl/manifests/step2.tsv \
  --outdir results/analysis
```

Step 1 fits one quantitative-trait null model per cluster-PC phenotype. Step 2
uses those models for chromosome-specific regional single-variant tests. Step
3 calculates the regional ACAT result and regenerates the standard sc-pcQTL
summary tables. Add `-resume` to any interrupted stage.

If a variance-ratio marker set is not available, replace
`--variance_ratio_prefix` in Step 1 with the same chromosome-template
`--genotype_prefix` used in Step 2. sc-pcQTL will build the marker set before
fitting the null models.

Pass `--saige_params`, `--qtl_maf`, and any nondefault QTL-model covariate
settings to Step 1. Its resolved parameter table is inherited by Steps 2 and
3. A nondefault `--qtl_fdr` controls final reporting and should be passed to
Step 3.

### Manifest interface

`phenotypes/qtl_tasks.tsv` has one row per cluster-PC phenotype and these
required columns:

```text
task_id celltype cluster_id phenotype_id chromosome phenotype_file region_file
```

The same schema can be supplied by users who prepare compatible cluster-PC
phenotypes outside the upstream workflow. `task_id` must be unique;
identifiers may contain letters, numbers, dots, underscores, and hyphens; and
chromosomes must be 1-22. A phenotype table must contain `individual` and the
named `phenotype_id`, and its region file must contain a matching chromosome,
start, and end. Relative paths are resolved against the directory containing
the manifest. Absolute paths are also accepted.

Each completed stage writes the manifest consumed by the next stage:

- `qtl/manifests/step1.tsv` records null-model, variance-ratio, phenotype,
  region, and resolved-parameter paths.
- `qtl/manifests/step2.tsv` records the single-variant association output and
  inherited resolved-parameter path.
- `qtl/manifests/step3.tsv` records the final association, ACAT, metadata, and
  completion files.

## Advanced: native commands for one bundled task

The staged workflow is a validated batch wrapper around the following native
SAIGE-QTL 0.3.4 commands. After constructing the bundled example phenotypes
with `--run_qtl false`, the deterministic first task is
`sim_immune__SC_chr22_cluster_001__PC1`:

```bash
SCPCQTL_PIPELINE="$PWD" sc-pcqtl example \
  --run_qtl false \
  --outdir results/example_core
```

```bash
mkdir -p native_saige/sim_immune__SC_chr22_cluster_001__PC1
step1_fitNULLGLMM_qtl.R \
  --IsOverwriteVarianceRatioFile=TRUE \
  --covarColList=age,sex,pc1,pc2,pc3,pc4,pc5,pc6,pf1,pf2 \
  --invNormalize=TRUE \
  --isCovariateOffset=FALSE \
  --isCovariateTransform=TRUE \
  --isRemoveZerosinPheno=FALSE \
  --sampleCovarColList=age,sex,pc1,pc2,pc3,pc4,pc5,pc6,pf1,pf2 \
  --skipModelFitting=FALSE \
  --skipVarianceRatioEstimation=FALSE \
  --tol=0.00001 \
  --traitType=quantitative \
  --useGRMtoFitNULL=FALSE \
  --useSparseGRMtoFitNULL=FALSE \
  --phenoFile=results/example_core/phenotypes/sim_immune/SC_chr22_cluster_001/phenotypes.tsv \
  --phenoCol=PC1 \
  --sampleIDColinphenoFile=individual \
  --outputPrefix=native_saige/sim_immune__SC_chr22_cluster_001__PC1/saige_null_model \
  --plinkFile=examples/variance_ratio
```

```bash
step2_tests_qtl.R \
  --LOCO=FALSE \
  --markers_per_chunk=10000 \
  --minMAF=0.05 \
  --bedFile=examples/genotype_chr22.bed \
  --bimFile=examples/genotype_chr22.bim \
  --famFile=examples/genotype_chr22.fam \
  --SAIGEOutputFile=native_saige/sim_immune__SC_chr22_cluster_001__PC1/association.tsv \
  --chrom=22 \
  --GMMATmodelFile=native_saige/sim_immune__SC_chr22_cluster_001__PC1/saige_null_model.rda \
  --varianceRatioFile=native_saige/sim_immune__SC_chr22_cluster_001__PC1/saige_null_model.varianceRatio.txt \
  --rangestoIncludeFile=results/example_core/phenotypes/sim_immune/SC_chr22_cluster_001/cis_region.tsv
```

```bash
step3_gene_pvalue_qtl.R \
  --assocFile=native_saige/sim_immune__SC_chr22_cluster_001__PC1/association.tsv \
  --geneName=PC1 \
  --genePval_outputFile=native_saige/sim_immune__SC_chr22_cluster_001__PC1/acat.tsv
```

These commands are shown for transparency. The staged sc-pcQTL interface is
preferred because it validates manifests, sample ordering, region chromosome,
parameter ownership, and completion files.
