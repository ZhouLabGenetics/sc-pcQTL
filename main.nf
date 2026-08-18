#!/usr/bin/env nextflow

include { PREPARE_CELLTYPE }              from './modules/local/prepare_celltype'
include { RESOLVE_SAIGE_PARAMS }          from './modules/local/resolve_saige_params'
include { PLAN_PAIR_TASKS }               from './modules/local/plan_pair_tasks'
include { RUN_PAIR_TASK }                 from './modules/local/run_pair_task'
include { MERGE_PAIR_TASKS }              from './modules/local/merge_pair_tasks'
include { CALL_CLUSTERS }                 from './modules/local/call_clusters'
include { RUN_CLUSTER_PCA }               from './modules/local/run_cluster_pca'
include { COLLECT_QTL_TASKS }             from './modules/local/collect_qtl_tasks'
include { BUILD_VARIANCE_RATIO }          from './modules/local/build_variance_ratio'
include { RUN_SAIGE_STEP1 }               from './modules/local/run_saige_step1'
include { RUN_SAIGE_STEP2 }               from './modules/local/run_saige_step2'
include { RUN_SAIGE_STEP3 }               from './modules/local/run_saige_step3'
include { WRITE_SAIGE_STAGE_MANIFEST }    from './modules/local/write_saige_stage_manifest'
include { WRITE_UPSTREAM_STAGE_MANIFEST } from './modules/local/write_upstream_stage_manifest'
include { COLLECT_QTL_RESULTS }           from './modules/local/collect_qtl_results'
include { WRITE_RUN_METADATA }            from './modules/local/write_run_metadata'
include { VALIDATE_SAMPLESHEET }          from './modules/local/validate_samplesheet'

def requireParam(name, value) {
    if (value == null || value.toString().trim() == '') {
        error "Missing required parameter --${name}"
    }
}

def booleanParam(name, value) {
    if (value instanceof Boolean) return value
    def normalized = value?.toString()?.trim()?.toLowerCase()
    if (normalized == 'true') return true
    if (normalized == 'false') return false
    error "--${name} must be true or false; received '${value}'"
}

def requireGenotypePrefix(value) {
    requireParam('genotype_prefix', value)
    if (!value.toString().contains('{chr}')) {
        error '--genotype_prefix must contain the {chr} placeholder'
    }
}

def requireStageExecution(stageName) {
    if (params.execution_name != stageName ||
        !booleanParam('publish_saige_intermediates', params.publish_saige_intermediates)) {
        error "${stageName} must set --execution_name ${stageName} and --publish_saige_intermediates true; use sc-pcqtl saige"
    }
}

