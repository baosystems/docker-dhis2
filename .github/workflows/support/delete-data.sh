#!/bin/bash

# Source: https://github.com/dhis2/e2e-tests/blob/7de28e3f4a2c3fd5aa0cc5c417d467bef4fbce22/delete-data.sh

url=$url
credentials=$credentials
declare -a visualizations=('CurZOghc7Mh' 'jhr1eSnZeMr' 'jQPC2FMKqij' 'ekec09JdwLy' 'yyG85tyRhs4' 'dokSHzXzARE' 'YVEDTwlTKia' 'RCUE6hAisQN')
declare -a maps=("AHWtSmx21sx" "gJ1BHisY9Wm" "bX1XOjbCzWP")
declare -a charts=("ME1zXcf4zvu" "bDhkM10HzKO" "jQPC2FMKqij")
declare -a dashboards=("Goz4vyRx2cy")

# $1- resource
# $2 - array of uids
function send_delete_request() {
  resource=$1; shift
  ids=( "$@" )
  echo "Params: $resource, ${ids[@]}"

  echo $arr
  for id in "${ids[@]}"; do
      echo "Deleting from $resource, uid: $id"
      response=$(curl -u $credentials \
      -X DELETE \
      -s \
      -o /dev/null \
      --write-out "%{http_code}" \
      $url/api/$resource/$id )
      echo "Status code: $response"
    done
}

send_delete_request "visualizations" "${visualizations[@]}"
send_delete_request "maps" "${maps[@]}"
send_delete_request "charts" "${charts[@]}"
send_delete_request "dashboards" "${dashboards[@]}"
