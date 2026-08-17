FROM wzhou88/saigeqtl:0.3.4@sha256:9a09d3641697e95672156cddc95af4febacc58cacfa8c4de55576756b658850e

LABEL org.opencontainers.image.source="https://github.com/ZhouLabGenetics/sc-pcQTL"
LABEL org.opencontainers.image.description="Pinned SAIGE-QTL 0.3.4 environment for sc-pcQTL"

RUN command -v step1_fitNULLGLMM_qtl.R \
    && command -v step2_tests_qtl.R \
    && command -v step3_gene_pvalue_qtl.R
