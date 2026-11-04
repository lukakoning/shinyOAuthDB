FROM shinyoauthdb-local-runner:1 AS runner
RUN Rscript -e 'options(repos=c(CRAN="https://cloud.r-project.org")); install.packages("RTrino", Ncpus=2L); stopifnot(requireNamespace("RTrino", quietly=TRUE), packageVersion("RTrino") >= "0.1.0")'
