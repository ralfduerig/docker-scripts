#!/bin/bash
#*******************************************************************************
# Copyright 2015 IBM
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
#*******************************************************************************
# preferred method for using this code is to source this file, then call the
# appropriate function.
# uncomment the next line to debug this script
#set -x
###################################################################
# protect against logging functions not being loaded #
# An older version of the extension will not have them loaded #
# Will default to just performing an echo with colors #
###################################################################
if [[ ! "$(declare -f -F log_and_echo)" ]]; then
echo "Setting up log_and_echo to just echo with color"
INFO="INFO_LEVEL"
LABEL="LABEL_LEVEL"
WARN="WARN_LEVEL"
ERROR="ERROR_LEVEL"
INFO_LEVEL=4
WARN_LEVEL=2
ERROR_LEVEL=1
OFF_LEVEL=0
log_and_echo() {
local MSG_TYPE="$1"
if [ "$INFO" == "$MSG_TYPE" ]; then
shift
local pre=""
local post=""
elif [ "$LABEL" == "$MSG_TYPE" ]; then
shift
local pre="${label_color}"
local post="${no_color}"
elif [ "$WARN" == "$MSG_TYPE" ]; then
shift
local pre="${label_color}"
local post="${no_color}"
elif [ "$ERROR" == "$MSG_TYPE" ]; then
shift
local pre="${red}"
local post="${no_color}"
else
#NO MSG type specified; fall through to INFO level
#Do not shift
local pre=""
local post=""
fi
local L_MSG=`echo -e "$*"`
echo -e "${pre}${L_MSG}${post}"
}
fi
###################################################################
# get list of container data in json format
# this function gets the group container data in json format.
# output:
# data: group container data in json
###################################################################
get_group_container_data_json() {
local data=$(ice --verbose group list | sed -n '/{/,/}/p')
local RESULT=$?
if [ $RESULT -ne 0 ] || [ -z "${data}" ]; then
return 1
else
echo ${data}
return 0
fi
}
###################################################################
# get_list_container_group_value_for_given_attribute
# this function will search for the list of the container group value of the give attribute.
# input:
# attribute: the attribute of the container data
# search_value: part of the value that used for the search
# output:
# container_value_list: array of the value for the give key and given the search_value
###################################################################
get_list_container_group_value_for_given_attribute() {
local attribute=$1
local search_value=$2
if [ -z "${attribute}" ] || [ -z "${search_value}" ]; then
return 1
fi
local counter=0
local index=2
local container_data="unknown"
export container_value_list=()
local container_data_list=$(get_group_container_data_json)
local RESULT=$?
if [ $RESULT -ne 0 ] || [ -z "${container_data_list}" ]; then
return 1
fi
while :
do
local container_data=$(echo $container_data_list | awk -F'[{}]' '{print $'$index';}')
if [ -z "${container_data}" ]; then
break
fi
local container_name=$(echo $container_data | awk -F''$attribute'":' '{print $2;}' | awk -F'"' '{print $2;}')
if [ "${container_name%_*}" == "${search_value}" ]; then
container_value_list[$counter]=$container_name
fi
let counter=counter+1;
let index=index+2;
done
echo ${container_value_list[@]}
return 0
}
###################################################################
# get_container_group_value_for_given_attribute
# this function will search for the value of the give attribute of the container data formatted in json.
# input:
# attribute: the attribute of the container data
# value: value of the give attribute
# search_attribute: the attribute that used to find the require value
# output:
# require_value: the value for the give search_attribute
###################################################################
get_container_group_value_for_given_attribute() {
local attribute=$1
local value=$2
local search_attribute=$3
if [ -z "${attribute}" ] || [ -z "${value}" ] || [ -z "${search_attribute}" ]; then
return 1
fi
local index=2
local container_data="unknown"
local container_data_list=$(get_group_container_data_json)
local RESULT=$?
if [ $RESULT -ne 0 ] || [ -z "${container_data_list}" ]; then
return 1
fi
while :
do
local container_data=$(echo $container_data_list | awk -F'[{}]' '{print $'$index';}')
if [ -z "${container_data}" ]; then
log_and_echo "$ERROR" "Container ${value} does not exist in output of the 'ice --verbose group list' command."
break
fi
local container_name=$(echo $container_data | awk -F''$attribute'":' '{print $2;}' | awk -F'"' '{print $2;}')
if [ "${container_name}" == "${value}" ]; then
export require_value=$(echo $container_data | awk -F''$search_attribute'":' '{print $2;}' | awk -F'"' '{print $2;}')
RESULT=$?
if [ $RESULT -ne 0 ] || [ -z "${require_value}" ]; then
log_and_echo "$ERROR" "Failed to get ${search_attribute} value, return code = ${RESULT}"
return 1
else
return 0
fi
fi
let index=index+2;
done
export require_value=""
return 1
}
###################################################################
# get port numbers
###################################################################
get_port_numbers() {
local PORT_NUM=$1
local RETVAL=""
local OIFS=$IFS
# check for port as a number separate by commas and replace commas with --publish
check_num='^[[:digit:][:space:],,]+$'
if ! [[ "$PORT_NUM" =~ $check_num ]] ; then
echo -e "${red}PORT value is not a number. It should be number separated by commas. Defaulting to port 80 and continue deploy process.${no_color}" >&2
PORT_NUM=80
fi
# let commas split as well as whitespace
set -f; IFS=$IFS+","
for port in $PORT_NUM; do
if [ "${port}x" != "x" ]; then
RETVAL="$RETVAL --publish $port"
fi
done
set =f; IFS=$OIFS
echo $RETVAL
}
###################################################################
# normalize memory size - adjust to the allowed set of memory sizes
###################################################################
get_memory() {
local CONT_SIZE=$1
local NEW_MEMORY=256
# check for container size and set the value as MB
if [ -z "$CONT_SIZE" ] || [ "$CONT_SIZE" == "m1.tiny" ] || [ "$CONT_SIZE" == "256" ];then
NEW_MEMORY=256
elif [ "$CONT_SIZE" == "m1.small" ] || [ "$CONT_SIZE" == "512" ]; then
NEW_MEMORY=512
elif [ "$CONT_SIZE" == "m1.medium" ] || [ "$CONT_SIZE" == "1024" ]; then
NEW_MEMORY=1024
elif [ "$CONT_SIZE" == "m1.large" ] || [ "$CONT_SIZE" == "2048" ]; then
NEW_MEMORY=2048
else
echo -e "${red}$CONT_SIZE is an invalid value, defaulting to m1.tiny (256 MB memory) and continuing deploy process.${no_color}" >&2
NEW_MEMORY=256
fi
echo "$NEW_MEMORY"
}
###################################################################
# check_memory_quota
###################################################################
# this function expects a file "iceinfo.log" to exist in the current director, being the output of a call to 'ice info'
# example:
# ice info > iceinfo.log 2> /dev/null
# RESULT=$?
# if [ $RESULT -eq 0 ]; then
# check_memory_quota()
# RESULT=$?
# if [ $RESULT -ne 0 ]; then
# echo woe is us, we have exceeded our quota
# fi
# fi
check_memory_quota() {
local CONT_SIZE=$1
local NEW_MEMORY=$(get_memory "$CONT_SIZE" 2> /dev/null)
local MEMORY_LIMIT=$(grep "Memory limit (MB)" iceinfo.log | awk '{print $5}')
local MEMORY_USAGE=$(grep "Memory usage (MB)" iceinfo.log | awk '{print $5}')
if [ -z "$MEMORY_LIMIT" ] || [ -z "$MEMORY_USAGE" ]; then
echo -e "${red}MEMORY_LIMIT or MEMORY_USAGE value is missing from ice info output command. Defaulting to m1.tiny (256 MB memory) and continuing deploy process.${no_color}" >&2
else
if [ $(echo "$MEMORY_LIMIT - $MEMORY_USAGE" | bc) -lt $NEW_MEMORY ]; then
return 1
fi
fi
return 0
}
###################################################################
# get memory size
###################################################################
get_memory_size() {
local CONT_SIZE=$1
local NEW_MEMORY=$(get_memory $CONT_SIZE)
ice info > iceinfo.log 2> /dev/null
RESULT=$?
if [ $RESULT -eq 0 ]; then
$(check_memory_quota $NEW_MEMORY)
RESULT=$?
if [ $RESULT -ne 0 ]; then
echo -e "${red}Quota exceeded for container size: The selected container size $CONT_SIZE exceeded the memory limit. You need to select smaller container size or delete some of your existing containers.${no_color}" >&2
NEW_MEMORY="-1"
fi
else
echo -e "${red}Unable to call ice info${no_color}" >&2
NEW_MEMORY="-1"
fi
echo "$NEW_MEMORY"
}
###################################################################
# Unit Test
###################################################################
# internal function, selfcheck unit test to make sure things are working
# as expected
unittest() {
local RET=0
# Unit Test for get_memory() function
#############################################
RET=$(get_memory 256 2> /dev/null)
if [ "${RET}x" != "256x" ]; then
echo "ut fail (bad memory value on check 256)"
return 10
fi
RET=$(get_memory "m1.tiny" 2> /dev/null)
if [ "${RET}x" != "256x" ]; then
echo "ut fail (bad memory value on check m1.tiny)"
return 11
fi
RET=$(get_memory 512 2> /dev/null)
if [ "${RET}x" != "512x" ]; then
echo "ut fail (bad memory value on check 512)"
return 12
fi
RET=$(get_memory "m1.small" 2> /dev/null)
if [ "${RET}x" != "512x" ]; then
echo "ut fail (bad memory value on check m1.small)"
return 13
fi
RET=$(get_memory 1024 2> /dev/null)
if [ "${RET}x" != "1024x" ]; then
echo "ut fail (bad memory value on check 1024)"
return 14
fi
RET=$(get_memory "m1.medium" 2> /dev/null)
if [ "${RET}x" != "1024x" ]; then
echo "ut fail (bad memory value on check m1.medium)"
return 15
fi
RET=$(get_memory 2048 2> /dev/null)
if [ "${RET}x" != "2048x" ]; then
echo "ut fail (bad memory value on check 2048)"
return 16
fi
RET=$(get_memory "m1.large" 2> /dev/null)
if [ "${RET}x" != "2048x" ]; then
echo "ut fail (bad memory value on check m1.large)"
return 17
fi
RET=$(get_memory 4096 2> /dev/null)
if [ "${RET}x" != "256x" ]; then
echo "ut fail (bad memory value on check 4096)"
return 18
fi
RET=$(get_memory "bad_value" 2> /dev/null)
if [ "${RET}x" != "256x" ]; then
echo "ut fail (bad memory value on check bad_value)"
return 19
fi
RET=$(get_memory 1 2> /dev/null)
if [ "${RET}x" != "256x" ]; then
echo "ut fail (bad memory value on check 1)"
return 20
fi
RET=$(get_memory "" 2> /dev/null)
if [ "${RET}x" != "256x" ]; then
echo "ut fail (bad memory value on empty check)"
return 21
fi
# Unit Test for check_memory_quota() function
#############################################
echo "Memory limit (MB) : 2048" >iceinfo.log
echo "Memory usage (MB) : 0" >>iceinfo.log
$(check_memory_quota 256 2> /dev/null)
RET=$?
if [ ${RET} -ne 0 ]; then
echo "ut fail (bad quota check with 256 size)"
return 30
fi
echo "Memory limit (MB) : 2048" >iceinfo.log
echo "Memory usage (MB) : 1024" >>iceinfo.log
$(check_memory_quota 2048 2> /dev/null)
RET=$?
if [ ${RET} -ne 1 ]; then
echo "ut fail (incorrect pass for too much memory 2048+2048)"
return 31
fi
echo "Memory limit (MB) : 2048" >iceinfo.log
echo "Memory usage (MB) : 2048" >>iceinfo.log
$(check_memory_quota 512 2> /dev/null)
RET=$?
if [ ${RET} -ne 1 ]; then
echo "ut fail (incorrect pass for too much memory 2048+512)"
return 32
fi
echo "Memory limit (MB) : 1024" >iceinfo.log
echo "Memory usage (MB) : 0" >>iceinfo.log
$(check_memory_quota 512 2> /dev/null)
RET=$?
if [ ${RET} -ne 0 ]; then
echo "ut fail (bad quota check with 512 size)"
return 33
fi
echo "Memory limit (MB) : 2048" >iceinfo.log
echo "Memory usage (MB) : 1024" >>iceinfo.log
$(check_memory_quota -1 2> /dev/null)
RET=$?
if [ ${RET} -ne 0 ]; then
echo "ut fail (bad quota check with -1 size)"
return 34
fi
echo "Memory limit (MB) : 2048" >iceinfo.log
echo "Memory usage (MB) : 2048" >>iceinfo.log
$(check_memory_quota -1 2> /dev/null)
RET=$?
if [ ${RET} -ne 1 ]; then
echo "incorrect pass for too much memory 2048+\"-1\")"
return 34
fi
# Unit Test for get_port_numbers() function
#############################################
RET=$(get_port_numbers "80" 2> /dev/null)
if [ "${RET}x" != "--publish 80x" ]; then
echo "ut fail (bad publish value on port check \"80\")"
return 40
fi
RET=$(get_port_numbers "80,8080" 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad publish value on port check \"80,8080\")"
return 41
fi
RET=$(get_port_numbers "80,8080 " 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad error check on trailing space \"80, 8080 \")"
return 42
fi
RET=$(get_port_numbers "80,8080 ," 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad error check on trailing space and comma \"80, 8080 ,\")"
return 43
fi
RET=$(get_port_numbers "80, 8080" 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad error check on intervening space \"80, 8080\")"
return 44
fi
RET=$(get_port_numbers "badvalue" 2> /dev/null)
if [ "${RET}x" != "--publish 80x" ]; then
echo "ut fail (bad error check on invalid value)"
return 45
fi
RET=$(get_port_numbers "80,,,,8080" 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad filtering on internal commas)"
return 46
fi
RET=$(get_port_numbers ",,,,80,8080" 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad filtering on leading commas)"
return 47
fi
RET=$(get_port_numbers "80,8080,,,," 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad filtering on trailing commas)"
return 48
fi
RET=$(get_port_numbers "80 8080" 2> /dev/null)
if [ "${RET}x" != "--publish 80 --publish 8080x" ]; then
echo "ut fail (bad check on no commas)"
return 49
fi
return 0
}
# Unit test for the memory size
unittest
UTRC=$?
if [ $UTRC -ne 0 ]; then
echo "Unit test failed, aborting with return code $UTRC"
else
# allow run the script with --get_memory parameter to check get_memory with custom parms directly
FTTCMD=$1
if [ ! -z $FTTCMD ]; then
if [ "$FTTCMD" == "--get_memory" ]; then
FTTCMD="get_memory"
elif [ "$FTTCMD" == "--check_memory_quota" ]; then
FTTCMD="check_memory_quota"
elif [ "$FTTCMD" == "--get_port_numbers" ]; then
FTTCMD="get_port_numbers"
else
FTTCMD=""
fi
if [ "${FTTCMD}x" != "x" ]; then
shift
rc=0
for i in $@
do
COMMAND="$FTTCMD $i"
echo "testing call \"$COMMAND\""
$COMMAND
rcc=$?
if [ $rc -eq 0 ]; then
rc=$rcc
fi
shift
done

# only exit if running directly, if done in source will
# kill the parent shell
#


