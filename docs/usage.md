# Inputs and execution

## Samplesheet

`--input` is a comma-separated file with one unique row per cell type:

```text
celltype,counts
cd8_nc,/absolute/path/cd8_nc_counts.tsv.gz
nk,/absolute/path/nk_counts.tsv.gz
```

Cell-type identifiers may contain letters, numbers, dots, underscores, and
hyphens. Each `counts` file is a wide, tab-separated table with one cell per
row. Relative count paths are resolved against the samplesheet directory. The
minimum column structure is:

```text
individual barcode GENE1 GENE2 ...
```

`individual` is the donor identifier and `barcode` is a unique cell
identifier. Gene columns must be finite and non-negative. The default settings
were calibrated with SCTransform-corrected OneK1K counts; applying the workflow
to a different expression scale requires independent calibration.

The default covariate configuration additionally uses `age`, `sex`, `pc1`-
`pc6`, `pf1`, and `pf2`. These names are defaults, not fixed input requirements.
Only columns selected with `--covariates` are required. For example:

```bash
sc-pcqtl run \
  --covariates 'age,batch,ancestry_pc1,ancestry_pc2' \
  --categorical_covariates 'batch' \
  [other parameters]
```

To fit models without additional donor covariates, use
`--covariates '' --categorical_covariates ''`. Library size remains included
in the hurdle model independently of this list. Configured covariates must be
constant across all cells from the same donor within a cell type. Library-size
columns are cell-level and are checked separately. Column names are otherwise
configurable.

### Library size

Supplying `total_read_counts` and `log_total_read_counts` is recommended. The
count component uses log library size as an offset, while the detection
component uses it as an ordinary covariate. If either column is absent, the
workflow computes the missing value from expression columns matched to the
gene annotation and records the source in `celltype_qc.tsv`. If the annotation
does not cover the complete transcriptome, provide precomputed library sizes
instead.

## Gene annotation

`--gene_annotation` is a TSV with one unique row per gene and default columns:

```text
gene_name chromosome start end
GIMAP1    7          150417177 150423199
```

Chromosomes may be `1` or `chr1`. Version 0.1 analyzes autosomes only. The
annotation and genotype files must use the same genome build; sc-pcQTL does
not perform liftOver.

The complete autosomal annotation defines genomic adjacency for cluster
calling. Pairwise models are fitted only for genes passing the configured
expression filter. Cluster PCA reads any retained cluster gene directly from
the count table, including a sparsely expressed gene retained within an
otherwise dense window.

## Genotypes

`--genotype_prefix` is a PLINK1 prefix template containing `{chr}`. It must
resolve to BED, BIM, and FAM files for chromosomes 1 through 22, for example:

```text
/data/genotype_chr1.bed
/data/genotype_chr1.bim
/data/genotype_chr1.fam
...
```

Donor IDs in the phenotype table must map to genotype sample IDs. Extra
genotype samples are allowed. Use `--run_qtl false` to stop after cluster-PC
phenotype construction; genotype input is then optional. This mode still
writes the global `phenotypes/qtl_tasks.tsv` manifest required by standalone
SAIGE-QTL execution.

## Variance-ratio markers

For exact reuse, provide a pruned PLINK prefix with
`--variance_ratio_prefix`. If omitted, the workflow merges the chromosome
files, filters and LD-prunes variants, and deterministically selects at most
10,000 markers. The generated PLINK files and SHA256 checksums are published
under `pipeline_info/variance_ratio/`.

## Execution profiles

The installed launcher selects a supported runtime automatically:

```bash
sc-pcqtl doctor
sc-pcqtl example --outdir results/example
sc-pcqtl run [parameters]
```

Set `SCPCQTL_RUNTIME=docker`, `podman`, `apptainer`, or `singularity` to
override automatic selection. Advanced users can call Nextflow directly as
shown below.

On Slurm, append the executor profile without changing the runtime selection:

```bash
SCPCQTL_EXTRA_PROFILES=slurm sc-pcqtl run -c institutional.config [parameters]
```

Bundled example with Apptainer:

```bash
nextflow run ZhouLabGenetics/sc-pcQTL -profile apptainer,example \
  --outdir results/example
```

Docker workstation:

```bash
nextflow run ZhouLabGenetics/sc-pcQTL -profile docker [parameters]
```

Podman workstation:

```bash
nextflow run ZhouLabGenetics/sc-pcQTL -profile podman [parameters]
```

Slurm with Apptainer:

```bash
nextflow run ZhouLabGenetics/sc-pcQTL -profile apptainer,slurm [parameters]
```

SGE/UGE with Apptainer:

```bash
nextflow run ZhouLabGenetics/sc-pcQTL -profile apptainer,sge \
  -c institutional.config [parameters]
```

Add `-resume` after an interruption. Site-specific resources, queues, and
container cache paths belong in a separate Nextflow config:

```bash
nextflow run ZhouLabGenetics/sc-pcQTL -profile apptainer,slurm \
  -c institutional.config [parameters]
```

Do not edit the workflow's committed profiles for a single installation.

For large expression inputs, `sc-pcqtl upstream step1`, `step2`, and `step3`
separate preparation plus pair testing, cluster calling, and cluster-PC
phenotype construction. Each stage retains Nextflow-native parallelism and
writes the manifest consumed by the next stage. Complete commands are provided
in [three-stage upstream execution](upstream.md).

For large QTL scans, `sc-pcqtl saige step1`, `step2`, and `step3` similarly
divide SAIGE-QTL work into three manifest-driven runs without changing the
statistical settings or final output tables. Complete commands and the external
phenotype manifest schema are provided in [SAIGE-QTL execution](saigeqtl.md).
Resource profiles, scheduler submission patterns, concurrency controls, and
recovery procedures are covered in the dedicated
[large-scale and HPC batch guide](large-scale.md).
