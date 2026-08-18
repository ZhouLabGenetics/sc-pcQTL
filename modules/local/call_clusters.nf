process CALL_CLUSTERS {
    tag "$celltype"
    label 'process_medium'
    publishDir "${params.outdir}/clusters", mode: 'copy', overwrite: true,
        saveAs: { name -> name == "${celltype}_clusters" ? celltype : name }

    input:
    tuple val(celltype), path(pair_dir, stageAs: 'pair_dir'), path(stage, stageAs: 'prepared_dir')
    path workflow_bin

    output:
    tuple val(celltype), path("${celltype}_clusters"), emit: clusters

    script:
    """
    Rscript ${workflow_bin}/call_clusters.R \
      --stage '${stage}' \
      --pairs '${pair_dir}/all_computed_pairs.tsv.gz' \
      --outdir '${celltype}_clusters' \
      --celltype '${celltype}' \
      --max_cluster_genes '${params.max_cluster_genes}' \
      --min_cluster_genes '${params.min_cluster_genes}' \
      --cluster_density '${params.cluster_density}'
    """
}
