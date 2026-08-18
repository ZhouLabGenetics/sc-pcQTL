process COLLECT_QTL_TASKS {
    tag 'QTL task manifest'
    label 'process_low'
    publishDir "${params.outdir}/phenotypes", mode: 'copy', overwrite: true

    input:
    path pca_dirs
    path workflow_bin

    output:
    path 'qtl_tasks.tsv', emit: manifest

    script:
    def inputLines = pca_dirs.collect { directory -> directory.toString() }.join('\n')
    """
    printf '%s\n' '${inputLines}' > pca_inputs.txt
    Rscript ${workflow_bin}/collect_qtl_tasks.R \
      --input_list pca_inputs.txt \
      --out qtl_tasks.tsv
    """
}
