#!/bin/bash

# Check if an argument is provided
if [ -z "$1" ]; then
  echo "No datetime provided to set to, exiting"
  exit 1
fi

date_time="$1"

#Parse date time into month, day, hour, min and year values
MM=${date_time:5:2}
DD=${date_time:8:2}
HH=${date_time:11:2}
mm=${date_time:14:2}
YYYY=${date_time:0:4}

# Print the re-formatted result
echo $MM$DD$HH$mm$YYYY
#Set date
echo "setting dateitime"
date $MM$DD$HH$mm$YYYY


