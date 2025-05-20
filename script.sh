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

# Get the operating system and version
OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep -m 1 PRETTY_NAME | cut -d '"' -f 2)

# Get the architecture (bit)
ARCH=$(uname -m)
case $ARCH in
    x86_64) BIT="64-bit" ;;
    i686|i386) BIT="32-bit" ;;
    *) BIT="Unknown" ;;
esac

# Get RAM details (total in MB)
RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')

# Get storage details (total in GB)
STORAGE_TOTAL=$(df -h / | awk 'NR==2 {print $2}' | tr -d 'G')

# Get uptime (in seconds)
UPTIME=$(cat /proc/uptime | awk '{print $1}')

# Get total number of processes
PROCESSES=$(ps -e | wc -l)

# Create JSON object
JSON=$(jq -n \
  --arg hostname "$HOSTNAME" \
  --arg machine_id "$MACHINE_ID" \
  --arg public_ip "$PUBLIC_IP" \
  --arg os "$OS" \
  --arg bit "$BIT" \
  --arg ram_total "$RAM_TOTAL" \
  --arg storage_total "$STORAGE_TOTAL" \
  --arg uptime "$UPTIME" \
  --arg processes "$PROCESSES" \
  '{hostname: $hostname, machine_id: $machine_id, public_ip: $public_ip, os: $os, bit: $bit, ram_total_mb: $ram_total, storage_total_gb: $storage_total, uptime_seconds: $uptime, total_processes: $processes}')

# Output the JSON
echo "$JSON"
