# Large-scale and HPC batch execution

sc-pcQTL uses Nextflow to submit independent units of work concurrently. The
default `sc-pcqtl run` command is already parallel: cell types, gene-pair
chunks, cluster PCA tasks, and cluster-PC QTL phenotypes are scheduled as soon
as their inputs are available. Users should not launch one workflow per gene
pair or phenotype.

For particularly large QTL scans, the recommended execution model is:

1. Run expression preparation, pair testing, clustering, and phenotype
   construction once with `--run_qtl false`.
2. Run SAIGE-QTL Step 1, Step 2, and Step 3 as separate scheduler submissions.
3. Allow Nextflow to parallelize all manifest rows within each submission.

The three QTL stages are sequential because each consumes the manifest written
by the preceding stage. Within a stage, every cluster-PC phenotype is an
independent task.

## Parallel units

| Workflow section | Parallel unit | Process label |
|---|---|---|
| Input preparation and filtering | Cell type | `process_prepare` |
| Hurdle association screen | Cell type and response-gene chunk | `process_pair` |
| Cluster calling | Cell type | `process_medium` |
| Cluster PCA | Cell type | `process_pca` |
| SAIGE-QTL Steps 1-3 | Cluster-PC phenotype | `process_qtl` |
| Final QTL aggregation | One workflow-wide task | `process_medium` |

The final manifest and summary processes start only after all required upstream
tasks have completed. This synchronization is expected and should not be
mistaken for a loss of parallelism.

## Shared filesystem layout

Use stable shared paths for inputs, published results, the Nextflow work
directory, and the container cache. A practical layout is:

```text
/shared/project/scpcqtl/
  input/
  results/
  work/
  logs/
  container-cache/
```

The work directory can be substantially larger than the published results and
must remain available for `-resume`. Node-local scratch is appropriate for
temporary files through `TMPDIR`, but not for the persistent Nextflow work
directory when tasks can run on different nodes.

For Apptainer on HPC, configure one shared image cache before launching the
workflow:

```bash
export NXF_APPTAINER_CACHEDIR=/shared/project/scpcqtl/container-cache
export SCPCQTL_RUNTIME=apptainer
export SCPCQTL_EXTRA_PROFILES=slurm
```

The cache path must be writable by the user and visible from all compute nodes.

## Institutional Nextflow configuration

The bundled Slurm profile selects the Slurm executor and allows up to 200
submitted or active tasks. Put site-specific queues and resources in a separate
configuration file rather than editing the repository. For example:

```groovy
// institutional.config
executor {
    queueSize = 300
}

process {
    withLabel: process_prepare {
        queue = 'normal'
        cpus = 1
        memory = '64 GB'
        time = '48h'
        maxForks = 8
    }

    withLabel: process_pair {
        queue = 'normal'
        cpus = 1
        memory = '16 GB'
        time = '24h'
        maxForks = 150
    }

    withLabel: process_pca {
        queue = 'normal'
        cpus = 1
        memory = '32 GB'
        time = '24h'
        maxForks = 40
    }

    withLabel: process_qtl {
        queue = 'normal'
        cpus = 1
        memory = '16 GB'
        time = '24h'
        maxForks = 150
    }

    withLabel: process_medium {
        queue = 'normal'
        cpus = 2
        memory = '32 GB'
        time = '24h'
        maxForks = 20
    }
}
```

These values are examples, not universal recommendations. Lower `maxForks`
when concurrent jobs would exceed the project's memory or scheduler quota.
Increase memory or time for a process only after checking failed-task resource
usage in the execution report.

The commands below use Slurm. On an SGE/UGE system, set
`SCPCQTL_EXTRA_PROFILES=sge` instead; the process-label resource selectors are
unchanged, while queue names and any site-specific scheduler options belong in
the institutional configuration.

`executor.queueSize` limits all submitted and active Nextflow tasks, whereas
`maxForks` limits concurrent tasks matching one process selector. The smaller
applicable limit controls effective concurrency. The default SAIGE-QTL tasks
request one CPU; allocating additional CPUs does not by itself make the pinned
SAIGE-QTL commands faster.

## Option 1: complete workflow in one submission

The single-command mode is suitable when the scheduler permits a long-lived
Nextflow driver and the complete analysis can share one resource policy:

```bash
mkdir -p /shared/project/scpcqtl/{results,work,logs}

SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl run \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/full \
  --input /shared/project/scpcqtl/input/samplesheet.csv \
  --gene_annotation /shared/project/scpcqtl/input/genes.tsv \
  --genotype_prefix '/shared/project/scpcqtl/input/genotype_chr{chr}' \
  --variance_ratio_prefix /shared/project/scpcqtl/input/variance_ratio \
  --outdir /shared/project/scpcqtl/results/full \
  -resume
```

This command submits independent tasks through Slurm; it does not run the
analysis serially inside the launcher. Depending on local policy, run the
Nextflow driver on a login node, a workflow node, or within a modest scheduler
allocation that remains active until the workflow finishes.

## Option 2: upstream analysis plus three QTL submissions

This mode provides explicit checkpoints and is recommended when the QTL scan
contains many cluster-PC phenotypes or scheduler wall-time limits make one
long-lived submission inconvenient.

### A. Construct cluster-PC phenotypes

```bash
SCPCQTL_RUNTIME=apptainer \
SCPCQTL_EXTRA_PROFILES=slurm \
sc-pcqtl run \
  -c institutional.config \
  -work-dir /shared/project/scpcqtl/work/upstream \
  --input /shared/project/scpcqtl/input/samplesheet.csv \
  --gene_annotation /shared/project/scpcqtl/input/genes.tsv \
  --run_qtl false \
  --outdir /shared/project/scpcqtl/results/analysis \
  -resume
```

