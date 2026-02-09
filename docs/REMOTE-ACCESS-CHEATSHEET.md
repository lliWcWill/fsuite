# RADi Remote Access Cheat Sheet

Quick reference for remote access to RADi testers through Bertta hosts.

---

## 1. SSH Connection Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SSH CONNECTION FLOW                                  │
└─────────────────────────────────────────────────────────────────────────────┘

    Your Machine (WSL)
           │
           │ SSH with ControlMaster
           │ (persistent connection)
           ▼
    ┌──────────────────┐
    │   Jump Host      │
    │  52.54.110.136   │
    └────────┬─────────┘
             │
             │ Port forwarding
             │ (45017, 45018, 45022, 45024, 45025, 45056, 45103)
             ▼
    ┌──────────────────────────────────────────────────────────────┐
    │                      Bertta Hosts                             │
    │  bertta17 │ bertta18 │ bertta22 │ bertta24 │ bertta25 │ ...  │
    └─────────────────────────┬────────────────────────────────────┘
                              │
                              │ sshpass + SSH
                              │ (fusion / fusionproject)
                              ▼
    ┌──────────────────────────────────────────────────────────────┐
    │                     RADi Testers (39 total)                   │
    │         radi41, radi56, radi62, radi78, radi79, ...          │
    └──────────────────────────────────────────────────────────────┘
```

---

## 2. Quick Reference

### Direct RADi Access (Preferred)

SSH keys are deployed. Use direct SSH to any RADi from WSL:

| Command | Description |
|---------|-------------|
| `ssh radi78 "flog tower"` | Check tower status on radi78 |
| `ssh radi78 "flog tail"` | Live tail filtered logs |
| `ssh radi78 "flog errors 20"` | Last 20 errors/warnings |
| `ssh radi78 "flog snapshot 100"` | Last 100 filtered log lines |
| `ssh radi78 "flog search 'pattern' --no-filter"` | Search raw unfiltered log |
| `ssh radi78 "ftree --snapshot /home/fusion"` | Directory tree on RADi |
| `ssh bertta22 "ftree --snapshot /var/db/fusion"` | Directory tree on Bertta |

### Bertta Access

| Command | Description |
|---------|-------------|
| `ssh bertta103` | Connect to NPI Bertta (interactive) |
| `ssh bertta103 "command"` | Run headless command on Bertta |
| `ssh bertta103 "sudo dhcp-lease-list \| grep radi"` | List RADi IPs on Bertta |
| `scp file.deb bertta103:/var/db/fusion/` | Copy file to Bertta shared mount |

---

## 3. Log Investigation Workflow

**Use the diagnostic tools and flog together to investigate RADi issues.**

### Step 1: Find active testers

```bash
cd ~/Desktop/agent/scripts
./fusion_agent_diag_v2.sh live        # Show only GREEN (testing) RADis
./fusion_agent_diag_v2.sh fleet       # Show all 39 RADis
./fusion_agent_diag_v2.sh fleet -r    # Show only RED (error) RADis
```

### Step 2: Tail or snapshot logs on a GREEN RADi

```bash
ssh radi78 "flog tail"                # Live stream (Ctrl+C to stop)
ssh radi78 "flog snapshot 100"        # Last 100 filtered lines
ssh radi78 "flog errors 20"           # Last 20 errors/warnings
ssh radi78 "flog tower"               # Current tower status
```

### Step 3: Search for specific patterns

```bash
# Filtered search (excludes noise like tntserver, cherrypy, etc.)
ssh radi78 "flog search 'FAIL' -n 50"
ssh radi78 "flog search 'LCD grade' -n 20"

# Unfiltered search (for excluded terms)
ssh radi78 "flog search 'tntserver' --no-filter -n 100"
ssh radi78 "flog search 'robot_error' --no-filter -n 50"
```

### Step 4: Filesystem exploration

```bash
ssh radi78 "ftree --snapshot /home/fusion"
ssh radi78 "fsearch '*.log' /var/log"
ssh radi78 "fcontent 'error' /var/log/syslog"
ssh bertta22 "ftree --snapshot /var/db/fusion"
```

---

## 4. Common SSH Patterns

### Direct RADi Access (Preferred)

```bash
# SSH keys deployed — direct access from WSL
ssh radi78 "flog tower"
ssh radi117 "flog errors 20"
ssh radi56 "ftree --snapshot /home/fusion"

