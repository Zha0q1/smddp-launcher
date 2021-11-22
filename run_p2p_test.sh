#!/bin/bash
# Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file
# except in compliance with the License. A copy of the License is located at
#
# http://aws.amazon.com/apache2.0/
#
# or in the "LICENSE.txt" file accompanying this file. This file is distributed on an "AS IS"
# BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or implied. See the License for
# the specific language governing permissions and limitations under the License.
set -e

export SMDATAPARALLEL_WORLD_RANK=$OMPI_COMM_WORLD_RANK
export SMDATAPARALLEL_WORLD_SIZE=$OMPI_COMM_WORLD_SIZE
export SMDATAPARALLEL_LOCAL_RANK=$OMPI_COMM_WORLD_LOCAL_RANK

local_rank=$SMDATAPARALLEL_LOCAL_RANK
first_core=$((local_rank * 6))
last_core=$((first_core + 5))

# assert hwloc packages are available for SageMaker jobs
if [[ "$SM_HOSTS" != "" ]]; then
  if ! ([[ "$(which lstopo)" != "" ]] && [[ "$(which hwloc-bind)" != "" ]]); then
    if (($OMPI_COMM_WORLD_RANK == 0)); then
      echo "hwloc not found in image. Aborting......"
    fi
    exit 1
  fi
fi

# check lstopo output, p3.16x will show 0 on OpenFabrics devices
num_efa_devices=$(lstopo | grep OpenFabrics | cut -d'"' -f2 | wc -l)
if [ "$num_efa_devices" -eq "0" ]; then # Mostly will be p3.16 block
  export SMDATAPARALLEL_USE_ENA=1
  export SMDATAPARALLEL_NUM_CONN=3 # This was the magic number in SM branch that worked on ENA.
  # W/O there is intermittent hang. https://github.com/aws/herring/blob/sm/commoncpu/Config.cpp#L28
  $@ # hwloc-bind slows down on p3.16. Need to debug this why.
else
  mpi_local_size=4
  efa_device_idx=$((local_rank / (mpi_local_size / num_efa_devices)))
  efa_device_idx=$((efa_device_idx + 1))
  export SMDATAPARALLEL_DEVICE_NAME=$(lstopo | grep OpenFabrics | cut -d'"' -f2 | sed -n "${efa_device_idx},${efa_device_idx} p")
  hwloc-bind core:$first_core-$last_core $@
fi
