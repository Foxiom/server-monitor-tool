#!/bin/bash

# Default interval in seconds
INTERVAL=${1:-5}  # Use first argument or default to 5 seconds

# Ensure required tools are installed
if ! command -v jq &> /dev/null; then
    sudo apt update && sudo apt install -y jq
fi
if ! command -v curl &> /dev/null; then
    sudo apt install -y curl
fi

# Get initial server details
HOSTNAME=$(hostname)
MACHINE_ID=$(cat /etc/machine-id)
PUBLIC_IP=$(curl -s http://ifconfig.me)

# Create initial JSON object
JSON=$(jq -n \
  --arg hostname "$HOSTNAME" \
  --arg machine_id "$MACHINE_ID" \
  --arg public_ip "$PUBLIC_IP" \
  '{hostname: $hostname, machine_id: $machine_id, public_ip: $public_ip}')

# Output initial server details
echo "$JSON"

# Log file for uptime
LOG_FILE="/var/log/server_uptime.log"

# Function to log uptime
log_uptime() {
  UPTIME=$(uptime -s)  # Get system uptime start time
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")  # Current UTC timestamp
  UPTIME_JSON=$(jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg uptime "$UPTIME" \
    '{timestamp: $timestamp, uptime: $uptime}')
  echo "$UPTIME_JSON" >> "$LOG_FILE"
}

# Log uptime at specified interval
while true; do
  log_uptime
  sleep "$INTERVAL"
done
