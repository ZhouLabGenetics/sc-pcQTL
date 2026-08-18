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

## Advanced staged execution

Users who require independently resumable upstream and SAIGE-QTL submissions
should follow [Advanced staged execution](staged-execution.md). That guide is
the authoritative source for all six commands, manifest schemas, parameter
inheritance, scheduler dependencies, and recovery procedures.

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

These commands are shown for transparency. Use `sc-pcqtl run` for routine
analysis. If separate batch stages are required, the staged sc-pcQTL interface
is preferred over native commands because it validates manifests, sample
ordering, region chromosome, parameter ownership, and completion files.
