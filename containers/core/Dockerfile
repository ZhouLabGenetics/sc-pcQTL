FROM rocker/r-ver:4.5.1@sha256:55be3ae296dd21b6f2da705be44804ba7eb2ab2233a7050730506d7e64e8feda

LABEL org.opencontainers.image.source="https://github.com/ZhouLabGenetics/sc-pcQTL"
LABEL org.opencontainers.image.description="Core R environment for sc-pcQTL"

ARG CRAN_REPO=https://packagemanager.posit.co/cran/2026-08-14

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git libcurl4-openssl-dev libssl-dev libxml2-dev \
      libopenblas-dev libuv1-dev pkg-config zlib1g-dev plink1.9 ca-certificates \
    && ln -s /usr/bin/plink1.9 /usr/local/bin/plink \
    && rm -rf /var/lib/apt/lists/*

RUN R -q -e "install.packages(c('data.table','R.utils','Rcpp','RcppArmadillo','RcppEigen','BH','fastglm','roptim','testthat','remotes'), repos='${CRAN_REPO}')" \
    && R -q -e "options(repos=c(CRAN='${CRAN_REPO}')); remotes::install_github('mkanai/fasthurdle@72c2cd7a91208d6285c52a80f198f045ba51b5d7', upgrade='never')" \
    && R -q -e "required <- c('data.table','R.utils','Rcpp','RcppArmadillo','RcppEigen','BH','fastglm','roptim','testthat','fs','pkgload','remotes','fasthurdle'); missing <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]; if (length(missing)) stop('Missing required R packages: ', paste(missing, collapse=', ')); stopifnot(as.character(packageVersion('fasthurdle')) == '1.2.0')" \
    && R -q -e "path <- tempfile(fileext='.tsv.gz'); data.table::fwrite(data.table::data.table(id=1:3, value=c('a','b','c')), path, sep='\t', compress='gzip'); observed <- data.table::fread(path); stopifnot(file.size(path) > 0, nrow(observed) == 3L, identical(observed\$value, c('a','b','c')))" \
    && plink --version >/dev/null \
    && mkdir -p /opt/scpcqtl/manifest \
    && printf '%s\n' "${CRAN_REPO}" > /opt/scpcqtl/manifest/CRAN-repository.txt \
    && R -q -e "packages <- as.data.frame(installed.packages()[, c('Package','Version','LibPath')]); write.table(packages, '/opt/scpcqtl/manifest/R-packages.tsv', sep='\t', quote=FALSE, row.names=FALSE); writeLines(capture.output(sessionInfo()), '/opt/scpcqtl/manifest/sessionInfo.txt')"
