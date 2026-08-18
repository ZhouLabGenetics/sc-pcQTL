# Advanced: large-scale and HPC execution

This guide explains how to run the standard complete sc-pcQTL workflow on an
HPC scheduler. Most users should begin with the workstation command documented
in [Inputs and execution](usage.md).

The standard `sc-pcqtl run` command is already parallel: cell types,
gene-pair chunks, cluster PCA tasks, and cluster-PC QTL phenotypes are
scheduled as soon as their inputs are available. Running on HPC changes the
executor and resource configuration; it does not require splitting the
workflow into manual stages. Users should not launch one workflow per gene
pair or phenotype.

If institutional policy requires separate scheduler allocations or explicit
manifest checkpoints, use the distinct
[advanced staged-execution guide](staged-execution.md).

## Parallel units

| Workflow section | Parallel unit | Process label |
|---|---|---|
| Input preparation and filtering | Cell type | `process_prepare` |
| Hurdle association screen | Cell type and response-gene chunk | `process_pair` |
| Cluster calling | Cell type | `process_medium` |
| Cluster PCA | Cell type | `process_pca` |
| SAIGE-QTL association | Cluster-PC phenotype | `process_qtl` |
| Final QTL aggregation | One workflow-wide task | `process_medium` |

The final summary processes start only after all required upstream tasks have
completed. This synchronization is expected and should not be mistaken for a
loss of parallelism.

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

## Run the complete workflow on HPC

Create the shared directories and submit the standard workflow with the site
configuration:

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

## Operational tuning

### Pair-test task size

`--pair_responses_per_task` controls how many response genes are assigned to
one hurdle-screen task. Smaller values create more, shorter jobs; larger values
create fewer, longer jobs. The default is 10. Change it only for scheduling or
resource reasons, and verify that the largest tasks fit within the configured
`process_pair` memory and wall time.

`--count_block_size` controls prepared expression block size. Its default is
100 genes. Reducing it can lower temporary memory use at the cost of additional
files and task overhead.

### QTL task concurrency

Each cluster-PC phenotype is an independent QTL task. For thousands of
phenotypes, control pressure on the scheduler using `maxForks` for
`process_qtl` and the global `executor.queueSize`. Raising either value beyond
the site's job limit does not improve throughput and can cause submission
throttling.

### Storage

Estimate work-directory and published-result sizes from a pilot subset before
launching the full analysis. Keep the Nextflow work directory until analysis
and QC are finished; `nextflow clean` removes cached files required by
`-resume`.

## Monitoring and recovery

Monitor scheduler jobs with site tools such as:

```bash
squeue -u "$USER"
```

The complete run writes an execution trace, HTML report, timeline, DAG, and
resolved parameters under `pipeline_info/`. After a scheduler interruption or
task failure, fix the resource or input problem and rerun the same
`sc-pcqtl run` command with the same `--outdir`, `-work-dir`, and `-resume`.
Completed tasks are recovered from the cache. Do not delete the work directory
before resuming.

See [Outputs](outputs.md) for the result structure and
[Troubleshooting](troubleshooting.md) for common runtime failures. For separate
driver submissions and stage-specific recovery, use
[Advanced staged execution](staged-execution.md).
