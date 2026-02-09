# SSH Configuration for Direct RADi Access

This guide shows how to configure SSH for direct access to RADi testers by hostname, eliminating the need to remember IP addresses or use nested SSH commands.

---

## 1. Current Architecture Problem

### The Problem

Currently, accessing a RADi tester requires:

1. **Knowing the RADi's IP address** - RADis get IPs via DHCP from their parent Bertta
2. **Looking up the IP** - Must run `dhcp-lease-list` on the Bertta each time
3. **Nested SSH with sshpass** - Awkward command structure

**Current workflow (painful):**
```bash
# Step 1: Find the IP
ssh bertta103 "dhcp-lease-list"
# Output shows radi117 is at 10.11.40.21

# Step 2: Connect with nested SSH + sshpass
ssh bertta103 "sshpass -p 'fusionproject' ssh fusion@10.11.40.21 'flog tower'"
```

**Problems:**
- IP addresses change when DHCP leases expire
- Must remember which Bertta hosts which RADi
- Cumbersome nested command syntax
- Password visible in command history

---

## 2. Solution: SSH ProxyCommand with sshpass

SSH's `ProxyCommand` directive lets us tunnel through a jump host automatically. Combined with SSH keys, we can achieve single-command RADi access.

### Basic SSH Config Pattern

Add to `~/.ssh/config`:

```ssh-config
# ~/.ssh/config

# =============================================================================
# RADi Testers - Direct Access via Bertta Proxy
# =============================================================================
# Usage: ssh radi117 "command"
# Requires: SSH key deployed to Bertta, and Bertta->RADi key or sshpass wrapper
# =============================================================================

# RADi 117 via Bertta103
Host radi117
    HostName 10.11.40.21
    User fusion
    ProxyCommand ssh -W %h:%p bertta103
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# RADi 231 via Bertta103
Host radi231
    HostName 10.11.130.59
    User fusion
    ProxyCommand ssh -W %h:%p bertta103
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

### How It Works

1. `Host radi117` - Defines the alias you type
2. `HostName 10.11.40.21` - The actual RADi IP
3. `User fusion` - Default username on RADi
4. `ProxyCommand ssh -W %h:%p bertta103` - Tunnels through Bertta103
5. `StrictHostKeyChecking no` - Prevents host key prompts (RADis are ephemeral)

---

## 3. Full RADi Host Configuration

### Complete SSH Config for All 39 RADis

Copy this entire block to your `~/.ssh/config`:

```ssh-config
# =============================================================================
# RADi Testers - Direct Access Configuration
# =============================================================================
# Generated for FSuite RADi fleet
# Last updated: 2025
# =============================================================================

# -----------------------------------------------------------------------------
# Bertta103 RADis (5 units)
# -----------------------------------------------------------------------------

Host radi117
    HostName 10.11.40.21
    User fusion
    ProxyCommand ssh -W %h:%p bertta103
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi231
    HostName 10.11.130.59
    User fusion
    ProxyCommand ssh -W %h:%p bertta103
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi232
    HostName 10.11.130.60
    User fusion
    ProxyCommand ssh -W %h:%p bertta103
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi234
    HostName 10.11.130.62
    User fusion
    ProxyCommand ssh -W %h:%p bertta103
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi236
    HostName 10.11.130.68
    User fusion
    ProxyCommand ssh -W %h:%p bertta103
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# -----------------------------------------------------------------------------
# Bertta17 RADis (6 units)
# -----------------------------------------------------------------------------

Host radi149
    HostName 10.11.129.201
    User fusion
    ProxyCommand ssh -W %h:%p bertta17
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi152
    HostName 10.11.129.202
    User fusion
    ProxyCommand ssh -W %h:%p bertta17
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi151
    HostName 10.11.129.203
    User fusion
    ProxyCommand ssh -W %h:%p bertta17
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi153
    HostName 10.11.129.218
    User fusion
    ProxyCommand ssh -W %h:%p bertta17
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi164
    HostName 10.11.129.226
    User fusion
    ProxyCommand ssh -W %h:%p bertta17
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi165
    HostName 10.11.129.224
    User fusion
    ProxyCommand ssh -W %h:%p bertta17
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# -----------------------------------------------------------------------------
# Bertta18 RADis (6 units)
# -----------------------------------------------------------------------------

Host radi116
    HostName 10.11.48.72
    User fusion
    ProxyCommand ssh -W %h:%p bertta18
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi160
    HostName 10.11.129.220
    User fusion
    ProxyCommand ssh -W %h:%p bertta18
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi161
    HostName 10.11.129.221
    User fusion
    ProxyCommand ssh -W %h:%p bertta18
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi162
    HostName 10.11.129.222
    User fusion
    ProxyCommand ssh -W %h:%p bertta18
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi181
    HostName 10.11.129.239
    User fusion
    ProxyCommand ssh -W %h:%p bertta18
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi183
    HostName 10.11.129.245
    User fusion
    ProxyCommand ssh -W %h:%p bertta18
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# -----------------------------------------------------------------------------
# Bertta22 RADis (7 units)
# -----------------------------------------------------------------------------

