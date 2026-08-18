process RUN_SAIGE_STEP1 {
    tag "$celltype:$cluster_id:$phenotype_id"
    label 'process_qtl'
    publishDir "${params.outdir}/qtl/step1", mode: 'copy', overwrite: true,
        enabled: params.publish_saige_intermediates.toString().toBoolean()

    input:
    tuple val(task_id), val(celltype), val(cluster_id), val(phenotype_id), val(chromosome),
          val(phenotype_source), val(region_source), path(phenotype_file),
          path(vr_bed), path(vr_bim), path(vr_fam), val(vr_fam_source),
          path(saige_params), val(saige_params_source)
    path workflow_bin

    output:
    tuple val(task_id), path("${task_id}"), emit: result

    script:
    def vrPrefix = vr_bed.baseName
    """
    bash ${workflow_bin}/run_saige_step1.sh \
      '${task_id}' '${celltype}' '${cluster_id}' '${phenotype_id}' '${chromosome}' \
      '${phenotype_file}' '${phenotype_source}' '${region_source}' \
      '${vrPrefix}' '${vr_fam_source}' '${saige_params}' '${saige_params_source}' \
      '${task_id}'
    """
}
