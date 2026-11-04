FROM shinyoauthdb-local-runner:1 AS runner
RUN Rscript -e 'options(repos=c(CRAN="https://cloud.r-project.org")); install.packages("brickster", Ncpus=2L); stopifnot(requireNamespace("brickster", quietly=TRUE), packageVersion("brickster") >= "0.2.14")'
