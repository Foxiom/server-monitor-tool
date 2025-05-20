#!/bin/bash

# Ensure required tools are installed
if ! command -v jq &> /dev/null; then
    sudo apt update && sudo apt install -y jq
fi
if ! command -v curl &> /dev/null; then
    sudo apt install -y curl
fi

# Get the hostname
HOSTNAME=$(hostname)

# Get the unique machine ID
MACHINE_ID=$(cat /etc/machine-id)

# Get the public IP address
PUBLIC_IP=$(curl -s http://ifconfig.me)

# Create JSON object
JSON=$(jq -n \
  --arg hostname "$HOSTNAME" \
  --arg machine_id "$MACHINE_ID" \
  --arg public_ip "$PUBLIC_IP" \
  '{hostname: $hostname, machine_id: $machine_id, public_ip: $public_ip}')

# Output the JSON
echo "$JSON"
