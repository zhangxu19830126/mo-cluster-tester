FROM matrixorigin/golang:1.19-ubuntu2204

WORKDIR /mo_test

COPY ./run_cluster_test.sh /mo_test/run_cluster_test.sh

ENTRYPOINT ["/mo_test/run_cluster_test.sh"]