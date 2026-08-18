process WRITE_RUN_METADATA {
    tag 'run metadata'
    label 'process_low'
    publishDir "${params.outdir}/pipeline_info${params.execution_name ? '/' + params.execution_name : ''}",
        mode: 'copy', overwrite: true

    input:
    val run_parameters

    output:
    path 'analysis_parameters.json', emit: parameters

    script:
    def payload = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(run_parameters))
    def encoded = payload.bytes.encodeBase64().toString()
    """
    printf '%s' '${encoded}' | base64 --decode > analysis_parameters.json
    """
}
