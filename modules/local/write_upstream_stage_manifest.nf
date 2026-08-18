process WRITE_UPSTREAM_STAGE_MANIFEST {
    tag "$stage manifest"
    label 'process_low'
    publishDir "${params.outdir}/upstream/manifests", mode: 'copy', overwrite: true

    input:
    val stage
    val rows
    path parameter_file

    output:
    path 'step*.tsv', emit: manifest

    script:
    def columnsByStage = [
        step1: ['celltype', 'counts_file', 'prepared_dir', 'pair_dir',
                'step1_parameters_file'],
        step2: ['celltype', 'counts_file', 'prepared_dir', 'pair_dir',
                'cluster_dir', 'step1_parameters_file', 'step2_parameters_file'],
        step3: ['celltype', 'counts_file', 'prepared_dir', 'pair_dir',
                'cluster_dir', 'phenotype_dir', 'step1_parameters_file',
                'step2_parameters_file', 'step3_parameters_file']
    ]
    def columns = columnsByStage[stage]
    if (columns == null) error "Unsupported upstream stage manifest: ${stage}"
    def orderedRows = rows.sort { left, right -> left[0].toString() <=> right[0].toString() }
    orderedRows.each { row ->
        if (row.size() != columns.size()) {
            error "${stage} manifest row has ${row.size()} fields; expected ${columns.size()}"
        }
    }
    def lines = [columns.join('\t')] + orderedRows.collect { row ->
        row.collect { value -> value.toString() }.join('\t')
    }
    def payload = lines.join('\n') + '\n'
    def encoded = payload.bytes.encodeBase64().toString()
    """
    printf '%s' '${encoded}' | base64 --decode > '${stage}.tsv'
    """
}
