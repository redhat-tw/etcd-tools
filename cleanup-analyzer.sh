#!/bin/bash

echo -e "DRY RUN without paramateters"
echo -e "Depending on the size of cluster, this script can run from several seconds to several minutes."
echo -e ""

CLIENT="oc"

MUST_PATH=$1
ORIG_PATH=$(pwd)
OUTPUT_PATH=$ORIG_PATH/DATA

#rm -rf $OUTPUT_PATH
mkdir -p $OUTPUT_PATH

# PARSER --------------------------------------------------------------------------

print_help() {
  echo -e "HELP:"
  echo -e "-f | --force : to actually delete ReplicaSets not in use. (Not implemented)"
  echo -e "-g | --graph : graph referenced images. (Not implemented)"
  echo -e ""
}

PARAMS=""
while (( "$#" )); do
  case "$1" in
    -f|--force)
      FORCE_DELETION=0
      shift
      ;;
    -k|--kubectl)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        CLIENT="kubectl"
        ETCD_NS="kube-system"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      print_help
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

#---------------------------------------------------------------------------------

oc get ns |grep -v openshift|grep -v kube|grep -v default > $OUTPUT_PATH/ns.log
oc get ns > $OUTPUT_PATH/ns_all.log


imagestreams() {
  echo -e ""
  echo -e "[IMAGESTREAMS]"
  $CLIENT get imagestream -A -o jsonpath="{..dockerImageReference}" | tr -s '[[:space:]]' '\n'| sort | uniq > $OUTPUT_PATH/is_images.log
  $CLIENT get is -A > $OUTPUT_PATH/is.log
  
  echo -e "IMAGESTREAM: there are $(cat $OUTPUT_PATH/is_images.log|wc -l) images referenced by Imagestreams."
  echo -e "IMAGESTREAM: there are $(cat $OUTPUT_PATH/is_images.log|grep openshift-release-dev|wc -l) openshift-release-dev images referenced by Imagestreams."
  echo -e "IMAGESTREAM: there are $(cat $OUTPUT_PATH/is_images.log|wc -l) other images referenced by Imagestreams."
  echo -e "..."

}

pods() {
  echo -e ""
  echo -e "[PODS]"
  $CLIENT get pods -A|tail -n +2 > $OUTPUT_PATH/pod.log
  echo -e "PODS: there are $(cat $OUTPUT_PATH/pod.log|wc -l) pods."
  $CLIENT get pods -A -o jsonpath="{..image}" | tr -s '[[:space:]]' '\n'| sort | uniq  > $OUTPUT_PATH/pod_images.log
  echo -e "PODS: there are $(cat $OUTPUT_PATH/pod_images.log|wc -l) images referenced by pods."
}

# REPLICASETS

replicasets() {
  echo -e ""
  echo -e "[REPLICASETS]"
  $CLIENT get replicasets -A > $OUTPUT_PATH/rs.log
  INACTIVE_OLDER=$(cat $OUTPUT_PATH/rs.log |grep  -E '0{1}\s+0{1}\s+0{1}'| awk '($6*3600) > (20*3600) {print "oc describe rs -n " $1, $2, $6 }'|sort -k 7n|uniq|wc -l)
  cat $OUTPUT_PATH/rs.log |grep  -E '0{1}\s+0{1}\s+0{1}'| awk '{print "-n " $1, $2}'|sort|uniq > $OUTPUT_PATH/rs_inactive.log
  #cat rs.log |grep  -E '0{1}\s+0{1}\s+0{1}'| awk '{print "oc describe rs -n " $1, $2, $6, ($6*3600) }'|sort -k 7n|uniq
  $CLIENT get rs -A  -o jsonpath="{..image}" | tr -s '[[:space:]]' '\n' | sort | uniq > $OUTPUT_PATH/rs_images.log
  $CLIENT get replicasets -A | awk '{print "-n " $1, $2}'|sort|uniq > $OUTPUT_PATH/replicasetsns.log
  echo -e "REPLICASET: there are $(cat $OUTPUT_PATH/rs.log|wc -l) ReplicaSets."
  echo -e "REPLICASET: there are $(cat $OUTPUT_PATH/rs_inactive.log|wc -l) INACTIVE ReplicaSets."
  echo -e "REPLICASET: there are $(cat $OUTPUT_PATH/rs_images.log|wc -l) images referenced by ReplicaSets."
  echo -e ""

  echo -e "There is $INACTIVE_OLDER RS older than 20 days"
  echo -e ""
  # cat $OUTPUT_PATH/rs.log |grep  -E '0{1}\s+0{1}\s+0{1}'| awk '($6*3600) > (20*3600) {print "oc describe rs -n " $1, $2, $6 }'|sort -k 7n|uniq
}

deployments() {
  echo -e ""
  echo -e "[DEPLOYMENTS]"
  $CLIENT get deployment -A|tail -n +2 > $OUTPUT_PATH/deployment.log
  echo -e "DEPLOYMENT: There is $(cat $OUTPUT_PATH/deployment.log|wc -l) deployments."
  cat $OUTPUT_PATH/deployment.log |awk '{print $2" -n "$1}' > $OUTPUT_PATH/deploy.log
# while IFS= read -r line; do $CLIENT describe deployment $line |grep Image | awk '{print $2}'; done < deployment.log

  $CLIENT get deployment -A -o jsonpath="{..image}" | tr -s '[[:space:]]' '\n' | sort | uniq > $OUTPUT_PATH/depimage.log
# while IFS= read -r line; do $CLIENT describe deployment $line |grep Image | awk '{print $2}'; done < $OUTPUT_PATH/deploy.log > $OUTPUT_PATH/depimage.log
# sort $OUTPUT_PATH/depimage.log |uniq|wc -l
# echo -e "DEPLOYMENT: there is $(cat $OUTPUT_PATH/depimage.log|sort|uniq|wc -l) images referenced by Deployments."
  echo -e "DEPLOYMENT: there is $(cat $OUTPUT_PATH/depimage.log|sort|uniq|wc -l) images referenced by Deployments."
}

delete_rs() {
  $CLIENT delete rs $1
}

imagestreams
pods
deployments
replicasets


# $CLIENT get deployments -A |grep  -E '0{1}/[0-9]+'  > $OUTPUT_PATH/deployments.log


$CLIENT get jobs -A|wc -l > $OUTPUT_PATH/jobs.log


# $CLIENT get deployment -A|awk '{print $2 " -n " $1}'

# $CLIENT describe deployment alpine -n foo|grep Image | awk '{print $2}'







# $CLIENT get is -A | awk '{print $2}'


# echo -e "diffing.."
# Print images not used by any pod

awk 'NR == FNR{ a[$0] = 1;next } !a[$0]' $OUTPUT_PATH/pod_images.log $OUTPUT_PATH/is_images.log > $OUTPUT_PATH/podis.log

# Print images not used by any Deployment

awk 'NR == FNR{ a[$0] = 1;next } !a[$0]' $OUTPUT_PATH/deploy.log $OUTPUT_PATH/is_images.log > $OUTPUT_PATH/depis.log

awk 'NR == FNR{ a[$0] = 1;next } !a[$0]' $OUTPUT_PATH/depis.log $OUTPUT_PATH/podis.log > $OUTPUT_PATH/EXCESS.log


echo -e "Done"




#oc get deploy -A -o jsonpath='{range .items[*]}{.metadata.name} revision:{.metadata.annotations.deployment\.kubernetes\.io\/revision}{"\n"}  {end}'