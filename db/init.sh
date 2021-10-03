#!/bin/bash
set -xe
set -o pipefail

CURRENT_DIR=$(cd $(dirname $0);pwd)
export JOB_DB_HOST=${DB_HOST:-127.0.0.1}
export JOB_DB_PORT=${DB_PORT:-3306}
export JOB_DB_USER=${DB_USER:-isucon}
export JOB_DB_DBNAME=${DB_DBNAME:-isuumo}
export JOB_DB_PWD=${DB_PASS:-isucon}
export LANG="C.UTF-8"
cd $CURRENT_DIR

cat 0_Schema.sql 1_DummyEstateData.sql 2_DummyChairData.sql | mysql --defaults-file=/dev/null -h $JOB_DB_HOST -P $JOB_DB_PORT -u $JOB_DB_USER $JOB_DB_DBNAME