# Interactive session
ssh radi78
```

### Bertta Access

```bash
# Interactive shell
ssh bertta103

# Run single command (headless)
ssh bertta103 "ls -la"

# Check what RADis are connected
ssh bertta103 "sudo dhcp-lease-list | grep radi"
```

### Legacy RADi Access (via sshpass, still works)

```bash
ssh bertta103 "sshpass -p 'fusionproject' ssh -o StrictHostKeyChecking=no fusion@10.11.40.21 'flog tower'"
```

### Package Deployment

```bash
# Install package from shared mount
ssh radi78 "echo fusionproject | sudo -S dpkg -i /mnt/bertta/package.deb"

# Check package version
ssh radi78 "dpkg -l | grep fsuite"
```

---

## 5. Bertta to RADi Inventory

| Bertta | Role | RADi Count | RADi Names |
|--------|------|------------|------------|
| bertta17 | Green 351 | 6 | radi149, radi151, radi152, radi153, radi164, radi165 |
| bertta18 | Red 252 | 6 | radi116, radi160, radi161, radi162, radi181, radi183 |
| bertta22 | Manual Core | 7 | radi199, radi200, radi201, radi231, radi232, radi233, radi234 |
| bertta24 | Manual Trades | 3 | radi235, radi236, radi237 |
| bertta25 | Green 352 | 6 | radi154, radi155, radi156, radi157, radi158, radi166 |
| bertta56 | Red 251 | 6 | radi115, radi133, radi135, radi138, radi163, radi185 |
| bertta103 | NPI Dev | 1 | radi117 |

**Total: 7 Bertta hosts, 35 RADi testers**

---

## 6. FSuite Commands

### flog (RADi Only — Log Viewer)

| Command | Description |
|---------|-------------|
| `ssh radi78 "flog tail"` | Live stream filtered log |
| `ssh radi78 "flog snapshot 50"` | Last 50 filtered lines |
| `ssh radi78 "flog errors 20"` | Last 20 errors/warnings |
| `ssh radi78 "flog search 'pattern'"` | Search filtered log |
| `ssh radi78 "flog search 'tntserver' --no-filter -n 100"` | Search raw unfiltered log |
| `ssh radi78 "flog tower"` | Light tower status |
| `ssh radi78 "flog tower -o json"` | Tower status as JSON |
| `ssh radi78 "flog info"` | Log file stats |
| `ssh radi78 "flog snapshot 50 -o slim"` | Minimal output (good for piping) |

**`--no-filter` bypasses the include/exclude filters.** Use it when searching for terms that flog normally hides (tntserver, cherrypy, fusion_modbus, CommSocket, etc.)

### ftree, fsearch, fcontent (RADi + Bertta)

| Command | Description |
|---------|-------------|
| `ssh radi78 "ftree --snapshot /home/fusion"` | Directory tree with sizes |
| `ssh radi78 "fsearch '*.log' /var/log"` | Find files by name/pattern |
| `ssh radi78 "fcontent 'error' /var/log/syslog"` | Search inside files |
| `ssh bertta22 "ftree --snapshot /var/db/fusion"` | Works on Berttas too |

---

## 7. Package Deployment Commands

### Copy Package to Bertta

```bash
# Single package
scp package.deb bertta103:/var/db/fusion/

# Multiple packages
scp *.deb bertta103:/var/db/fusion/

# With specific path
scp /path/to/fsuite_1.0.0_amd64.deb bertta103:/var/db/fusion/
```

### Install on Single RADi

```bash
# Get the RADi IP first
ssh bertta103 "sudo dhcp-lease-list | grep radi231"

# Install package
ssh bertta103 "sshpass -p 'fusionproject' ssh -o StrictHostKeyChecking=no fusion@10.11.40.21 'echo fusionproject | sudo -S dpkg -i /mnt/bertta/fsuite_1.0.0_amd64.deb'"
```

### Install on All RADis (Loop)

```bash
# On Bertta (interactive session)
for ip in $(sudo dhcp-lease-list | grep radi | awk '{print $1}'); do
    echo "Installing on $ip..."
    sshpass -p 'fusionproject' ssh -o StrictHostKeyChecking=no fusion@$ip \
        'echo fusionproject | sudo -S dpkg -i /mnt/bertta/fsuite_1.0.0_amd64.deb'
