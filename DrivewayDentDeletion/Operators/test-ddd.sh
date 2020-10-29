#!/bin/bash
#******************************************************************************
# Licensed Materials - Property of IBM
# (c) Copyright IBM Corporation 2019. All Rights Reserved.
#
# Note to U.S. Government Users Restricted Rights:
# Use, duplication or disclosure restricted by GSA ADP Schedule
# Contract with IBM Corp.
#******************************************************************************

#******************************************************************************
# PREREQUISITES:
#   - Logged into cluster on the OC CLI (https://docs.openshift.com/container-platform/4.4/cli_reference/openshift_cli/getting-started-cli.html)
#
# PARAMETERS:
#   -n : <NAMESPACE> (string), namespace for the e2e test for DDD. Defaults to "cp4i"
#   -r : <REPO> (string), Defaults to 'https://github.com/IBM/cp4i-deployment-samples.git'
#   -b : <BRANCH> (string), Defaults to 'main'
#
# USAGE:
#   With defaults values
#     ./test-e2e.sh
#
#   Overriding the default paramters
#     ./test-e2e.sh -n <NAMESPACE> -r <FORKED_REPO> -b <BRANCH>
#

function divider() {
    echo -e "\n-------------------------------------------------------------------------------------------------------------------\n" | add_date_for_log
}

function usage() {
    echo -e "\nUsage: $0 -n <NAMESPACE> -r <FORKED_REPO> -b <BRANCH>"
    divider
    exit 1
}

function add_date_for_log() {
    while IFS= read -r line; do
        printf '%s %s\n' "$(date)" "$line"
    done
}

NAMESPACE="cp4i"
CURRENT_DIR=$(dirname $0)
TICK="\xE2\x9C\x85"
CROSS="\xE2\x9D\x8C"
ALL_DONE="\xF0\x9F\x92\xAF"
INFO="\xE2\x84\xB9"
MISSING_PARAMS="false"
BRANCH="main"
FORKED_REPO="https://github.com/IBM/cp4i-deployment-samples.git"
TKN_INSTALLED=false
JQ_INSTALLED=false

while getopts "n:r:b:" opt; do
    case ${opt} in
    n)
        NAMESPACE="$OPTARG"
        ;;
    r)
        FORKED_REPO="$OPTARG"
        ;;
    b)
        BRANCH="$OPTARG"
        ;;
    \?)
        usage
        ;;
    esac
done

if [[ -z "${NAMESPACE// /}" ]]; then
    echo -e "$CROSS ERROR: Driveway Dent deletion testing namespace is empty. Please provide a value for '-n' parameter." | add_date_for_log
    missingParams="true"
fi

if [[ -z "${FORKED_REPO// /}" ]]; then
    echo -e "$CROSS ERROR: Driveway Dent deletion testing repository is empty. Please provide a value for '-r' parameter." | add_date_for_log
    missingParams="true"
fi

if [[ -z "${BRANCH// /}" ]]; then
    echo -e "$CROSS ERROR: Driveway Dent deletion testing branch is empty. Please provide a value for '-b' parameter." | add_date_for_log
    missingParams="true"
fi

if [[ "$missingParams" == "true" ]]; then
    usage
fi

function print_pipelineruns_taskruns() {
    divider
    echo -e "$INFO INFO: Printing the pipelineruns in the '$NAMESPACE' namesapce...\n" | add_date_for_log
    $TKN pipelinerun list -n $NAMESPACE
    divider
    echo -e "$INFO INFO: Printing all the taskruns in the '$NAMESPACE' namesapce...'n" | add_date_for_log
    $TKN taskrun list -n $NAMESPACE
    divider
}

