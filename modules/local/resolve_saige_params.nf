process RESOLVE_SAIGE_PARAMS {
    tag 'SAIGE-QTL parameters'
    label 'process_low'
    publishDir "${params.outdir}/pipeline_info${params.execution_name ? '/' + params.execution_name : ''}",
        mode: 'copy', overwrite: true

    input:
    path defaults
    path user_params
    path workflow_bin

    output:
    path 'resolved_saigeqtl_params.tsv', emit: table

    script:
    """
    Rscript ${workflow_bin}/resolve_saige_params.R \
      --defaults '${defaults}' \
      --user '${user_params}' \
      --out resolved_saigeqtl_params.tsv \
      --covariates '${params.covariates}' \
      --qtl_maf '${params.qtl_maf}' \
      --allow_unknown '${params.allow_unknown_saige_params}'
    """
}
