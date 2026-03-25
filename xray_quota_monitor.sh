#!/usr/bin/env bash

QUOTA_MANAGER="/usr/bin/xray-quota-manager"

while true; do
    if [ -x "$QUOTA_MANAGER" ]; then
        "$QUOTA_MANAGER" enforce
    fi
    sleep 60
done
