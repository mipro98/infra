#!/bin/bash

#
# source this file to unlock the bitwarden vault:
#
#   > source unlock-bw.sh
#

session="$(bw unlock --raw)"
export BW_SESSION=$session
