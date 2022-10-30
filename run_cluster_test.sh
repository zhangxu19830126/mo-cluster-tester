#!/bin/bash

MO_REPO=matrixorigin
MO_BRANCH=main
MO_SRC=
TEST_COUNT=1
TEST_TIMEOUT=30m

while getopts ":r:b:c:t:s:" optname
do
    case "$optname" in
      "r")
        MO_REPO=$OPTARG
        ;;
      "b")
        MO_BRANCH=$OPTARG
        ;;
      "s")
        MO_SRC=$OPTARG
        ;;
      "c")
        TEST_COUNT=$OPTARG
        ;;
      "t")
        TEST_TIMEOUT=$OPTARG
        ;;
      ":")
        echo "missing argument for option $OPTARG"
        exit 1
        ;;
      "?")
        echo "unsupported option $OPTARG"
        exit 1
        ;;
      *)
        echo "unknown error while processing options"
        exit 1
        ;;
    esac
done

BASE_DIR=$PWD/workspace
SRC_DIR=$BASE_DIR/src
BIN_DIR=$BASE_DIR/bin
# currently, test data not supoprt use specified dir
DATA_DIR=$BASE_DIR/data
LOG_DIR=$BASE_DIR/log

echo "start cluster test with:"
echo "    datadir : $BASE_DIR"
echo "    target  : $MO_SRC"
echo "    repo    : https://github.com/$MO_REPO/matrixone.git"
echo "    branch  : $MO_BRANCH"
echo "    count   : $TEST_COUNT"
echo "    timeout : $TEST_TIMEOUT"

function prepare() {
    echo "prepare test"
    rm -rf $BASE_DIR
    mkdir -p $BASE_DIR
    mkdir -p $SRC_DIR
    mkdir -p $BIN_DIR
    mkdir -p $DATA_DIR
    mkdir -p $LOG_DIR
    echo "prepare test completed"
}

function clone() {
    if [ -n "$MO_SRC" ]
    then
        echo "skip clone, use exist mo: $MO_SRC"
        SRC_DIR=$MO_SRC
        return
    fi
    
    echo "starting clone mo"
    git clone https://github.com/$MO_REPO/matrixone.git $SRC_DIR
    echo "clone mo completed"
    cd $SRC_DIR
    git checkout $MO_BRANCH
    echo "switch to target branch"
}

function build_tester() {
    echo "starting build test"
    cd $SRC_DIR
    make cgo
    rm -rf $BASE_DIR/bin/*
    CGO_CFLAGS="-I${SRC_DIR}/cgo" CGO_LDFLAGS="-L${SRC_DIR}/cgo -lmo" go test -c -o $BIN_DIR/service-tester -timeout $TEST_TIMEOUT -race github.com/matrixorigin/matrixone/pkg/tests/service
    CGO_CFLAGS="-I${SRC_DIR}/cgo" CGO_LDFLAGS="-L${SRC_DIR}/cgo -lmo" go test -c -o $BIN_DIR/txn-tester -timeout $TEST_TIMEOUT -race github.com/matrixorigin/matrixone/pkg/tests/txn
    echo "build test completed"
}

function run() {
    echo "starting run test"
    $BASE_DIR/bin/service-tester -test.timeout $TEST_TIMEOUT -test.count=1 &> $LOG_DIR/current_service.log
    $BASE_DIR/bin/txn-tester -test.timeout $TEST_TIMEOUT -test.count=1 &> $LOG_DIR/current_txn.log
    echo "run test completed"
}

function check() {
    v=`tail -n 1 $LOG_DIR/current_service.log`
    if [ "$v" != "PASS" ]
    then
        return 1
    fi

    v=`tail -n 1 $LOG_DIR/current_txn.log`
    if [ "$v" != "PASS" ]
    then
        return 1
    fi

    return 0
}

prepare
clone
build_tester     

for i in `seq 1 $TEST_COUNT`
do
    rm -rf $DATA_DIR/mo-data
    run
    check
    v=$?
    if [ $v == 1 ]
    then
        tar zcvf $LOG_DIR/failed_$i.tgz $LOG_DIR/current_service.log $LOG_DIR/current_txn.log 
        rm -rf $LOG_DIR/current_service.log $LOG_DIR/current_txn.log 
        echo "test $i failed"
    fi
done