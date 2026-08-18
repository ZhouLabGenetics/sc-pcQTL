process RUN_SAIGE_STEP2 {
    tag "$celltype:$cluster_id:$phenotype_id"
    label 'process_qtl'
    publishDir "${params.outdir}/qtl/tasks", mode: 'copy', overwrite: true,
        enabled: params.publish_saige_intermediates.toString().toBoolean()

    input:
    tuple val(task_id), val(celltype), val(cluster_id), val(phenotype_id), val(chromosome),
          val(phenotype_source), val(region_source), path(region_file),
          path(bed), path(bim), path(fam), path(vr_fam),
          path(null_model), path(variance_ratio),
          path(saige_params), val(saige_params_source)
    path workflow_bin

    output:
    tuple val(task_id), path("${task_id}"), emit: result

    script:
    """
    bash ${workflow_bin}/run_saige_step2.sh \
      '${task_id}' '${celltype}' '${cluster_id}' '${phenotype_id}' '${chromosome}' \
      '${phenotype_source}' '${region_file}' '${region_source}' \
      '${bed}' '${bim}' '${fam}' '${vr_fam}' '${null_model}' '${variance_ratio}' \
      '${saige_params}' '${saige_params_source}' '${task_id}'
    """
}
