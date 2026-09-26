#!/usr/bin/env bash

# --- START SERVICE HELPER ---
# Helper function to display usage and best practices for start_service.
_start_service_usage() {
    echo "🚀 The 'start_service' command helps you activate and enable systemd services."
    echo ""
    echo "Usage: start_service [-s] [-e] [-h] service1.service [service2.service ...]"
    echo ""
    echo "Arguments:"
    echo "  -s         ▶️  Start the service(s) for the current session."
    echo "  -e         🔌  Enable the service(s) to start automatically on boot."
    echo "  -h         ❓  Display this help menu."
    echo ""
    echo "--- 💡 Best Practices ---"
    echo "1. Start vs. Enable: What's the difference?"
    echo "   - 'Starting' a service (-s) runs it right now, but it won't restart after a reboot."
    echo "   - 'Enabling' a service (-e) tells the system to run it on the next boot, but it doesn't start it now."
    echo ""
    echo "2. The Most Common Use Case (Do Both):"
    echo "   To make a service persistent and run it immediately, use both flags: 'start_service -e -s your.service'"
    echo "   This is the equivalent of the powerful 'systemctl enable --now' command."
    echo ""
    echo "3. Check Your Work:"
    echo "   You can always verify a service's status with: 'systemctl status your.service'"
    echo "   The command will show if the service is 'active (running)' and 'enabled'."
    echo ""
    echo "4. Idempotency (It's Safe to Re-run):"
    echo "   This script won't cause errors if a service is already active or enabled. It will simply"
    echo "   report the current state, so you can run it without worrying about breaking things."
}