function wait_and_trigger_pipeline() {
    divider
    PIPELINE_TYPE=${1}
    URL=$(oc get route -n $NAMESPACE el-main-trigger-route --template='http://{{.spec.host}}')

    # Wait for upto 5 minutes for the event listener pod to be running
    time=0
    while [ "$(oc get pod -n $NAMESPACE | grep el-$PIPELINE_TYPE-event-listener | grep 1/1 | grep Running)" == "" ]; do
        if [ $time -gt 5 ]; then
            echo -e "$CROSS ERROR: The event listner pod could not be found or did not get to Running state within 5 minutes, below is the current list of pods in the '$NAMESPACE' namespace:\n'" | add_date_for_log
            oc get pods -n $NAMESPACE
            exit 1
        fi
        echo -e "$INFO INFO: Wait for upto 5 minutes for the event listener pod to be running to start the '$PIPELINE_TYPE' pipeline. Waited ${time} minute(s)." | add_date_for_log
        time=$((time + 1))
        sleep 60
    done
    divider
    echo -e "$INFO INFO: The event listener pod:\n" | add_date_for_log
    oc get pod -n $NAMESPACE | grep el-$PIPELINE_TYPE-event-listener | grep 1/1 | grep Running
    echo -e "\n$INFO INFO: The event listener pod is now in Running, going ahead to trigger the '$PIPELINE_TYPE' pipeline...\n" | add_date_for_log
    curl $URL
    divider
    echo -e "$INFO INFO: Printing the logs for the '$PIPELINE_TYPE' pipeline...\n" | add_date_for_log
    if ! $TKN pr logs --last -f; then
        echo -e "\n$CROSS ERROR: Could not display the logs for the '$PIPELINE_TYPE' pipeline" | add_date_for_log
        divider
        exit 1
    fi
    divider
    PIPELINE_RUN_END_STATUS=$($TKN pipelinerun describe -n $NAMESPACE $($TKN pipelinerun list -n $NAMESPACE --limit 1 | sed -n 2p | awk '{print $1}') -o json | $JQ -r '.status.conditions[0].type')
    if [[ "$PIPELINE_RUN_END_STATUS" != "Succeeded" ]]; then
        echo -e "$CROSS ERROR: The '$PIPELINE_TYPE' pipeline run did not complete successfully.$CROSS"
        print_pipelineruns_taskruns
        exit 1
    else
        echo -e "$TICK INFO: The '$PIPELINE_TYPE' pipeline completed successfully."
    fi
}

function run_continous_load_script() {
    divider
    CONTINUOUS_LOAD_NAMESPACE=$1 #namespace
    APIC_ENABLED=$2              # apic enabled
    PIPELINE_TYPE=$3             # pipeline type

    echo -e "$INFO INFO Running the continuous-load.sh after '$PIPELINE_TYPE' pipeine with apic set to '$APIC_ENABLED' in the '$CONTINUOUS_LOAD_NAMESPACE' namespace..." | add_date_for_log
    if [ $APIC_ENABLED ]; then
        if ! $CURRENT_DIR/continuous-load.sh -n $CONTINUOUS_LOAD_NAMESPACE -a -z | add_date_for_log; then
            echo -e "$CROSS ERROR: Could not start or finish the continuous load testing." | add_date_for_log
            divider
            exit 1
        fi
    else
        if ! $CURRENT_DIR/continuous-load.sh -n $CONTINUOUS_LOAD_NAMESPACE -z | add_date_for_log; then
            echo -e "$CROSS ERROR: Could not start or finish the continuous load testing." | add_date_for_log
            divider
            exit 1
        fi
    fi
    divider
}

divider
echo -e "$INFO Current directory: $CURRENT_DIR" | add_date_for_log
echo -e "$INFO Driveway Dent deletion testing namespace: $NAMESPACE" | add_date_for_log
echo -e "$INFO Driveway Dent deletion testing repository: $FORKED_REPO" | add_date_for_log
echo -e "$INFO Driveway Dent deletion testing branch: $BRANCH" | add_date_for_log
divider

oc project $NAMESPACE

divider

# -------------------------------------- INSTALL JQ ---------------------------------------------------------------------

echo -e "\nINFO: Checking if jq is pre-installed..." | add_date_for_log
jqVersionCheck=$(jq --version)

if [ $? -eq 0 ]; then
    JQ_INSTALLED=true
fi

JQ=jq
if [[ "$JQ_INSTALLED" == "false" ]]; then
    echo "INFO: JQ is not installed, installing jq..." | add_date_for_log
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "INFO: Installing on linux" | add_date_for_log
        wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
        chmod +x ./jq
        JQ=./jq
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "INFO: Installing on MAC" | add_date_for_log
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        brew install jq
    fi
fi

echo -e "\n$TICK INFO: Installed JQ version is $($JQ --version)" | add_date_for_log

divider

# -------------------------------------- INSTALL TKN ---------------------------------------------------------------------

echo -e "$INFO INFO: Checking if tekton-cli is pre-installed...\n" | add_date_for_log
TKN=tkn
$TKN version

if [ $? -eq 0 ]; then
    TKN_INSTALLED=true
fi

