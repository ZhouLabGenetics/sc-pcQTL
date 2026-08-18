# Advanced: staged execution

This guide describes the optional six-stage, manifest-driven interface. It is
intended for scheduler policies that cannot accommodate one long-lived
Nextflow driver or analyses that require explicit operational checkpoints.
Most users, including most HPC users, should run the complete workflow with
`sc-pcqtl run`; see [Inputs and execution](usage.md) and
[Large-scale and HPC execution](large-scale.md).

Staged execution changes orchestration and publishes additional intermediate
files. It does not change statistical settings or final result tables. Each
stage must finish and write its manifest before the next stage starts, while
tasks within each stage remain parallel.

## Before starting

All stages must use:

- the same workflow revision and analysis containers;
- one shared `--outdir` visible to every compute node;
- persistent, stage-specific `-work-dir` paths; and
- the same statistical parameter file and relevant institutional config.

The commands below illustrate Slurm with Apptainer. Configure shared storage,
the container cache, process resources, and scheduler concurrency as described
in [Large-scale and HPC execution](large-scale.md). On SGE/UGE, replace the
`slurm` extra profile with `sge`.

## Stage 1: prepare inputs and test gene pairs

```bash
SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl upstream step1 \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/upstream-step1 \
  --input /shared/project/scpcqtl/input/samplesheet.csv \
  --gene_annotation /shared/project/scpcqtl/input/genes.tsv \
  --outdir /shared/project/scpcqtl/results/analysis \
  -resume
```

This stage applies cell-type and gene filters, prepares reusable expression
blocks and covariates, runs all hurdle pair-test chunks, and writes:

```text
upstream/manifests/step1.tsv
```

## Stage 2: call local clusters

Start this stage only after `upstream/manifests/step1.tsv` is present:

```bash
SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl upstream step2 \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/upstream-step2 \
  --upstream_step1_manifest /shared/project/scpcqtl/results/analysis/upstream/manifests/step1.tsv \
  --outdir /shared/project/scpcqtl/results/analysis \
  -resume
```

This stage calls non-overlapping local clusters and writes:

```text
upstream/manifests/step2.tsv
```

## Stage 3: construct cluster-PC phenotypes

Start this stage only after `upstream/manifests/step2.tsv` is present:

```bash
SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl upstream step3 \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/upstream-step3 \
  --upstream_step2_manifest /shared/project/scpcqtl/results/analysis/upstream/manifests/step2.tsv \
  --outdir /shared/project/scpcqtl/results/analysis \
  -resume
```

This stage performs cluster PCA, publishes retained PC phenotypes and cis
regions, and writes:

```text
phenotypes/qtl_tasks.tsv
upstream/manifests/step3.tsv
```

## Stage 4: fit SAIGE-QTL null models

```bash
SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl saige step1 \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/saige-step1 \
  --qtl_manifest /shared/project/scpcqtl/results/analysis/phenotypes/qtl_tasks.tsv \
  --variance_ratio_prefix /shared/project/scpcqtl/input/variance_ratio \
  --outdir /shared/project/scpcqtl/results/analysis \
  -resume
```

This stage fits one quantitative-trait null model per cluster-PC phenotype and
writes:

```text
qtl/manifests/step1.tsv
```

If a precomputed variance-ratio marker set is unavailable, provide the
chromosome-template `--genotype_prefix` instead of
`--variance_ratio_prefix`. The workflow will construct the marker set before
fitting the null models.

## Stage 5: run regional association tests

Start this stage only after `qtl/manifests/step1.tsv` is present:

```bash
SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl saige step2 \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/saige-step2 \
  --step1_manifest /shared/project/scpcqtl/results/analysis/qtl/manifests/step1.tsv \
  --genotype_prefix '/shared/project/scpcqtl/input/genotype_chr{chr}' \
  --outdir /shared/project/scpcqtl/results/analysis \
  -resume
```

This stage runs one chromosome-specific regional single-variant test per
completed null model and writes:

```text
qtl/manifests/step2.tsv
```

## Stage 6: calculate regional results and summaries

Start this stage only after `qtl/manifests/step2.tsv` is present:

```bash
SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl saige step3 \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/saige-step3 \
  --step2_manifest /shared/project/scpcqtl/results/analysis/qtl/manifests/step2.tsv \
  --outdir /shared/project/scpcqtl/results/analysis \
  -resume
```

This stage calculates one regional ACAT result per phenotype and creates the
standard combined QTL summary tables. It also writes:

```text
qtl/manifests/step3.tsv
```

## Parameter ownership

Use the same parameter file or institutional Nextflow configuration for all
six commands. The launcher validates parameters that must remain identical
across stage boundaries.

For the upstream stages:

- Stage 1 owns expression filtering and pair-test settings.
- Stage 2 owns cluster density and minimum cluster size, but
  `max_cluster_genes` must match Stage 1 because it affects pair scheduling.
- Stage 3 owns `pca_variance` and `cis_window`, while its covariate list must
  match Stage 1.

For the SAIGE-QTL stages:

- Pass `--saige_params`, `--qtl_maf`, and nondefault QTL-model covariates to
  Stage 4 (`sc-pcqtl saige step1`).
