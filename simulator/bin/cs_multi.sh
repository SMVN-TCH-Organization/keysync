#!/bin/bash
startinstance(){
    export PS1=Simulator_$1@localhost
    export SDK_PORT=$1
    $2/$3/bin/bl_sim_instance -h -o &> /dev/null
}

if [ -z "$SDK_PORT" ]
then
  SDK_PORT=3001
fi

SDK_START_PORT=$SDK_PORT

SDK_BIN_PATH="$(dirname "$(readlink -f "$0")")"

SDK_INSTANCE_PATH=".tmp"

if [ -z ${1+x} ]
then
   echo "Please set the number of simulators you want to start as first parameter in your call to the script!"
   exit 1
fi

if [ ! -e $SDK_INSTANCE_PATH ]
then
  mkdir $SDK_INSTANCE_PATH
  i=1
  while [ $i -le $1 ]
  do
    mkdir -p "$SDK_INSTANCE_PATH/$i/bin" 
    cp "$SDK_BIN_PATH/bl_sim5"  "$SDK_INSTANCE_PATH/$i/bin/bl_sim_instance" 
    cp "$SDK_BIN_PATH/cs_sim.ini" "$SDK_INSTANCE_PATH/$i/bin" 
    cp "$SDK_BIN_PATH/*.so" "$SDK_INSTANCE_PATH/$i/bin" 2> /dev/null
    mkdir -p "$SDK_INSTANCE_PATH/$i/devices" 
    cp  -r "$SDK_BIN_PATH/../devices"  "$SDK_INSTANCE_PATH/$i" 


    echo "SDK_PORT $SDK_PORT SDK_INSTANCE_PATH $SDK_INSTANCE_PATH INSTANCE $i"
    startinstance $SDK_PORT $SDK_INSTANCE_PATH $i &      

    i=`expr $i + 1`
    SDK_PORT=`expr $SDK_PORT + 2`
  done
else
   echo ".tmp directory already exists"
   echo "delete .tmp directory and start again"
   exit 0
fi

trap "rm -r $SDK_INSTANCE_PATH
      exit 0" SIGINT SIGTERM

echo 
echo "cs_multi: $1 instances started"
echo
read -n1 -r -p "Press any key to terminate and remove all instances" 
echo

pkill -SIGINT bl_sim_instance
 
rm -r $SDK_INSTANCE_PATH



