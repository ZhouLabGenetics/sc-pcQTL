process RUN_CLUSTER_PCA {
    tag "$celltype"
    label 'process_pca'
    publishDir "${params.outdir}/phenotypes", mode: 'copy', overwrite: true,
        saveAs: { name -> name == "${celltype}_pca" ? celltype : name }

    input:
    tuple val(celltype), path(cluster_dir, stageAs: 'cluster_dir'),
          path(stage, stageAs: 'prepared_dir'), path(counts)
    path workflow_bin

    output:
    tuple val(celltype), path("${celltype}_pca"), emit: pca

    script:
    """
    Rscript ${workflow_bin}/run_cluster_pca.R \
      --stage '${stage}' \
      --clusters '${cluster_dir}/clusters.tsv' \
      --counts '${counts}' \
      --outdir '${celltype}_pca' \
      --celltype '${celltype}' \
      --pca_variance '${params.pca_variance}' \
      --cis_window '${params.cis_window}' \
      --covariates '${params.covariates}'
    """
}