The required QTL input is then available at:

```text
/shared/project/scpcqtl/results/analysis/phenotypes/qtl_tasks.tsv
```

### B. Fit SAIGE-QTL null models

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

Step 1 launches one null-model task per manifest row. If a precomputed
variance-ratio marker set is unavailable, provide the chromosome-template
`--genotype_prefix` instead; the workflow will construct the marker set before
the null-model tasks begin.

### C. Run regional association tests

Run this stage only after Step 1 has written `qtl/manifests/step1.tsv`:

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

Step 2 launches one regional association task per completed Step 1 row.

### D. Calculate regional results and summaries

Run this stage only after Step 2 has written `qtl/manifests/step2.tsv`:

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

Step 3 runs one ACAT task per phenotype and then creates the standard combined
QTL summary tables. The staged analysis therefore produces the same statistical
outputs as the end-to-end QTL path while retaining intermediate null models and
stage manifests.

The full manifest schemas and parameter-ownership rules are documented in
[SAIGE-QTL execution and customization](saigeqtl.md).

## Scheduler submission pattern

Each command above is a Nextflow driver, not an individual phenotype job. If a
site requires the driver itself to run through Slurm, place one command in a
small driver script and submit it with `sbatch`. The three SAIGE-QTL drivers can
be chained with `afterok` dependencies:

```bash
step1_job=$(sbatch --parsable run_saige_step1.sh)
step2_job=$(sbatch --parsable --dependency="afterok:${step1_job}" run_saige_step2.sh)
sbatch --dependency="afterok:${step2_job}" run_saige_step3.sh
```

Each driver subsequently submits its phenotype-level jobs through the Slurm
executor. Do not create one driver submission per phenotype.

## Operational tuning

### Pair-test task size

`--pair_responses_per_task` controls how many response genes are assigned to
one hurdle-screen task. Smaller values create more, shorter jobs; larger values
create fewer, longer jobs. The default is 10. Change it only for scheduling or
resource reasons, and verify that the largest tasks fit within the configured
`process_pair` memory and wall time.

`--count_block_size` controls staged expression blocks during preparation. Its
default is 100 genes. Reducing it can lower temporary memory use at the cost of
additional files and task overhead.

### QTL task concurrency

Each SAIGE-QTL stage consumes one manifest row per task. For thousands of
phenotypes, control pressure on the scheduler using `maxForks` for
`process_qtl` and the global `executor.queueSize`. Raising either value beyond
the site's job limit does not improve throughput and can cause submission
throttling.

### Storage

Standalone SAIGE-QTL stages publish null models and other intermediates needed
by later stages. Estimate storage from a pilot subset before launching the full
manifest. Keep the Nextflow work directory until the complete analysis and QC
are finished; `nextflow clean` removes cached files required by `-resume`.

## Monitoring and recovery

Monitor scheduler jobs with site tools such as:

```bash
squeue -u "$USER"
```

Each run writes an execution trace, HTML report, timeline, and DAG under
`pipeline_info/`. Independent QTL stages use separate directories:

```text
pipeline_info/saige_step1/
pipeline_info/saige_step2/
pipeline_info/saige_step3/
```

After a scheduler interruption or task failure, fix the resource or input
problem and rerun the exact same stage command with the same `--outdir`,
`-work-dir`, and `-resume`. Completed tasks are recovered from the cache. Do not
delete the work directory before resuming.

A stage manifest is written only after every task in that stage succeeds. Its
absence means the stage has not reached its synchronization point; inspect the
execution trace and resume that stage rather than starting the next one.

## Advanced manual manifest sharding

Nextflow-native parallelism is preferred. Manual sharding is useful only when
an institution imposes limits that cannot be handled with `queueSize` or
`maxForks`.

When externally splitting a manifest:

1. Preserve the header and keep every `task_id` unique across shards.
2. Keep `qtl_tasks.tsv` shards beside the original manifest, or rewrite all
   relative phenotype and region paths as absolute paths.
3. Give every concurrently running shard a distinct `--outdir` and
   `-work-dir`.
4. Use identical statistical parameters and container revisions for all
   shards.
5. Combine completed stage manifests with one header before starting the next
   stage, and verify that no task identifier is duplicated.
6. Prefer one final Step 3 run over a combined Step 2 manifest so that a single
   authoritative summary is generated.

Never run independent shards concurrently against the same output directory.
They would overwrite stage manifests and provenance reports even when their
task identifiers differ. Automatic manifest splitting and cross-shard summary
merging are not currently launcher commands.

## Completion checks

For a successful staged analysis:

1. `qtl_tasks.tsv`, `step1.tsv`, `step2.tsv`, and `step3.tsv` should contain the
   same number of task rows.
2. Every Step 3 task directory should contain `association.tsv`, `acat.tsv`,
   `metadata.tsv`, and `COMPLETE`.
3. `summary/phenotype_summary.tsv` should contain one record per successfully
   tested cluster-PC phenotype.
4. `summary/significant_pcqtl_phenotypes.tsv` and
   `summary/pcqtl_counts_by_celltype.tsv` should be present even when no
   phenotype passes the configured FDR threshold.
5. The execution traces should contain no failed tasks remaining after the
   final resumed run.

See [Outputs](outputs.md) for the complete result structure and
[Troubleshooting](troubleshooting.md) for common runtime failures.