done
```

### Verify Installation

```bash
# Check installed version
ssh bertta103 "sshpass -p 'fusionproject' ssh -o StrictHostKeyChecking=no fusion@10.11.40.21 'dpkg -l | grep fsuite'"

# Test command works
ssh bertta103 "sshpass -p 'fusionproject' ssh -o StrictHostKeyChecking=no fusion@10.11.40.21 'flog --version'"
```

---

## 8. Shared Mount Paths

| Location | Path | Notes |
|----------|------|-------|
| On Bertta | `/var/db/fusion` | Upload packages here |
| On RADi | `/mnt/bertta` | Same content, mounted via NFS |

### Common Operations

```bash
# List files on Bertta
ssh bertta103 "ls -la /var/db/fusion/"

# List files on RADi (same content)
ssh bertta103 "sshpass -p 'fusionproject' ssh fusion@10.11.40.21 'ls -la /mnt/bertta/'"

# Clean up old packages on Bertta
ssh bertta103 "rm /var/db/fusion/*.deb"
```

---

## 9. Credentials

| System | Username | Password | Auth Method |
|--------|----------|----------|-------------|
| Bertta | (your user) | - | SSH key (no password) |
| RADi | fusion | fusionproject | Password via sshpass |

### SSH Key Setup (for Bertta)

Your SSH config should have entries like:

```
# ~/.ssh/config
Host bertta103
    HostName localhost
    Port 45103
    User your_username
    ProxyJump jumphost
    IdentityFile ~/.ssh/id_rsa

Host jumphost
    HostName 52.54.110.136
    User your_username
    IdentityFile ~/.ssh/id_rsa
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
```

---

## 10. Troubleshooting

### Connection Issues

```bash
# Test jump host connectivity
ssh -v jumphost "echo connected"

# Test Bertta connectivity
ssh -v bertta103 "echo connected"

# Check if RADi is reachable from Bertta
ssh bertta103 "ping -c 1 10.11.40.21"
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Permission denied` | SSH key not loaded | Run `ssh-add ~/.ssh/id_rsa` |
| `Connection refused` | Port forwarding issue | Check SSH config ports |
| `Host key verification failed` | New/changed RADi | Add `-o StrictHostKeyChecking=no` |
| `sshpass: command not found` | Missing on Bertta | Contact admin to install |

### Debug Mode

```bash
# Verbose SSH to Bertta
ssh -vvv bertta103

# See what's happening with RADi connection
ssh bertta103 "sshpass -p 'fusionproject' ssh -v -o StrictHostKeyChecking=no fusion@10.11.40.21 'hostname'"
```

---

## 11. Quick Copy-Paste Templates

### Quick Health Check (Direct SSH)

```bash
# Check tower status
ssh radi78 "flog tower"

# Check recent errors
ssh radi78 "flog errors 20"

# Check disk space
ssh radi78 "df -h"

# Search unfiltered logs
ssh radi78 "flog search 'tntserver' --no-filter -n 100"
```

### Deploy Package

```bash
# 1. Copy to Bertta
scp fsuite_1.3.0_amd64.deb bertta22:/var/db/fusion/

# 2. Install on Bertta
ssh bertta22 "echo fusionproject | sudo -S dpkg -i /var/db/fusion/fsuite_1.3.0_amd64.deb"

# 3. Install on RADi (via shared mount)
ssh radi78 "echo fusionproject | sudo -S dpkg -i /mnt/bertta/fsuite_1.3.0_amd64.deb"

# 4. Or use the batch deploy script
./deploy-fsuite.sh bertta22
```

### Full Investigation Workflow

```bash
# 1. Find active testers
cd ~/Desktop/agent/scripts
./fusion_agent_diag_v2.sh live

# 2. Tail the green one
ssh radi78 "flog tail"

# 3. Check errors
ssh radi78 "flog errors 30"

# 4. Search for specific issue
ssh radi78 "flog search 'LCD grade' -n 50"
```

---

*Last updated: January 28, 2026 - Added direct SSH workflow, fsuite tools, --no-filter flag*