Host radi56
    HostName 10.11.54.13
    User fusion
    ProxyCommand ssh -W %h:%p bertta22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi62
    HostName 10.11.47.185
    User fusion
    ProxyCommand ssh -W %h:%p bertta22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi78
    HostName 10.11.47.201
    User fusion
    ProxyCommand ssh -W %h:%p bertta22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi81
    HostName 10.11.217.156
    User fusion
    ProxyCommand ssh -W %h:%p bertta22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi199
    HostName 10.11.130.5
    User fusion
    ProxyCommand ssh -W %h:%p bertta22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi200
    HostName 10.11.130.6
    User fusion
    ProxyCommand ssh -W %h:%p bertta22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi201
    HostName 10.11.130.7
    User fusion
    ProxyCommand ssh -W %h:%p bertta22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# -----------------------------------------------------------------------------
# Bertta24 RADis (3 units)
# -----------------------------------------------------------------------------

Host radi41
    HostName 10.11.47.194
    User fusion
    ProxyCommand ssh -W %h:%p bertta24
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi44
    HostName 10.11.109.151
    User fusion
    ProxyCommand ssh -W %h:%p bertta24
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi79
    HostName 10.11.88.97
    User fusion
    ProxyCommand ssh -W %h:%p bertta24
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# -----------------------------------------------------------------------------
# Bertta25 RADis (6 units)
# -----------------------------------------------------------------------------

Host radi154
    HostName 10.11.129.217
    User fusion
    ProxyCommand ssh -W %h:%p bertta25
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi155
    HostName 10.11.129.213
    User fusion
    ProxyCommand ssh -W %h:%p bertta25
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi156
    HostName 10.11.129.210
    User fusion
    ProxyCommand ssh -W %h:%p bertta25
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi157
    HostName 10.11.129.216
    User fusion
    ProxyCommand ssh -W %h:%p bertta25
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi158
    HostName 10.11.129.212
    User fusion
    ProxyCommand ssh -W %h:%p bertta25
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi166
    HostName 10.11.129.225
    User fusion
    ProxyCommand ssh -W %h:%p bertta25
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# -----------------------------------------------------------------------------
# Bertta56 RADis (6 units)
# -----------------------------------------------------------------------------

Host radi115
    HostName 10.11.10.10
    User fusion
    ProxyCommand ssh -W %h:%p bertta56
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi133
    HostName 10.11.129.197
    User fusion
    ProxyCommand ssh -W %h:%p bertta56
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi135
    HostName 10.11.1.47
    User fusion
    ProxyCommand ssh -W %h:%p bertta56
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi138
    HostName 10.11.1.19
    User fusion
    ProxyCommand ssh -W %h:%p bertta56
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi163
    HostName 10.11.129.223
    User fusion
    ProxyCommand ssh -W %h:%p bertta56
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host radi185
    HostName 10.11.129.247
    User fusion
    ProxyCommand ssh -W %h:%p bertta56
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

---

## 4. RADi IP Address Reference Table

Quick reference for all RADi IP addresses grouped by parent Bertta:

| RADi | Bertta | IP Address |
|------|--------|------------|
| **Bertta103** | | |
| radi117 | bertta103 | 10.11.40.21 |
| radi231 | bertta103 | 10.11.130.59 |
| radi232 | bertta103 | 10.11.130.60 |
| radi234 | bertta103 | 10.11.130.62 |
| radi236 | bertta103 | 10.11.130.68 |
| **Bertta17** | | |
| radi149 | bertta17 | 10.11.129.201 |
| radi152 | bertta17 | 10.11.129.202 |
| radi151 | bertta17 | 10.11.129.203 |
| radi153 | bertta17 | 10.11.129.218 |
| radi164 | bertta17 | 10.11.129.226 |
| radi165 | bertta17 | 10.11.129.224 |
| **Bertta18** | | |
| radi116 | bertta18 | 10.11.48.72 |
| radi160 | bertta18 | 10.11.129.220 |
| radi161 | bertta18 | 10.11.129.221 |
| radi162 | bertta18 | 10.11.129.222 |
| radi181 | bertta18 | 10.11.129.239 |
| radi183 | bertta18 | 10.11.129.245 |
| **Bertta22** | | |
| radi56 | bertta22 | 10.11.54.13 |
| radi62 | bertta22 | 10.11.47.185 |
| radi78 | bertta22 | 10.11.47.201 |
| radi81 | bertta22 | 10.11.217.156 |
| radi199 | bertta22 | 10.11.130.5 |
| radi200 | bertta22 | 10.11.130.6 |
| radi201 | bertta22 | 10.11.130.7 |
| **Bertta24** | | |
| radi41 | bertta24 | 10.11.47.194 |
| radi44 | bertta24 | 10.11.109.151 |
| radi79 | bertta24 | 10.11.88.97 |
| **Bertta25** | | |
| radi154 | bertta25 | 10.11.129.217 |
| radi155 | bertta25 | 10.11.129.213 |
| radi156 | bertta25 | 10.11.129.210 |
| radi157 | bertta25 | 10.11.129.216 |
| radi158 | bertta25 | 10.11.129.212 |
| radi166 | bertta25 | 10.11.129.225 |
| **Bertta56** | | |
| radi115 | bertta56 | 10.11.10.10 |
| radi133 | bertta56 | 10.11.129.197 |
| radi135 | bertta56 | 10.11.1.47 |
| radi138 | bertta56 | 10.11.1.19 |
| radi163 | bertta56 | 10.11.129.223 |
| radi185 | bertta56 | 10.11.129.247 |

