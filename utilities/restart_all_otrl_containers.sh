#!/bin/bash


#This will slowly restart all the swarm services - aside from services we'd be very sad to see restarted (e.g. rabbitmq).

#The purpose of this is that we never have a container running for more than a day in case they've somehow been
#compromised without the intrustion detection alerting us.

#We only restart 'replicated' services (i.e. not global).



######### Config

ignore_services="otrl_rabbitmq otrl_sdci-cron otrl_netcheck portainer otrl_mysql"

restart_monitor_sleep="10"
restart_monitor_timeout="1800"  #Half an hour


######### Functions

function monitor_restart () {

 if [ ! $1 ]; then
   echo
   echo "You need to pass a service name to monitor_restart()."
   echo
   exit 1
 else
   local this_service=$1
   local secs_waited="0"
   local restarted="false"
 fi

 while [ "$restarted" == "false" ] && [ "$secs_waited" -lt "$restart_monitor_timeout" ] ; do

   sleep $restart_monitor_sleep
   secs_waited=$((secs_waited+${restart_monitor_sleep}))

   this_status=`docker $docker_opts service inspect --format "{{.UpdateStatus.State}}" $this_service`
   echo "Status: $this_status :: Waited: ${secs_waited} secs"
   if [[ "$this_status" =~ completed ]]; then restarted="true"; fi

 done

 if [ "$secs_waited" -ge "$restart_monitor_timeout" ]; then

   
   echo "WARNING:  Timed-out waiting for $this_service restart (waited over $timeout seconds)."
   echo

 fi

}


######### Get a list of services

running_services=`docker service ls | grep replicated | awk '{ print $2 }'`

for service in $running_services; do

  regex="\\b$service\\b"
  if [[ ! $ignore_services =~ $regex ]]; then

    echo
    echo "########  Restarting $service"
    echo
    docker service update --with-registry-auth --force -q -d $service >/dev/null 2>&1
    monitor_restart $service

  else

    echo -n "Skipping restart for $service"

  fi

  echo

done

