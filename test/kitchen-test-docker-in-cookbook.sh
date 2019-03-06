#!/bin/bash
#
# Purpose: Run 'kitchen docker test' in a specific cookbook
# Prerequests: Environment variable COOKBOOK_NAME should point
#              to an existing cookbook in chef-repo/cookbooks/$COOKBOOK_NAME
#
# Example: export COOKBOOK_NAME="user-wrapper"; test/kitchen-test-docker-in-cookbook.sh
#

source ~/.bashrc

# remember where we started
REPO_PATH=$(pwd)
cd $REPO_PATH

COOKBOOK_PATH="cookbooks/$COOKBOOK_NAME"
TEST_COMMAND="kitchen test docker"
TEST_DESTROY_COMMAND="kitchen destroy docker"
TEST_RESULT=0

if [ -d ${COOKBOOK_PATH} ]; then
  echo " ** Running '$TEST_COMMAND' in folder '$COOKBOOK_PATH'"
  cd "$COOKBOOK_PATH"
  $TEST_COMMAND
  TEST_RESULT=$?
  if [  $TEST_RESULT != 0 ]; then
      echo " ERROR '$TEST_RESULT': Running '$TEST_COMMAND' in folder '$COOKBOOK_PATH' failed!"
      $TEST_DESTROY_COMMAND
      exit $TEST_RESULT
  fi
  cd  $REPO_PATH
else
  echo " ** Sorry: No test found!"
  exit 100
fi
