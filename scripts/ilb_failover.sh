#!/bin/bash

# Failover script
# Used to move umig around to facilitate a failover. 
# This script should only be using with a topology that does not use proxies but instead ilb as endpoints and that can handle 3-5 minutes of outage during script run.
# Usage bash ilb_failover.sh <old_mater> <new_master> 

old_master=$1
new_master=$2


# Find the instance group name for the old and new umig

search_list=$(/usr/bin/gcloud compute instance-groups unmanaged list --format="table('NAME', 'ZONE')" | grep -v "^NAME")

while read umig_name umig_zone 
  do 
    found_hostname=$(/usr/bin/gcloud compute instance-groups unmanaged list-instances "$umig_name" --zone="$umig_zone" --format="table(NAME)" | grep -v "^NAME")
    if [[ "$found_hostname" == "$old_master" ]] ; then
      echo "We found the old umig $umig_name"
      export old_umig_name="$umig_name"
      export old_umig_zone="$umig_zone"
    elif [[ "$found_hostname" == "$new_master" ]] ; then
      echo "We found the new umig $umig_name"
      export new_umig_name="$umig_name"
      export new_umig_zone="$umig_zone"
    fi
  done <<< "$search_list"


# Search with found umig to find the ilb name for the failover; we also are removing umig from any ilb that exists on the new umig 

search_list=$(/usr/bin/gcloud compute backend-services list --format="table(NAME, BACKENDS)" | grep -v "^NAME")

while read ilb_name ilb_backend
  do
    if [[ -z "${ilb_backend##*$old_umig_name*}" ]] ; then
      echo "We found the new failover ilb $ilb_name"
      export failover_ilb_name="$ilb_name"
    elif [[ -z "${ilb_backend##*$new_umig_name*}" ]] ; then
      echo "We found an attached ilb to de-tatch ilb $ilb_name"
      export discard_ilb_name="$ilb_name" ##we will detatch here all attached ilb's
      remove_list=$(/usr/bin/gcloud compute forwarding-rules list --format="table(NAME, REGION)" | grep -v "^NAME")
      #remove the backend for matched ilb name
      while read ilb_drop_name ilb_drop_region
        do
          if [[ "$ilb_drop_name" == "$discard_ilb_name" ]] ; then
            echo "We found the discard region $ilb_drop_region"
#            /usr/bin/gcloud compute backend-services remove-backend ${discard_ilb_name} --instance-group="${new_umig_name}" --instance-group-zone="${new_umig_zone}" --region="${ilb_drop_region}" 
            export discard_ilb_region="$ilb_drop_region"
          fi
      done <<< "$remove_list"
    fi
  done <<< "$search_list"


# Find the region for the failover ilb
search_list=$(/usr/bin/gcloud compute forwarding-rules list --format="table(NAME, REGION)" | grep -v "^NAME")

while read ilb_name ilb_region
  do
    if [[ "$ilb_name" == "$failover_ilb_name" ]] ; then
      echo "We found the failover region $ilb_region"
      export failover_ilb_region="$ilb_region"
    fi
  done <<< "$search_list"

#remove failed front end service
echo "Removing ${old_master} with umig ${old_umig_name} from ${failover_ilb_name} in region ${failover_ilb_region}"
/usr/bin/gcloud compute backend-services remove-backend ${failover_ilb_name} --instance-group="${old_umig_name}" --instance-group-zone="${old_umig_zone}" --region="${failover_ilb_region}"

#remove failed front end service 
echo "Removing ${new_master} with umig ${new_umig_name} from ${discard_ilb_name} in region ${discard_ilb_region}"
/usr/bin/gcloud compute backend-services remove-backend ${discard_ilb_name} --instance-group="${new_umig_name}" --instance-group-zone="${new_umig_zone}" --region="${discard_ilb_region}"

#Add failover front end service to old umig
echo "Adding ${new_master} with umig ${new_umig_name} to ${failover_ilb_name} in region ${failover_ilb_region}"
/usr/bin/gcloud compute backend-services add-backend ${failover_ilb_name} --instance-group="${new_umig_name}" --instance-group-zone="${new_umig_zone}" --region="${failover_ilb_region}"

#Add failover front end service to new umig
echo "Adding ${old_master} with umig ${old_umig_name} to ${discard_ilb_name} in region ${discard_ilb_region}"
/usr/bin/gcloud compute backend-services add-backend ${discard_ilb_name} --instance-group="${old_umig_name}" --instance-group-zone="${old_umig_zone}" --region="${discard_ilb_region}"
