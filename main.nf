#!/usr/bin/env nextflow

include { PREPARE_CELLTYPE }      from './modules/local/prepare_celltype'
include { RESOLVE_SAIGE_PARAMS }  from './modules/local/resolve_saige_params'
include { PLAN_PAIR_TASKS }       from './modules/local/plan_pair_tasks'
include { RUN_PAIR_TASK }         from './modules/local/run_pair_task'
include { MERGE_PAIR_TASKS }      from './modules/local/merge_pair_tasks'
include { CALL_CLUSTERS }         from './modules/local/call_clusters'
include { RUN_CLUSTER_PCA }       from './modules/local/run_cluster_pca'
include { BUILD_VARIANCE_RATIO }  from './modules/local/build_variance_ratio'
include { RUN_SAIGE_QTL }         from './modules/local/run_saige_qtl'
include { COLLECT_QTL_RESULTS }    from './modules/local/collect_qtl_results'
include { WRITE_RUN_METADATA }     from './modules/local/write_run_metadata'
include { VALIDATE_SAMPLESHEET }   from './modules/local/validate_samplesheet'

def requireParam(name, value) {
    if (value == null || value.toString().trim() == '') {
        error "Missing required parameter --${name}"
    }
}

def usageText() {
    return '''
sc-pcQTL: hurdle-based local multi-gene cis-QTL mapping

Required:
  --input PATH               CSV samplesheet: celltype,counts
  --gene_annotation PATH     TSV gene coordinates
  --genotype_prefix PREFIX   PLINK prefix with {chr}; required unless --run_qtl false

Execution:
  -profile docker|podman     macOS or Linux workstation
  -profile apptainer,slurm   Linux HPC with Slurm
  -profile apptainer,sge     Linux HPC with SGE/UGE

Core options:
  --pair_scope fast|complete
  --pair_test component_union|joint_score
  --covariates LIST         Comma-separated donor covariates; may be empty
  --saige_params PATH        Optional step,parameter,value override table
  --outdir PATH              Output directory (default: results)

Documentation: https://github.com/ZhouLabGenetics/sc-pcQTL
'''.stripIndent()
}

def parseTaskTable(taskFile, celltype) {
    def lines = taskFile.readLines()
    if (lines.size() <= 1) return []
    def header = lines[0].split('\t', -1)
    lines.drop(1).findAll { line -> line.trim() }.collect { line ->
        def values = line.split('\t', -1)
        def row = [header, values].transpose().collectEntries()
        tuple(celltype, row.task_id as Integer, row.chromosome as Integer,
              row.response_start as Integer, row.response_end as Integer,
              row.block_start as Integer, row.block_end as Integer)
    }
}

def parseQtlTable(pcaDir, celltype) {
    def taskFile = pcaDir.resolve('qtl_tasks.tsv')
    def lines = taskFile.readLines()
    if (lines.size() <= 1) return []
    def header = lines[0].split('\t', -1)
    lines.drop(1).findAll { line -> line.trim() }.collect { line ->
        def values = line.split('\t', -1)
        def row = [header, values].transpose().collectEntries()
        tuple(celltype, row.task_id as Integer, row.cluster_id, row.phenotype_id,
              row.chromosome as Integer, pcaDir.resolve(row.phenotype_file),
              pcaDir.resolve(row.region_file))
    }
}

