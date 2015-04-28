#!/bin/bash
#
# start/stop service
# 

start_stop_service(){
	for daemon in ${services[*]}; do
		sudo service  $daemon $start_stop_command
	done
}
