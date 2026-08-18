process BUILD_VARIANCE_RATIO {
    tag 'variance-ratio markers'
    label 'process_high'
    publishDir "${params.outdir}/pipeline_info${params.execution_name ? '/' + params.execution_name : ''}/variance_ratio",
        mode: 'copy', overwrite: true

    input:
    path beds
    path bims
    path fams
    path workflow_bin

    output:
    tuple path('auto_vr.bed'), path('auto_vr.bim'), path('auto_vr.fam'), emit: plink
    path 'auto_vr.sha256', emit: checksum
    path 'auto_vr.settings.tsv', emit: settings

    script:
    def prefixes = beds.collect { bed -> bed.baseName }.join('\\n')
    """
    printf '%s\n' '${prefixes}' > genotype_prefixes.txt
    bash ${workflow_bin}/build_variance_ratio_markers.sh \
      genotype_prefixes.txt auto_vr '${params.qtl_maf}' '${params.vr_geno}' \
      '${params.vr_prune_window}' '${params.vr_prune_step}' '${params.vr_prune_r2}' \
      '${params.vr_n_markers}' '${params.vr_seed}'
    """
}
