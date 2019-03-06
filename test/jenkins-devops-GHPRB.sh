#!/bin/bash
# We expect $KITCHEN_TEST_SCRIPT to point 
# to the script running the tests.
#
# Variable $ghprbCommentBody is set by Github Pull Request builder
# with the comment body. We will parse out COOKBOOK_NAME
# 

source ~/.bashrc

# parse out COOKBOOK_NAME from $ghprbCommentBody
COOKBOOK_NAME=${ghprbCommentBody#*kitchen test docker in cookbook} # rm trigger prefix
COOKBOOK_NAME=${COOKBOOK_NAME%please*}                             # rm trigger suffix
COOKBOOK_NAME=${COOKBOOK_NAME# }                                   # rm leading blank
COOKBOOK_NAME=${COOKBOOK_NAME% }                                   # rm trailing blank
export COOKBOOK_NAME

echo "  ********************** "
echo " ** Comment Body: '$ghprbCommentBody' "
echo " ** PR link: '$ghprbPullLink'"
echo " ** PR Title: '$ghprbPullTitle	'"
echo " ** Branch name: '$BRANCH_NAME'"
echo " ** Test script: '$KITCHEN_TEST_SCRIPT'"
echo " ** Cookbook name: '$COOKBOOK_NAME'"
echo "  ********************** "


if [ ${#KITCHEN_TEST_SCRIPT} == 0 ]; then
  echo " ** ERROR: Variable KITCHEN_TEST_SCRIPT is empty!"
  exit 1001
fi

if [ -f $KITCHEN_TEST_SCRIPT ]; then
  echo " ** Running: '$KITCHEN_TEST_SCRIPT $COOKBOOK_NAME'"
  bash $KITCHEN_TEST_SCRIPT $COOKBOOK_NAME
else
  echo " ** ERROR: script '$KITCHEN_TEST_SCRIPT' not found!"
  exit 1002
fi

