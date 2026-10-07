#!/bin/bash
#
# This assumes all of the OS-level configuration has been completed and git repo has already been cloned
#
# This script should be run from the source directory
# cd source
# ./run-unit-tests.sh
#

["$DEBUG" == 'true' ] && set -x
set -e

# Get reference for all important folders
source_dir="$PWD"
terraform_dir="$source_dir/../terraform"
services_dir="$source_dir/services"

echo "------------------------------------------------------------------------------"
echo "[Pre-Test] build binaries"
echo "------------------------------------------------------------------------------"
cd $services_dir/transformer
npm run build:all

echo "------------------------------------------------------------------------------"
echo "[Test] Terraform"
echo "------------------------------------------------------------------------------"
cd $terraform_dir
terraform fmt -recursive -check
terraform init -backend=false -input=false
terraform validate
terraform test

echo "------------------------------------------------------------------------------"
echo "[Test] transformer"
echo "------------------------------------------------------------------------------"
cd $services_dir/transformer
npm run test
