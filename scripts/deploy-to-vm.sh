#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Deploy KidulWM to the VM once it's reachable
# Usage: ./deploy-to-vm.sh

VM_IP="10.0.2.15"
VM_USER="kidul"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$PROJECT_DIR/zig-out/bin/kidulwm"
SERVICE_FILE="$SCRIPT_DIR/kidulwm.service"

echo "Waiting for VM at $VM_IP..."
while ! ping -c 1 -W 1 $VM_IP >/dev/null 2>&1; do
    sleep 2
done

echo "VM reachable. Deploying..."
scp $BINARY $VM_USER@$VM_IP:/usr/local/bin/kidulwm
scp $SERVICE_FILE $VM_USER@$VM_IP:/tmp/kidulwm.service
ssh $VM_USER@$VM_IP "sudo cp /tmp/kidulwm.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl restart kidulwm"
echo "Deployed."