if [[ "$TKN_INSTALLED" == "false" ]]; then
    echo -e "$INFO INFO: Installing tekton cli..." | add_date_for_log
    if [[ $(uname) == Darwin ]]; then
        echo -e "$INFO INFO: Installing on MAC" | add_date_for_log
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        brew tap tektoncd/tools
        brew install tektoncd/tools/tektoncd-cli
    else
        echo -e "$INFO INFO: Installing on Linux" | add_date_for_log
        # Get the tar
        curl -LO https://github.com/tektoncd/cli/releases/download/v0.12.0/tkn_0.12.0_Linux_x86_64.tar.gz
        # Extract tkn to current directory
        tar xvzf tkn_0.12.0_Linux_x86_64.tar.gz -C . tkn
        UNTAR_STATUS=$(echo $?)
        if [[ "$UNTAR_STATUS" -ne 0 ]]; then
            echo -e "\n$CROSS ERROR: Could not extract the tar for 'tkn'" | add_date_for_log
            exit 1
        fi

        chmod +x ./tkn
        CHMOD_STATUS=$(echo $?)
        if [[ "$CHMOD_STATUS" -ne 0 ]]; then
            echo -e "\n$CROSS ERROR: Could not make the 'tkn' executable" | add_date_for_log
            exit 1
        fi

        TKN=./tkn
    fi
fi

divider

# -------------------------------------------- DEV PIPELINE RUN -----------------------------------------------------------

echo -e "$INFO INFO: Applying the dev pipeline resources...\n" | add_date_for_log
if ! $CURRENT_DIR/cicd-apply-dev-pipeline.sh -n $NAMESPACE -r $FORKED_REPO -b $BRANCH; then
    echo -e "$CROSS ERROR: Could not apply the dev pipeline and related resources." | add_date_for_log
    exit 1
fi

if ! wait_and_trigger_pipeline "dev"; then
    echo -e "$CROSS ERROR: Exited during the 'dev' pipelinerun testing phase." | add_date_for_log
    exit 1
fi

if ! run_continous_load_script "$NAMESPACE" "false" "dev"; then
    echo -e "$CROSS ERROR: Continuous load script did not run successfully in the '$NAMESPACE' namespace for 'dev' pipeline without apic" | add_date_for_log
fi

# -------------------------------------------- TEST PIPELINE RUN ----------------------------------------------------------

echo -e "$INFO INFO: Applying the test pipeline resources...\n" | add_date_for_log
if ! $CURRENT_DIR/cicd-apply-test-pipeline.sh -n $NAMESPACE -r $FORKED_REPO -b $BRANCH; then
    echo -e "$CROSS ERROR: Could not apply the test pipeline and related resources." | add_date_for_log
    exit 1
fi

if ! wait_and_trigger_pipeline "test"; then
    echo -e "$CROSS ERROR: Exited during the 'test' pipelinerun testing phase." | add_date_for_log
    exit 1
fi

if ! run_continous_load_script "$NAMESPACE" "false" "test"; then
    echo -e "$CROSS ERROR: Continuous load script did not run successfully in the '$NAMESPACE' namespace for 'test' pipeline without apic" | add_date_for_log
fi

if ! run_continous_load_script "$NAMESPACE-ddd-test" "false" "test"; then
    echo -e "$CROSS ERROR: Continuous load script did not run successfully in the '$NAMESPACE' namespace for 'test' pipeline without apic" | add_date_for_log
fi

# -------------------------------------------- TEST APIC PIPELINE RUN -----------------------------------------------------

echo -e "$INFO INFO: Applying the test pipeline resources...\n" | add_date_for_log
if ! $CURRENT_DIR/cicd-apply-test-apic-pipeline.sh -n $NAMESPACE -r $FORKED_REPO -b $BRANCH; then
    echo -e "$CROSS ERROR: Could not apply the test pipeline and related resources." | add_date_for_log
    exit 1
fi

if ! wait_and_trigger_pipeline "test-apic"; then
    echo -e "$CROSS ERROR: Exited during the 'test-apic' pipelinerun testing phase." | add_date_for_log
    exit 1
fi

if ! run_continous_load_script "$NAMESPACE" "true" "test-apic"; then
    echo -e "$CROSS ERROR: Continuous load script did not run successfully in the '$NAMESPACE' namespace for 'test-apic' pipeline with apic" | add_date_for_log
fi

if ! run_continous_load_script "$NAMESPACE-ddd-test" "true" "test-apic"; then
    echo -e "$CROSS ERROR: Continuous load script did not run successfully in the '$NAMESPACE' namespace for 'test-apic' pipeline with apic" | add_date_for_log
fi

# -------------------------------------------PRINT PIPELINERUN, TASKRUN, EXIT ---------------------------------------------
print_pipelineruns_taskruns

echo -e "$TICK $ALL_DONE INFO: The DDD E2E test ran successfully $ALL_DONE $TICK" | add_date_for_log

divider
