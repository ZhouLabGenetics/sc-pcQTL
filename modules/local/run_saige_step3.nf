process RUN_SAIGE_STEP3 {
    tag "$celltype:$cluster_id:$phenotype_id"
    label 'process_qtl'
    publishDir "${params.outdir}/qtl/tasks", mode: 'copy', overwrite: true

    input:
    tuple val(task_id), val(celltype), val(cluster_id), val(phenotype_id), val(chromosome),
          val(phenotype_source), val(region_source), path(association),
          path(saige_params), val(saige_params_source)
    path workflow_bin

    output:
    tuple val(task_id), val(celltype), path("${task_id}"), emit: result

    script:
    """
    bash ${workflow_bin}/run_saige_step3.sh \
      '${task_id}' '${celltype}' '${cluster_id}' '${phenotype_id}' '${chromosome}' \
      '${phenotype_source}' '${region_source}' '${association}' \
      '${saige_params}' '${saige_params_source}' '${task_id}'
    """
}