- Stages 5 and 6 inherit the resolved SAIGE-QTL parameter table through their
  manifests.
- Pass a nondefault `--qtl_fdr` to Stage 6 because it controls final reporting.

See [SAIGE-QTL execution and customization](saigeqtl.md) for the parameter
override-table format.

## Manifest interface

`phenotypes/qtl_tasks.tsv` has one row per cluster-PC phenotype and these
required columns:

```text
task_id celltype cluster_id phenotype_id chromosome phenotype_file region_file
```

`task_id` must be unique; identifiers may contain letters, numbers, dots,
underscores, and hyphens; and chromosomes must be 1-22. A phenotype table must
contain `individual` and the named `phenotype_id`, and its region file must
contain a matching chromosome, start, and end. Relative paths are resolved
against the directory containing the manifest. Absolute paths are also
accepted.

Each SAIGE-QTL stage records the files required by the next stage:

- `qtl/manifests/step1.tsv` records null-model, variance-ratio, phenotype,
  region, and resolved-parameter paths.
- `qtl/manifests/step2.tsv` records the single-variant association output and
  inherited resolved-parameter path.
- `qtl/manifests/step3.tsv` records the final association, ACAT, metadata, and
  completion files.

Do not modify generated manifest contents during normal staged execution. A
stage manifest is written only after every task in that stage has completed
successfully. If institutional constraints require manual sharding, follow the
dedicated instructions below.

## Scheduler dependency pattern

Each command above is one Nextflow driver, not one analysis task. If the driver
must itself run through Slurm, place each command in a small submission script
and chain the six drivers with `afterok` dependencies:

```bash
upstream1_job=$(sbatch --parsable run_upstream_step1.sh)
upstream2_job=$(sbatch --parsable --dependency="afterok:${upstream1_job}" run_upstream_step2.sh)
upstream3_job=$(sbatch --parsable --dependency="afterok:${upstream2_job}" run_upstream_step3.sh)
saige1_job=$(sbatch --parsable --dependency="afterok:${upstream3_job}" run_saige_step1.sh)
saige2_job=$(sbatch --parsable --dependency="afterok:${saige1_job}" run_saige_step2.sh)
sbatch --dependency="afterok:${saige2_job}" run_saige_step3.sh
```

Each driver subsequently submits cell-type, pair-chunk, or phenotype-level
tasks through the configured executor. Do not create one driver submission per
gene pair or phenotype.

## Storage, monitoring, and recovery

Staged execution publishes prepared expression blocks, null models, and other
intermediates required by later stages. Estimate their storage requirements
from a pilot subset. Keep all stage work directories until analysis and QC are
finished; `nextflow clean` removes cached files required by `-resume`.

Each stage writes an execution trace, HTML report, timeline, DAG, and resolved
parameters to a separate provenance directory:

```text
pipeline_info/upstream_step1/
pipeline_info/upstream_step2/
pipeline_info/upstream_step3/
pipeline_info/saige_step1/
pipeline_info/saige_step2/
pipeline_info/saige_step3/
```

After an interruption or task failure, fix the resource or input problem and
rerun the exact same stage command with the same `--outdir`, `-work-dir`, and
`-resume`. If the expected output manifest is absent, resume that stage rather
than starting the next one.

## Advanced manual manifest sharding

Nextflow-native parallelism is preferred. Manual sharding is useful only when
an institution imposes limits that cannot be handled with `queueSize` or
`maxForks`.

When externally splitting a QTL manifest:

1. Preserve the header and keep every `task_id` unique across shards.
2. Keep `qtl_tasks.tsv` shards beside the original manifest, or rewrite all
   relative phenotype and region paths as absolute paths.
3. Give every concurrently running shard a distinct `--outdir` and
   `-work-dir`.
4. Use identical statistical parameters and container revisions for all
   shards.
5. Combine completed stage manifests with one header before starting the next
   stage, and verify that no task identifier is duplicated.
6. Prefer one final Stage 6 run over a combined Stage 5 manifest so that a
   single authoritative summary is generated.

Never run independent shards concurrently against the same output directory.
They would overwrite stage manifests and provenance reports even when their
task identifiers differ. Automatic manifest splitting and cross-shard summary
merging are not currently launcher commands.

## Completion checks

For a successful staged analysis:

1. `phenotypes/qtl_tasks.tsv`, `qtl/manifests/step1.tsv`,
   `qtl/manifests/step2.tsv`, and `qtl/manifests/step3.tsv` should contain the
   same number of task rows.
2. Every final QTL task directory should contain `association.tsv`, `acat.tsv`,
   `metadata.tsv`, and `COMPLETE`.
3. `summary/phenotype_summary.tsv` should contain one record per successfully
   tested cluster-PC phenotype.
4. `summary/significant_pcqtl_phenotypes.tsv` and
   `summary/pcqtl_counts_by_celltype.tsv` should be present even when no
   phenotype passes the configured FDR threshold.
5. The six execution traces should contain no failed tasks after the final
   resumed run.

See [Outputs](outputs.md) for stage-specific output paths and
[Troubleshooting](troubleshooting.md) for common runtime failures.