---

## 5. SSH Key Deployment: Bertta to RADi

To eliminate password prompts entirely, deploy SSH keys from each Bertta to its RADis.

### Step 1: Generate SSH Key on Bertta (if needed)

```bash
# SSH to Bertta
ssh bertta103

# Check if key exists
ls -la ~/.ssh/id_rsa.pub

# If not, generate one
ssh-keygen -t rsa -b 4096 -C "bertta103-radi-access"
# Press Enter for default location, no passphrase for automation
```

### Step 2: Copy Key to RADi

```bash
# From Bertta, copy key to each RADi using sshpass
sshpass -p 'fusionproject' ssh-copy-id -o StrictHostKeyChecking=no fusion@10.11.40.21

# Verify passwordless access works
ssh fusion@10.11.40.21 "hostname"
```

### Batch Deployment Script

Run this on each Bertta to deploy keys to all its RADis:

```bash
#!/bin/bash
# deploy-keys-to-radis.sh
# Run on Bertta to deploy SSH keys to all connected RADis

RADI_PASSWORD="fusionproject"

# Define RADi IPs for this Bertta (example for bertta103)
RADI_IPS=(
    "10.11.40.21"    # radi117
    "10.11.130.59"   # radi231
    "10.11.130.60"   # radi232
    "10.11.130.62"   # radi234
    "10.11.130.68"   # radi236
)

for ip in "${RADI_IPS[@]}"; do
    echo "Deploying key to $ip..."
    sshpass -p "$RADI_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no fusion@$ip
done

echo "Done! Test with: ssh fusion@10.11.40.21 hostname"
```

### Verification

```bash
# From your workstation, after SSH config is set up
ssh radi117 "hostname"
# Should return: radi117 (or similar) without password prompt
```

---

## 6. Final Simplified Workflow

After completing the setup:

### Before (Old Way)
```bash
# Find the IP
ssh bertta103 "dhcp-lease-list | grep radi117"

# Execute command with nested SSH
ssh bertta103 "sshpass -p 'fusionproject' ssh fusion@10.11.40.21 'flog tower'"
```

### After (New Way)
```bash
# Direct access by name!
ssh radi117 "flog tower"

# All FSuite commands work directly
ssh radi117 "ftree --snapshot /home/fusion"
ssh radi117 "flog --list"
ssh radi117 "fcheck --status"

# Interactive session
ssh radi117
fusion@radi117:~$ flog tower
```

### Batch Operations Across Multiple RADis

```bash
# Check all Bertta22 RADis
for radi in radi56 radi62 radi78 radi81 radi199 radi200 radi201; do
    echo "=== $radi ==="
    ssh $radi "flog --status" 2>/dev/null || echo "  OFFLINE"
done

# Parallel execution with GNU parallel
parallel -j 5 ssh {} "flog tower" ::: radi117 radi231 radi232 radi234 radi236
```

---

## 7. Troubleshooting

### Connection Timeout
```bash
# Check if Bertta is reachable
ssh bertta103 "echo OK"

# Check if RADi IP is correct
ssh bertta103 "ping -c 1 10.11.40.21"

# Verify DHCP lease
ssh bertta103 "dhcp-lease-list | grep radi117"
```

### Permission Denied
```bash
# Verify SSH key is deployed
ssh bertta103 "ssh -o BatchMode=yes fusion@10.11.40.21 hostname"

# If fails, redeploy key
ssh bertta103 "sshpass -p 'fusionproject' ssh-copy-id fusion@10.11.40.21"
```

### Host Key Changed (IP reused)
```bash
# Clear old host key from Bertta
ssh bertta103 "ssh-keygen -R 10.11.40.21"

# The SSH config disables strict checking, but Bertta's known_hosts may still complain
```

---

## 8. Alternative: sshpass Wrapper (No Key Deployment)

If you cannot deploy SSH keys, create a wrapper script on each Bertta:

```bash
# /usr/local/bin/radi-ssh on Bertta
#!/bin/bash
sshpass -p 'fusionproject' ssh -o StrictHostKeyChecking=no fusion@"$@"
```

Then modify SSH config to use it:
```ssh-config
Host radi117
    HostName 10.11.40.21
    User fusion
    ProxyCommand ssh bertta103 "/usr/local/bin/radi-ssh %h -W localhost:22"
```

**Note:** This is less secure and slower. Prefer SSH key deployment.

---

## Summary

| Component | Purpose |
|-----------|---------|
| `~/.ssh/config` | Maps `radi117` to IP + proxy |
| `ProxyCommand` | Routes through Bertta |
| SSH keys on Bertta | Passwordless Bertta->RADi |
| `StrictHostKeyChecking no` | Handles ephemeral RADi hosts |

**Result:** `ssh radi117 "command"` just works.