workflow {
    if (params.help) {
        log.info usageText()
        return
    }
    requireParam('input', params.input)
    requireParam('gene_annotation', params.gene_annotation)
    if (!params.pair_scope.toString().matches('fast|complete')) error 'pair_scope must be fast or complete'
    if (!params.pair_test.toString().matches('component_union|joint_score')) error 'pair_test must be component_union or joint_score'
    if (!params.count_family.toString().matches('poisson|negative_binomial')) error 'count_family must be poisson or negative_binomial'
    if (params.pair_test == 'joint_score' && params.count_family != 'poisson') {
        error 'joint_score currently requires --count_family poisson'
    }
    if (params.min_cluster_genes as Integer > params.max_cluster_genes as Integer) {
        error 'min_cluster_genes cannot exceed max_cluster_genes'
    }
    if (params.run_qtl) {
        requireParam('genotype_prefix', params.genotype_prefix)
        if (!params.genotype_prefix.toString().contains('{chr}')) {
            error '--genotype_prefix must contain the {chr} placeholder'
        }
    }

    inputFile = file(params.input, checkIfExists: true)
    annotation = channel.value(file(params.gene_annotation, checkIfExists: true))
    workflowBin = channel.value(file("${projectDir}/bin", checkIfExists: true))
    VALIDATE_SAMPLESHEET(channel.value(inputFile), inputFile.parent.toString(), workflowBin)
    samples = VALIDATE_SAMPLESHEET.out.samplesheet
        .splitCsv(header: true, quote: '"')
        .map { row ->
            def celltype = row.get('celltype')
            def counts = row.get('counts')
            if (!celltype || !counts) {
                error "Validated samplesheet row lacks celltype/counts fields: ${row}"
            }
            tuple(celltype.toString(), file(counts.toString(), checkIfExists: true))
        }
    sampleCounts = samples.map { celltype, counts -> tuple(celltype, counts) }

    defaults = channel.value(file("${projectDir}/assets/saigeqtl_defaults.tsv", checkIfExists: true))
    userSaige = channel.value(file(params.saige_params ?: "${projectDir}/assets/empty_saige_params.tsv", checkIfExists: true))
    runParameters = new LinkedHashMap(params)
    runParameters.workflow_version = workflow.manifest.version
    runParameters.workflow = [
        project_name: workflow.projectName?.toString(),
        repository: workflow.repository?.toString(),
        revision: workflow.revision?.toString(),
        commit_id: workflow.commitId?.toString(),
        session_id: workflow.sessionId?.toString(),
        run_name: workflow.runName?.toString(),
        profile: workflow.profile?.toString(),
        command_line: workflow.commandLine?.toString(),
        nextflow_version: nextflow.version?.toString(),
        container_engine: workflow.containerEngine?.toString(),
        resume: workflow.resume as Boolean
    ]
    runParameters.configured_containers = [
        core: params.core_container?.toString(),
        saigeqtl: params.saige_container?.toString()
    ]

    WRITE_RUN_METADATA(channel.value(runParameters))
    PREPARE_CELLTYPE(samples, annotation, workflowBin)
    RESOLVE_SAIGE_PARAMS(defaults, userSaige, workflowBin)
    PLAN_PAIR_TASKS(PREPARE_CELLTYPE.out.stage, workflowBin)

    pairRows = PLAN_PAIR_TASKS.out.tasks.flatMap { celltype, taskFile -> parseTaskTable(taskFile, celltype) }
    pairInputs = pairRows.combine(PREPARE_CELLTYPE.out.stage, by: 0)
    RUN_PAIR_TASK(pairInputs, workflowBin)

    pairGroups = RUN_PAIR_TASK.out.result
        .map { celltype, _taskId, result -> tuple(celltype, result) }
        .groupTuple()
        .join(PREPARE_CELLTYPE.out.stage)
    MERGE_PAIR_TASKS(pairGroups, workflowBin)

    clusterInputs = MERGE_PAIR_TASKS.out.pairs.join(PREPARE_CELLTYPE.out.stage)
    CALL_CLUSTERS(clusterInputs, workflowBin)
    pcaInputs = CALL_CLUSTERS.out.clusters
        .join(PREPARE_CELLTYPE.out.stage)
        .join(sampleCounts)
    RUN_CLUSTER_PCA(pcaInputs, workflowBin)

    if (params.run_qtl) {
        genotypeBeds = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.bed', checkIfExists: true) }
        genotypeBims = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.bim', checkIfExists: true) }
        genotypeFams = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.fam', checkIfExists: true) }

        if (params.variance_ratio_prefix) {
            vrChannel = channel.value(tuple(
                file(params.variance_ratio_prefix + '.bed', checkIfExists: true),
                file(params.variance_ratio_prefix + '.bim', checkIfExists: true),
                file(params.variance_ratio_prefix + '.fam', checkIfExists: true)))
        } else {
            BUILD_VARIANCE_RATIO(channel.value(genotypeBeds), channel.value(genotypeBims), channel.value(genotypeFams), workflowBin)
            vrChannel = BUILD_VARIANCE_RATIO.out.plink
        }

        qtlRows = RUN_CLUSTER_PCA.out.pca.flatMap { celltype, pcaDir -> parseQtlTable(pcaDir, celltype) }
        qtlGenotypes = qtlRows.map { celltype, taskId, clusterId, phenotypeId, chromosome, phenotypeFile, regionFile ->
            def prefix = params.genotype_prefix.replace('{chr}', chromosome.toString())
            tuple(celltype, taskId, clusterId, phenotypeId, chromosome, phenotypeFile, regionFile,
                  file(prefix + '.bed', checkIfExists: true), file(prefix + '.bim', checkIfExists: true),
                  file(prefix + '.fam', checkIfExists: true))
        }
        qtlWithVr = qtlGenotypes.combine(vrChannel).combine(RESOLVE_SAIGE_PARAMS.out.table)
        RUN_SAIGE_QTL(qtlWithVr, workflowBin)
        qtlResults = RUN_SAIGE_QTL.out.result.map { _celltype, directory -> directory }.collect()
        COLLECT_QTL_RESULTS(qtlResults, workflowBin)
    }
}