def requireUpstreamStageExecution(stageName) {
    if (params.execution_name != stageName ||
        !booleanParam('publish_upstream_intermediates', params.publish_upstream_intermediates)) {
        error "${stageName} must set --execution_name ${stageName} and --publish_upstream_intermediates true; use sc-pcqtl upstream"
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
  --covariates LIST          Comma-separated donor covariates; may be empty
  --saige_params PATH        Optional step,parameter,value override table
  --outdir PATH              Output directory (default: results)

The standard interface runs the complete workflow in one command. Advanced
manifest-driven and HPC execution is documented in docs/large-scale.md.

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

def parsePcaQtlTable(pcaDir, celltype, publishedPhenotypeRoot) {
    def taskFile = pcaDir.resolve('qtl_tasks.tsv')
    def lines = taskFile.readLines()
    if (lines.size() <= 1) return []
    def header = lines[0].split('\t', -1)
    lines.drop(1).findAll { line -> line.trim() }.collect { line ->
        def values = line.split('\t', -1)
        def row = [header, values].transpose().collectEntries()
        def taskId = "${celltype}__${row.cluster_id}__${row.phenotype_id}"
        def phenotypeSource = new File(publishedPhenotypeRoot, "${celltype}/${row.phenotype_file}").absolutePath
        def regionSource = new File(publishedPhenotypeRoot, "${celltype}/${row.region_file}").absolutePath
        tuple(taskId, celltype, row.cluster_id, row.phenotype_id,
              row.chromosome as Integer, phenotypeSource, regionSource,
              pcaDir.resolve(row.phenotype_file), pcaDir.resolve(row.region_file))
    }
}

def openTextReader(path) {
    def stream = java.nio.file.Files.newInputStream(path)
    if (path.toString().toLowerCase().endsWith('.gz')) {
        stream = new java.util.zip.GZIPInputStream(stream)
    }
    new java.io.BufferedReader(new java.io.InputStreamReader(stream, java.nio.charset.StandardCharsets.UTF_8))
}

def resolveManifestPath(manifestFile, rawValue, column, rowNumber) {
    def value = rawValue?.toString()?.trim()
    if (!value) error "Manifest row ${rowNumber} has an empty ${column}"
    if (value.contains('\t') || value.contains('\n') || value.contains('\r')) {
        error "Manifest row ${rowNumber} has an invalid ${column} path"
    }
    def path = java.nio.file.Paths.get(value)
    if (!path.isAbsolute()) path = manifestFile.parent.resolve(path)
    path = path.toAbsolutePath().normalize()
    if (!java.nio.file.Files.isRegularFile(path) || java.nio.file.Files.size(path) == 0L) {
        error "Manifest row ${rowNumber} references a missing or empty ${column}: ${path}"
    }
    path.toString()
}

def validatePhenotypeFile(pathString, phenotypeId, rowNumber) {
    def path = java.nio.file.Paths.get(pathString)
    def reader = openTextReader(path)
    def headerLine = reader.readLine()
    reader.close()
    if (headerLine == null) error "Manifest row ${rowNumber} has an empty phenotype table: ${path}"
    def header = headerLine.replaceAll('\\r$', '').split('\t', -1) as List
    if (!header.contains('individual') || !header.contains(phenotypeId)) {
        error "Manifest row ${rowNumber} phenotype table must contain individual and ${phenotypeId}: ${path}"
    }
}

def validateRegionFile(pathString, chromosome, rowNumber) {
    def path = java.nio.file.Paths.get(pathString)
    def reader = openTextReader(path)
    def lines = reader.readLines()
    reader.close()
    def fields = null
    lines.each { rawLine ->
        def line = rawLine.replaceAll('\\r$', '').trim()
        def candidate = line ? line.split('\t', -1) : []
        if (fields == null && candidate.size() >= 3 && candidate[0].replaceFirst('^chr', '') ==~ /[0-9]+/) {
            fields = candidate
        }
    }
    if (fields == null) error "Manifest row ${rowNumber} has no valid chromosome/start/end record: ${path}"
    def regionChromosome = fields[0].replaceFirst('^chr', '')
    if (regionChromosome.toInteger() != chromosome) {
        error "Manifest row ${rowNumber} region chromosome ${regionChromosome} does not match ${chromosome}: ${path}"
    }
    if (!(fields[1] ==~ /[0-9]+/) || !(fields[2] ==~ /[0-9]+/) ||
        fields[1].toLong() > fields[2].toLong()) {
        error "Manifest row ${rowNumber} has invalid region coordinates: ${path}"
    }
}

def parseSaigeManifest(manifestInput, stage) {
    def manifestFile = manifestInput.toAbsolutePath().normalize()
    def lines = manifestFile.readLines().findAll { line -> line.trim() }
    if (lines.size() < 2) error "${stage} manifest must contain a header and at least one task: ${manifestFile}"
    def header = lines[0].replaceAll('\\r$', '').split('\t', -1) as List
    if (header.size() != header.unique().size()) error "${stage} manifest has duplicate column names"

    def baseColumns = ['task_id', 'celltype', 'cluster_id', 'phenotype_id', 'chromosome',
                       'phenotype_file', 'region_file']
    def stageColumns = [
        qtl: [],
        step1: ['null_model_file', 'variance_ratio_file', 'variance_ratio_fam_file', 'saige_params_file'],
        step2: ['association_file', 'saige_params_file']
    ]
    if (!stageColumns.containsKey(stage)) error "Unsupported SAIGE manifest type: ${stage}"
    def required = baseColumns + stageColumns[stage]
    def missing = required.findAll { column -> !header.contains(column) }
    if (missing) error "${stage} manifest is missing columns: ${missing.join(', ')}"
    def pathColumns = (['phenotype_file', 'region_file'] + stageColumns[stage]).unique()
    def identifiers = ['task_id', 'celltype', 'cluster_id', 'phenotype_id']

    def rows = []
    lines.drop(1).eachWithIndex { line, index ->
        def rowNumber = index + 2
        def values = line.replaceAll('\\r$', '').split('\t', -1) as List
        if (values.size() != header.size()) {
            error "${stage} manifest row ${rowNumber} has ${values.size()} fields; expected ${header.size()}"
        }
        def row = [header, values].transpose().collectEntries()
        identifiers.each { column ->
            if (!(row[column] ==~ /[A-Za-z0-9][A-Za-z0-9_.-]*/)) {
                error "${stage} manifest row ${rowNumber} has an unsafe ${column}: ${row[column]}"
            }
        }
        if (!(row.chromosome ==~ /[0-9]+/) || row.chromosome.toInteger() < 1 || row.chromosome.toInteger() > 22) {
            error "${stage} manifest row ${rowNumber} chromosome must be 1-22: ${row.chromosome}"
        }
        row.chromosome = row.chromosome.toInteger()
        pathColumns.each { column ->
            row[column] = resolveManifestPath(manifestFile, row[column], column, rowNumber)
        }
        validatePhenotypeFile(row.phenotype_file, row.phenotype_id, rowNumber)
        validateRegionFile(row.region_file, row.chromosome as Integer, rowNumber)
        rows << row
    }
    def duplicateIds = rows.groupBy { row -> row.task_id }.findAll { _id, members -> members.size() > 1 }.keySet()
    if (duplicateIds) error "${stage} manifest has duplicate task_id values: ${duplicateIds.sort().join(', ')}"
    rows
}

def resolveManifestDirectory(manifestFile, rawValue, column, rowNumber, requiredFiles) {
    def value = rawValue?.toString()?.trim()
    if (!value) error "Manifest row ${rowNumber} has an empty ${column}"
    if (value.contains('\t') || value.contains('\n') || value.contains('\r')) {
        error "Manifest row ${rowNumber} has an invalid ${column} path"
    }
    def path = java.nio.file.Paths.get(value)
    if (!path.isAbsolute()) path = manifestFile.parent.resolve(path)
    path = path.toAbsolutePath().normalize()
    if (!java.nio.file.Files.isDirectory(path)) {
        error "Manifest row ${rowNumber} references a missing ${column}: ${path}"
    }
    requiredFiles.each { filename ->
        def requiredPath = path.resolve(filename)
        if (!java.nio.file.Files.isRegularFile(requiredPath) ||
            java.nio.file.Files.size(requiredPath) == 0L) {
            error "Manifest row ${rowNumber} ${column} is missing ${filename}: ${path}"
        }
    }
    path.toString()
}

def parseUpstreamManifest(manifestInput, stage) {
    def manifestFile = manifestInput.toAbsolutePath().normalize()
    def lines = manifestFile.readLines().findAll { line -> line.trim() }
    if (!lines) error "${stage} manifest must contain a header: ${manifestFile}"
    def header = lines[0].replaceAll('\\r$', '').split('\t', -1) as List
    if (header.size() != header.unique().size()) error "${stage} manifest has duplicate column names"

    def columnsByStage = [
        step1: ['celltype', 'counts_file', 'prepared_dir', 'pair_dir',
                'step1_parameters_file'],
        step2: ['celltype', 'counts_file', 'prepared_dir', 'pair_dir',
                'cluster_dir', 'step1_parameters_file', 'step2_parameters_file']
    ]
    if (!columnsByStage.containsKey(stage)) error "Unsupported upstream manifest type: ${stage}"
    def required = columnsByStage[stage]
    def missing = required.findAll { column -> !header.contains(column) }
    if (missing) error "${stage} manifest is missing columns: ${missing.join(', ')}"

    def rows = []
    lines.drop(1).eachWithIndex { line, index ->
        def rowNumber = index + 2
        def values = line.replaceAll('\\r$', '').split('\t', -1) as List
        if (values.size() != header.size()) {
            error "${stage} manifest row ${rowNumber} has ${values.size()} fields; expected ${header.size()}"
        }
        def row = [header, values].transpose().collectEntries()
        if (!(row.celltype ==~ /[A-Za-z0-9][A-Za-z0-9_.-]*/)) {
            error "${stage} manifest row ${rowNumber} has an unsafe celltype: ${row.celltype}"
        }
        row.counts_file = resolveManifestPath(manifestFile, row.counts_file, 'counts_file', rowNumber)
        row.prepared_dir = resolveManifestDirectory(
            manifestFile, row.prepared_dir, 'prepared_dir', rowNumber,
            ['celltype_qc.tsv', 'gene_filtering.tsv', 'count_blocks.tsv', 'covariates.rds', 'COMPLETE'])
        row.pair_dir = resolveManifestDirectory(
            manifestFile, row.pair_dir, 'pair_dir', rowNumber,
            ['all_computed_pairs.tsv.gz', 'significant_pairs.tsv.gz', 'pair_summary.tsv'])
        row.step1_parameters_file = resolveManifestPath(
            manifestFile, row.step1_parameters_file, 'step1_parameters_file', rowNumber)
        if (stage == 'step2') {
            row.cluster_dir = resolveManifestDirectory(
                manifestFile, row.cluster_dir, 'cluster_dir', rowNumber,
                ['clusters.tsv', 'cluster_genes.tsv', 'cluster_summary.tsv'])
            row.step2_parameters_file = resolveManifestPath(
                manifestFile, row.step2_parameters_file, 'step2_parameters_file', rowNumber)
        }
        rows << row
    }
    def duplicates = rows.groupBy { row -> row.celltype }
        .findAll { _celltype, members -> members.size() > 1 }.keySet()
    if (duplicates) error "${stage} manifest has duplicate celltype values: ${duplicates.sort().join(', ')}"
    rows
}

def requireUpstreamParameterMatch(rows, parameterFileColumn, parameterName, currentValue, stage) {
    rows.collect { row -> row[parameterFileColumn] }.unique().each { pathString ->
        def stored = new groovy.json.JsonSlurper().parse(new File(pathString))
        if (!stored.containsKey(parameterName)) {
            error "${stage} source parameters do not contain ${parameterName}: ${pathString}"
        }
        if (stored[parameterName]?.toString() != currentValue?.toString()) {
            error "${stage} requires --${parameterName} '${stored[parameterName]}' to match the preceding stage; received '${currentValue}'"
        }
    }
}

def runMetadata(parameters, workflowContext, entryName) {
    def metadata = new LinkedHashMap(parameters)
    metadata.workflow_version = workflowContext.manifest.version
    metadata.workflow_entry = entryName
    metadata.workflow = [
        project_name: workflowContext.projectName?.toString(),
        repository: workflowContext.repository?.toString(),
        revision: workflowContext.revision?.toString(),
        commit_id: workflowContext.commitId?.toString(),
        session_id: workflowContext.sessionId?.toString(),
        run_name: workflowContext.runName?.toString(),
        profile: workflowContext.profile?.toString(),
        command_line: workflowContext.commandLine?.toString(),
        nextflow_version: nextflow.version?.toString(),
        container_engine: workflowContext.containerEngine?.toString(),
        resume: workflowContext.resume as Boolean
    ]
    metadata.configured_containers = [
        core: metadata.get('core_container')?.toString(),
        saigeqtl: metadata.get('saige_container')?.toString()
    ]
    metadata
}

workflow UPSTREAM_STEP1 {
    requireUpstreamStageExecution('upstream_step1')
    requireParam('input', params.input)
    requireParam('gene_annotation', params.gene_annotation)
    if (!params.pair_scope.toString().matches('fast|complete')) error 'pair_scope must be fast or complete'
    if (!params.pair_test.toString().matches('component_union|joint_score')) error 'pair_test must be component_union or joint_score'
    if (!params.count_family.toString().matches('poisson|negative_binomial')) error 'count_family must be poisson or negative_binomial'
    if (params.pair_test == 'joint_score' && params.count_family != 'poisson') {
        error 'joint_score currently requires --count_family poisson'
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
            if (!celltype || !counts) error "Validated samplesheet row lacks celltype/counts fields: ${row}"
            tuple(celltype.toString(), file(counts.toString(), checkIfExists: true))
        }
    sampleCounts = samples.map { celltype, counts -> tuple(celltype, counts) }

    WRITE_RUN_METADATA(channel.value(runMetadata(params, workflow, 'UPSTREAM_STEP1')))
    PREPARE_CELLTYPE(samples, annotation, workflowBin)
    PLAN_PAIR_TASKS(PREPARE_CELLTYPE.out.stage, workflowBin)
    pairRows = PLAN_PAIR_TASKS.out.tasks.flatMap { celltype, taskFile -> parseTaskTable(taskFile, celltype) }
    pairInputs = pairRows.combine(PREPARE_CELLTYPE.out.stage, by: 0)
    RUN_PAIR_TASK(pairInputs, workflowBin)
    pairGroups = RUN_PAIR_TASK.out.result
        .map { celltype, _taskId, result -> tuple(celltype, result) }
        .groupTuple()
        .join(PREPARE_CELLTYPE.out.stage)
    MERGE_PAIR_TASKS(pairGroups, workflowBin)

    def publishedRoot = new File(params.outdir.toString()).absolutePath
    def step1Parameters = new File(
        publishedRoot, 'pipeline_info/upstream_step1/analysis_parameters.json').absolutePath
    completedRows = MERGE_PAIR_TASKS.out.pairs
        .join(PREPARE_CELLTYPE.out.stage)
        .join(sampleCounts)
        .map { celltype, _pairDir, _preparedDir, counts ->
            tuple(celltype, counts.toAbsolutePath().toString(),
                  new File(publishedRoot, "upstream/step1/prepared/${celltype}").absolutePath,
                  new File(publishedRoot, "pairs/${celltype}").absolutePath,
                  step1Parameters)
        }
        .collect(flat: false)
    WRITE_UPSTREAM_STAGE_MANIFEST(
        channel.value('step1'), completedRows, WRITE_RUN_METADATA.out.parameters)
}

workflow UPSTREAM_STEP2 {
    requireUpstreamStageExecution('upstream_step2')
    requireParam('upstream_step1_manifest', params.upstream_step1_manifest)
    if (params.min_cluster_genes as Integer > params.max_cluster_genes as Integer) {
        error 'min_cluster_genes cannot exceed max_cluster_genes'
    }

    manifestFile = file(params.upstream_step1_manifest, checkIfExists: true)
    rows = parseUpstreamManifest(manifestFile, 'step1')
    requireUpstreamParameterMatch(
        rows, 'step1_parameters_file', 'max_cluster_genes', params.max_cluster_genes, 'upstream step2')
    workflowBin = channel.value(file("${projectDir}/bin", checkIfExists: true))
    WRITE_RUN_METADATA(channel.value(runMetadata(params, workflow, 'UPSTREAM_STEP2')))

    clusterInputs = channel.fromList(rows).map { row ->
        tuple(row.celltype,
              file(row.pair_dir, checkIfExists: true),
              file(row.prepared_dir, checkIfExists: true))
    }
    rowMetadata = channel.fromList(rows).map { row ->
        tuple(row.celltype, row.counts_file, row.prepared_dir, row.pair_dir,
              row.step1_parameters_file)
    }
    CALL_CLUSTERS(clusterInputs, workflowBin)

    def publishedRoot = new File(params.outdir.toString()).absolutePath
    def step2Parameters = new File(
        publishedRoot, 'pipeline_info/upstream_step2/analysis_parameters.json').absolutePath
    completedRows = CALL_CLUSTERS.out.clusters
        .join(rowMetadata)
        .map { celltype, _clusterDir, countsFile, preparedDir, pairDir, step1Parameters ->
            tuple(celltype, countsFile, preparedDir, pairDir,
                  new File(publishedRoot, "clusters/${celltype}").absolutePath,
                  step1Parameters, step2Parameters)
        }
        .collect(flat: false)
    WRITE_UPSTREAM_STAGE_MANIFEST(
        channel.value('step2'), completedRows, WRITE_RUN_METADATA.out.parameters)
}

workflow UPSTREAM_STEP3 {
    requireUpstreamStageExecution('upstream_step3')
    requireParam('upstream_step2_manifest', params.upstream_step2_manifest)

    manifestFile = file(params.upstream_step2_manifest, checkIfExists: true)
    rows = parseUpstreamManifest(manifestFile, 'step2')
    requireUpstreamParameterMatch(
        rows, 'step1_parameters_file', 'covariates', params.covariates, 'upstream step3')
    workflowBin = channel.value(file("${projectDir}/bin", checkIfExists: true))
    WRITE_RUN_METADATA(channel.value(runMetadata(params, workflow, 'UPSTREAM_STEP3')))

    pcaInputs = channel.fromList(rows).map { row ->
        tuple(row.celltype,
              file(row.cluster_dir, checkIfExists: true),
              file(row.prepared_dir, checkIfExists: true),
              file(row.counts_file, checkIfExists: true))
    }
    rowMetadata = channel.fromList(rows).map { row ->
        tuple(row.celltype, row.counts_file, row.prepared_dir, row.pair_dir,
              row.cluster_dir, row.step1_parameters_file, row.step2_parameters_file)
    }
    RUN_CLUSTER_PCA(pcaInputs, workflowBin)
    pcaDirectories = RUN_CLUSTER_PCA.out.pca.map { _celltype, pcaDir -> pcaDir }.collect()
    COLLECT_QTL_TASKS(pcaDirectories, workflowBin)

    def publishedRoot = new File(params.outdir.toString()).absolutePath
    def step3Parameters = new File(
        publishedRoot, 'pipeline_info/upstream_step3/analysis_parameters.json').absolutePath
    completedRows = RUN_CLUSTER_PCA.out.pca
        .join(rowMetadata)
        .map { celltype, _pcaDir, countsFile, preparedDir, pairDir, clusterDir,
               step1Parameters, step2Parameters ->
            tuple(celltype, countsFile, preparedDir, pairDir, clusterDir,
                  new File(publishedRoot, "phenotypes/${celltype}").absolutePath,
                  step1Parameters, step2Parameters, step3Parameters)
        }
        .collect(flat: false)
    WRITE_UPSTREAM_STAGE_MANIFEST(
        channel.value('step3'), completedRows, WRITE_RUN_METADATA.out.parameters)
}

workflow SAIGE_STEP1 {
    requireStageExecution('saige_step1')
    requireParam('qtl_manifest', params.qtl_manifest)
    if (!params.variance_ratio_prefix) requireGenotypePrefix(params.genotype_prefix)

    manifestFile = file(params.qtl_manifest, checkIfExists: true)
    rows = parseSaigeManifest(manifestFile, 'qtl')
    workflowBin = channel.value(file("${projectDir}/bin", checkIfExists: true))
    qtlRows = channel.fromList(rows).map { row ->
        tuple(row.task_id, row.celltype, row.cluster_id, row.phenotype_id,
              row.chromosome as Integer, row.phenotype_file, row.region_file,
              file(row.phenotype_file, checkIfExists: true))
    }

    defaults = channel.value(file("${projectDir}/assets/saigeqtl_defaults.tsv", checkIfExists: true))
    userSaige = channel.value(file(params.saige_params ?: "${projectDir}/assets/empty_saige_params.tsv", checkIfExists: true))
    RESOLVE_SAIGE_PARAMS(defaults, userSaige, workflowBin)
    WRITE_RUN_METADATA(channel.value(runMetadata(params, workflow, 'SAIGE_STEP1')))

    def infoRoot = new File(params.outdir.toString(), "pipeline_info/${params.execution_name}").absolutePath
    def resolvedSource = new File(infoRoot, 'resolved_saigeqtl_params.tsv').absolutePath
    if (params.variance_ratio_prefix) {
        vrChannel = channel.value(tuple(
            file(params.variance_ratio_prefix + '.bed', checkIfExists: true),
            file(params.variance_ratio_prefix + '.bim', checkIfExists: true),
            file(params.variance_ratio_prefix + '.fam', checkIfExists: true)))
        vrFamSource = new File(params.variance_ratio_prefix.toString() + '.fam').absolutePath
    } else {
        genotypeBeds = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.bed', checkIfExists: true) }
        genotypeBims = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.bim', checkIfExists: true) }
        genotypeFams = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.fam', checkIfExists: true) }
        BUILD_VARIANCE_RATIO(channel.value(genotypeBeds), channel.value(genotypeBims), channel.value(genotypeFams), workflowBin)
        vrChannel = BUILD_VARIANCE_RATIO.out.plink
        vrFamSource = new File(infoRoot, 'variance_ratio/auto_vr.fam').absolutePath
    }

    step1Inputs = qtlRows.combine(vrChannel).combine(RESOLVE_SAIGE_PARAMS.out.table).map {
        taskId, celltype, clusterId, phenotypeId, chromosome, phenotypeSource, regionSource,
        phenotypeFile, vrBed, vrBim, vrFam, saigeParams ->
        tuple(taskId, celltype, clusterId, phenotypeId, chromosome,
              phenotypeSource, regionSource, phenotypeFile, vrBed, vrBim, vrFam,
              vrFamSource, saigeParams, resolvedSource)
    }
    RUN_SAIGE_STEP1(step1Inputs, workflowBin)
    stage1Directories = RUN_SAIGE_STEP1.out.result.map { _taskId, directory -> directory }.collect()
    WRITE_SAIGE_STAGE_MANIFEST(channel.value('step1'), stage1Directories, workflowBin)
}

workflow SAIGE_STEP2 {
    requireStageExecution('saige_step2')
    requireParam('step1_manifest', params.step1_manifest)
    requireGenotypePrefix(params.genotype_prefix)

    manifestFile = file(params.step1_manifest, checkIfExists: true)
    rows = parseSaigeManifest(manifestFile, 'step1')
    workflowBin = channel.value(file("${projectDir}/bin", checkIfExists: true))
    WRITE_RUN_METADATA(channel.value(runMetadata(params, workflow, 'SAIGE_STEP2')))

    step2Inputs = channel.fromList(rows).map { row ->
        def prefix = params.genotype_prefix.replace('{chr}', row.chromosome.toString())
        tuple(row.task_id, row.celltype, row.cluster_id, row.phenotype_id,
              row.chromosome as Integer, row.phenotype_file, row.region_file,
              file(row.region_file, checkIfExists: true),
              file(prefix + '.bed', checkIfExists: true),
              file(prefix + '.bim', checkIfExists: true),
              file(prefix + '.fam', checkIfExists: true),
              file(row.variance_ratio_fam_file, checkIfExists: true),
              file(row.null_model_file, checkIfExists: true),
              file(row.variance_ratio_file, checkIfExists: true),
              file(row.saige_params_file, checkIfExists: true), row.saige_params_file)
    }
    RUN_SAIGE_STEP2(step2Inputs, workflowBin)
    stage2Directories = RUN_SAIGE_STEP2.out.result.map { _taskId, directory -> directory }.collect()
    WRITE_SAIGE_STAGE_MANIFEST(channel.value('step2'), stage2Directories, workflowBin)
}

workflow SAIGE_STEP3 {
    requireStageExecution('saige_step3')
    requireParam('step2_manifest', params.step2_manifest)

    manifestFile = file(params.step2_manifest, checkIfExists: true)
    rows = parseSaigeManifest(manifestFile, 'step2')
    workflowBin = channel.value(file("${projectDir}/bin", checkIfExists: true))
    WRITE_RUN_METADATA(channel.value(runMetadata(params, workflow, 'SAIGE_STEP3')))

    step3Inputs = channel.fromList(rows).map { row ->
        tuple(row.task_id, row.celltype, row.cluster_id, row.phenotype_id,
              row.chromosome as Integer, row.phenotype_file, row.region_file,
              file(row.association_file, checkIfExists: true),
              file(row.saige_params_file, checkIfExists: true), row.saige_params_file)
    }
    RUN_SAIGE_STEP3(step3Inputs, workflowBin)
    stage3Directories = RUN_SAIGE_STEP3.out.result.map { _taskId, _celltype, directory -> directory }.collect()
    WRITE_SAIGE_STAGE_MANIFEST(channel.value('step3'), stage3Directories, workflowBin)
    COLLECT_QTL_RESULTS(stage3Directories, workflowBin)
}

workflow FULL_PIPELINE {
    def runQtl = booleanParam('run_qtl', params.run_qtl)
    if (booleanParam('help', params.help)) {
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
    if (runQtl) requireGenotypePrefix(params.genotype_prefix)

    inputFile = file(params.input, checkIfExists: true)
    annotation = channel.value(file(params.gene_annotation, checkIfExists: true))
    workflowBin = channel.value(file("${projectDir}/bin", checkIfExists: true))
    VALIDATE_SAMPLESHEET(channel.value(inputFile), inputFile.parent.toString(), workflowBin)
    samples = VALIDATE_SAMPLESHEET.out.samplesheet
        .splitCsv(header: true, quote: '"')
        .map { row ->
            def celltype = row.get('celltype')
            def counts = row.get('counts')
            if (!celltype || !counts) error "Validated samplesheet row lacks celltype/counts fields: ${row}"
            tuple(celltype.toString(), file(counts.toString(), checkIfExists: true))
        }
    sampleCounts = samples.map { celltype, counts -> tuple(celltype, counts) }

    defaults = channel.value(file("${projectDir}/assets/saigeqtl_defaults.tsv", checkIfExists: true))
    userSaige = channel.value(file(params.saige_params ?: "${projectDir}/assets/empty_saige_params.tsv", checkIfExists: true))
    WRITE_RUN_METADATA(channel.value(runMetadata(params, workflow, 'default')))
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
    pcaDirectories = RUN_CLUSTER_PCA.out.pca.map { _celltype, pcaDir -> pcaDir }.collect()
    COLLECT_QTL_TASKS(pcaDirectories, workflowBin)

    if (runQtl) {
        genotypeBeds = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.bed', checkIfExists: true) }
        genotypeBims = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.bim', checkIfExists: true) }
        genotypeFams = (1..22).collect { chr -> file(params.genotype_prefix.replace('{chr}', chr.toString()) + '.fam', checkIfExists: true) }
        def publishedPhenotypeRoot = new File(params.outdir.toString(), 'phenotypes').absolutePath
        def resolvedSource = new File(params.outdir.toString(), 'pipeline_info/resolved_saigeqtl_params.tsv').absolutePath

        if (params.variance_ratio_prefix) {
            vrChannel = channel.value(tuple(
                file(params.variance_ratio_prefix + '.bed', checkIfExists: true),
                file(params.variance_ratio_prefix + '.bim', checkIfExists: true),
                file(params.variance_ratio_prefix + '.fam', checkIfExists: true)))
            vrFamSource = new File(params.variance_ratio_prefix.toString() + '.fam').absolutePath
        } else {
            BUILD_VARIANCE_RATIO(channel.value(genotypeBeds), channel.value(genotypeBims), channel.value(genotypeFams), workflowBin)
            vrChannel = BUILD_VARIANCE_RATIO.out.plink
            vrFamSource = new File(params.outdir.toString(), 'pipeline_info/variance_ratio/auto_vr.fam').absolutePath
        }

        qtlRows = RUN_CLUSTER_PCA.out.pca.flatMap { celltype, pcaDir ->
            parsePcaQtlTable(pcaDir, celltype, publishedPhenotypeRoot)
        }
        step1Inputs = qtlRows.combine(vrChannel).combine(RESOLVE_SAIGE_PARAMS.out.table).map {
            taskId, celltype, clusterId, phenotypeId, chromosome, phenotypeSource, regionSource,
            phenotypeFile, _regionFile, vrBed, vrBim, vrFam, saigeParams ->
            tuple(taskId, celltype, clusterId, phenotypeId, chromosome,
                  phenotypeSource, regionSource, phenotypeFile, vrBed, vrBim, vrFam,
                  vrFamSource, saigeParams, resolvedSource)
        }
        RUN_SAIGE_STEP1(step1Inputs, workflowBin)

        qtlGenotypes = qtlRows.map {
            taskId, celltype, clusterId, phenotypeId, chromosome, phenotypeSource, regionSource,
            _phenotypeFile, regionFile ->
            def prefix = params.genotype_prefix.replace('{chr}', chromosome.toString())
            tuple(taskId, celltype, clusterId, phenotypeId, chromosome,
                  phenotypeSource, regionSource, regionFile,
                  file(prefix + '.bed', checkIfExists: true),
                  file(prefix + '.bim', checkIfExists: true),
                  file(prefix + '.fam', checkIfExists: true))
        }
        step2Inputs = qtlGenotypes.join(RUN_SAIGE_STEP1.out.result, by: 0)
            .combine(vrChannel)
            .combine(RESOLVE_SAIGE_PARAMS.out.table)
            .map {
                taskId, celltype, clusterId, phenotypeId, chromosome, phenotypeSource, regionSource,
                regionFile, bed, bim, fam, step1Dir, _vrBed, _vrBim, vrFam, saigeParams ->
                tuple(taskId, celltype, clusterId, phenotypeId, chromosome,
                      phenotypeSource, regionSource, regionFile, bed, bim, fam, vrFam,
                      step1Dir.resolve('saige_null_model.rda'),
                      step1Dir.resolve('saige_null_model.varianceRatio.txt'),
                      saigeParams, resolvedSource)
            }
        RUN_SAIGE_STEP2(step2Inputs, workflowBin)

        qtlMetadata = qtlRows.map {
            taskId, celltype, clusterId, phenotypeId, chromosome, phenotypeSource, regionSource,
            _phenotypeFile, _regionFile ->
            tuple(taskId, celltype, clusterId, phenotypeId, chromosome, phenotypeSource, regionSource)
        }
        step3Inputs = qtlMetadata.join(RUN_SAIGE_STEP2.out.result, by: 0)
            .combine(RESOLVE_SAIGE_PARAMS.out.table)
            .map {
                taskId, celltype, clusterId, phenotypeId, chromosome, phenotypeSource, regionSource,
                step2Dir, saigeParams ->
                tuple(taskId, celltype, clusterId, phenotypeId, chromosome,
                      phenotypeSource, regionSource, step2Dir.resolve('association.tsv'),
                      saigeParams, resolvedSource)
            }
        RUN_SAIGE_STEP3(step3Inputs, workflowBin)
        qtlResults = RUN_SAIGE_STEP3.out.result.map { _taskId, _celltype, directory -> directory }.collect()
        COLLECT_QTL_RESULTS(qtlResults, workflowBin)
    }
}

workflow {
    if (params.execution_stage == 'default') {
        FULL_PIPELINE()
    } else if (params.execution_stage == 'upstream_step1') {
        UPSTREAM_STEP1()
    } else if (params.execution_stage == 'upstream_step2') {
        UPSTREAM_STEP2()
    } else if (params.execution_stage == 'upstream_step3') {
        UPSTREAM_STEP3()
    } else if (params.execution_stage == 'saige_step1') {
        SAIGE_STEP1()
    } else if (params.execution_stage == 'saige_step2') {
        SAIGE_STEP2()
    } else if (params.execution_stage == 'saige_step3') {
        SAIGE_STEP3()
    } else {
        error "Unsupported --execution_stage: ${params.execution_stage}"
    }
}
