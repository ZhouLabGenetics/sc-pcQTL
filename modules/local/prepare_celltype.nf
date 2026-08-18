process PREPARE_CELLTYPE {
    tag "$celltype"
    label 'process_prepare'
    publishDir "${params.outdir}/qc/celltypes", mode: 'copy', overwrite: true,
        saveAs: { name ->
            if (name == "${celltype}_stage") return null
            def prefix = "${celltype}__"
            return name.startsWith(prefix) ? "${celltype}/${name.substring(prefix.size())}" : name
        }
    publishDir "${params.outdir}/upstream/step1/prepared", mode: 'copy', overwrite: true,
        enabled: params.publish_upstream_intermediates.toString().toBoolean(),
        saveAs: { name -> name == "${celltype}_stage" ? celltype : null }

    input:
    tuple val(celltype), path(counts)
    path annotation
    path workflow_bin

    output:
    tuple val(celltype), path("${celltype}_stage"), emit: stage
    tuple val(celltype), path("${celltype}__celltype_qc.tsv"),
          path("${celltype}__gene_filtering.tsv"), emit: qc

    script:
    """
    Rscript ${workflow_bin}/prepare_celltype.R \
      --celltype '${celltype}' \
      --counts '${counts}' \
      --annotation '${annotation}' \
      --outdir '${celltype}_stage' \
      --donor_col '${params.donor_col}' \
      --cell_id_col '${params.cell_id_col}' \
      --gene_col '${params.gene_col}' \
      --chromosome_col '${params.chromosome_col}' \
      --start_col '${params.start_col}' \
      --end_col '${params.end_col}' \
      --genome_build '${params.genome_build}' \
      --covariates '${params.covariates}' \
      --categorical_covariates '${params.categorical_covariates}' \
      --total_library_col '${params.total_library_col}' \
      --log_library_col '${params.log_library_col}' \
      --min_cells '${params.min_cells}' \
      --min_nonzero_fraction '${params.min_nonzero_fraction}' \
      --count_block_size '${params.count_block_size}'
    cp '${celltype}_stage/celltype_qc.tsv' '${celltype}__celltype_qc.tsv'
    cp '${celltype}_stage/gene_filtering.tsv' '${celltype}__gene_filtering.tsv'
    """
}
