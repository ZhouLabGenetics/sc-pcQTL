process WRITE_SAIGE_STAGE_MANIFEST {
    tag "$stage manifest"
    label 'process_low'
    publishDir "${params.outdir}/qtl/manifests", mode: 'copy', overwrite: true

    input:
    val stage
    path task_dirs
    path workflow_bin

    output:
    path 'step*.tsv', emit: manifest

    script:
    def inputLines = task_dirs.collect { directory -> directory.toString() }.join('\n')
    def publishedRoot = new File(params.outdir.toString()).absolutePath
    """
    printf '%s\n' '${inputLines}' > stage_inputs.txt
    Rscript ${workflow_bin}/collect_saige_stage_manifest.R \
      --input_list stage_inputs.txt \
      --stage '${stage}' \
      --published_root '${publishedRoot}' \
      --out '${stage}.tsv'
    """
}
