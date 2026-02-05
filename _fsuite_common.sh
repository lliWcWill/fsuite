#!/usr/bin/env bash
# _fsuite_common.sh — shared library for fsuite telemetry
# Sourced by fcontent, fsearch, ftree for tiered hardware telemetry.
#
# Telemetry tiers (FSUITE_TELEMETRY env var):
#   0 — disabled (no telemetry)
#   1 — timing + bytes (default, no hardware metrics)
#   2 — Tier 1 + cpu_temp, disk_temp, ram, load_avg
#   3 — Tier 2 + machine profile (~/.fsuite/machine_profile.json)

# -------------------------
# OS Detection
# -------------------------
_fsuite_detect_os() {
  local os_type
  os_type=$(uname -s 2>/dev/null) || os_type="unknown"
  case "$os_type" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    *)       echo "unknown" ;;
  esac
}

# -------------------------
# Hardware Metrics (Tier 2)
# -------------------------

# CPU temperature in millidegrees Celsius (e.g., 45000 = 45°C)
# Returns -1 on failure
_fsuite_cpu_temp_mc() {
  local os temp_mc
  os=$(_fsuite_detect_os)

  if [[ "$os" == "linux" ]]; then
    # Try hwmon (most common on modern Linux)
    local hwmon_dirs=(/sys/class/hwmon/hwmon*/temp*_input)
    for f in "${hwmon_dirs[@]}"; do
      if [[ -r "$f" ]]; then
        temp_mc=$(cat "$f" 2>/dev/null) || continue
        if [[ "$temp_mc" =~ ^[0-9]+$ ]]; then
          echo "$temp_mc"
          return 0
        fi
      fi
    done
    # Fallback: thermal zones
    local tz_file="/sys/class/thermal/thermal_zone0/temp"
    if [[ -r "$tz_file" ]]; then
      temp_mc=$(cat "$tz_file" 2>/dev/null) || true
      if [[ "$temp_mc" =~ ^[0-9]+$ ]]; then
        echo "$temp_mc"
        return 0
      fi
    fi
  elif [[ "$os" == "macos" ]]; then
    # macOS: use osx-cpu-temp if available
    if command -v osx-cpu-temp >/dev/null 2>&1; then
      local temp_c
      temp_c=$(osx-cpu-temp 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || true
      if [[ "$temp_c" =~ ^[0-9]+\.[0-9]+$ ]]; then
        # Convert to millidegrees
        temp_mc=$(awk "BEGIN {printf \"%d\", $temp_c * 1000}")
        echo "$temp_mc"
        return 0
      fi
    fi
  fi

  echo "-1"
}

# Disk temperature in millidegrees Celsius
# Tries NVMe first, then SATA drivetemp
_fsuite_disk_temp_mc() {
  local os
  os=$(_fsuite_detect_os)

  if [[ "$os" == "linux" ]]; then
    # NVMe drives
    local nvme_hwmon_dirs=(/sys/class/hwmon/hwmon*/temp1_input)
    for f in "${nvme_hwmon_dirs[@]}"; do
      if [[ -r "$f" ]]; then
        local name_file="${f%/temp1_input}/name"
        if [[ -r "$name_file" ]]; then
          local name
          name=$(cat "$name_file" 2>/dev/null) || continue
          if [[ "$name" == *nvme* ]]; then
            local temp_mc
            temp_mc=$(cat "$f" 2>/dev/null) || continue
            if [[ "$temp_mc" =~ ^[0-9]+$ ]]; then
              echo "$temp_mc"
              return 0
            fi
          fi
        fi
      fi
    done
    # SATA drivetemp
    for f in "${nvme_hwmon_dirs[@]}"; do
      if [[ -r "$f" ]]; then
        local name_file="${f%/temp1_input}/name"
        if [[ -r "$name_file" ]]; then
          local name
          name=$(cat "$name_file" 2>/dev/null) || continue
          if [[ "$name" == *drivetemp* ]]; then
            local temp_mc
            temp_mc=$(cat "$f" 2>/dev/null) || continue
            if [[ "$temp_mc" =~ ^[0-9]+$ ]]; then
              echo "$temp_mc"
              return 0
            fi
          fi
        fi
      fi
    done
  fi

  echo "-1"
}

# Total RAM in KB
_fsuite_ram_total_kb() {
  local os
  os=$(_fsuite_detect_os)

  if [[ "$os" == "linux" ]]; then
    local mem_total
    mem_total=$(grep -m1 '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}') || true
    if [[ "$mem_total" =~ ^[0-9]+$ ]]; then
      echo "$mem_total"
      return 0
    fi
  elif [[ "$os" == "macos" ]]; then
    local mem_bytes
    mem_bytes=$(sysctl -n hw.memsize 2>/dev/null) || true
    if [[ "$mem_bytes" =~ ^[0-9]+$ ]]; then
      echo "$(( mem_bytes / 1024 ))"
      return 0
    fi
  fi

  echo "-1"
}

# Available RAM in KB
_fsuite_ram_available_kb() {
  local os
  os=$(_fsuite_detect_os)

  if [[ "$os" == "linux" ]]; then
    local mem_avail
    mem_avail=$(grep -m1 '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}') || true
    if [[ "$mem_avail" =~ ^[0-9]+$ ]]; then
      echo "$mem_avail"
      return 0
    fi
  elif [[ "$os" == "macos" ]]; then
    # macOS: parse vm_stat for free + inactive pages
    local page_size free_pages inactive_pages
    page_size=$(sysctl -n vm.pagesize 2>/dev/null) || page_size=4096
    free_pages=$(vm_stat 2>/dev/null | grep 'Pages free' | awk '{print $3}' | tr -d '.') || free_pages=0
    inactive_pages=$(vm_stat 2>/dev/null | grep 'Pages inactive' | awk '{print $3}' | tr -d '.') || inactive_pages=0
    if [[ "$free_pages" =~ ^[0-9]+$ ]] && [[ "$inactive_pages" =~ ^[0-9]+$ ]]; then
      local avail_bytes=$(( (free_pages + inactive_pages) * page_size ))
      echo "$(( avail_bytes / 1024 ))"
      return 0
    fi
  fi

  echo "-1"
}

# 1-minute load average (as string, e.g., "0.42")
_fsuite_load_avg_1m() {
  local os
  os=$(_fsuite_detect_os)

  if [[ "$os" == "linux" ]]; then
    local load
    load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null) || true
    if [[ "$load" =~ ^[0-9.]+$ ]]; then
      echo "$load"
      return 0
    fi
  elif [[ "$os" == "macos" ]]; then
    local load
    load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}') || true
    if [[ "$load" =~ ^[0-9.]+$ ]]; then
      echo "$load"
      return 0
    fi
  fi

  echo "-1"
}

# -------------------------
# Filesystem & Storage Detection (Tier 2)
# -------------------------

# Detect filesystem type for a given path
# Returns: ext4, ntfs, exfat, apfs, nfs, cifs, tmpfs, unknown, etc.
_fsuite_detect_filesystem_type() {
  local path="${1:-/}"
  local os fstype
  os=$(_fsuite_detect_os)

  if [[ "$os" == "linux" ]]; then
    # Try findmnt first (most reliable)
    if command -v findmnt >/dev/null 2>&1; then
      fstype=$(findmnt -n -o FSTYPE "$path" 2>/dev/null) || true
      if [[ -n "$fstype" ]]; then
        echo "$fstype"
        return 0
      fi
    fi
    # Fallback: parse /proc/mounts via df
    if [[ -r /proc/mounts ]]; then
      local mnt_point fstype_tmp
      mnt_point=$(df "$path" 2>/dev/null | tail -1 | awk '{print $6}') || mnt_point=""
      if [[ -n "$mnt_point" ]]; then
        fstype_tmp=$(awk -v mp=" $mnt_point " '$0 ~ mp {print $3; exit}' /proc/mounts 2>/dev/null) || true
        if [[ -n "$fstype_tmp" ]]; then
          echo "$fstype_tmp"
          return 0
        fi
      fi
    fi
  elif [[ "$os" == "macos" ]]; then
    # Try diskutil info
    if command -v diskutil >/dev/null 2>&1; then
      fstype=$(diskutil info "$path" 2>/dev/null | grep "Type (Bundle):" | awk '{print $3}') || true
      if [[ -z "$fstype" ]]; then
        fstype=$(diskutil info "$path" 2>/dev/null | grep "File System Personality:" | sed 's/.*: *//' | tr -d '\n') || true
      fi
      if [[ -n "$fstype" ]]; then
        # Normalize common macOS names
        case "$fstype" in
          *APFS*|*apfs*) echo "apfs" ;;
          *HFS*|*hfs*) echo "hfs+" ;;
          *NTFS*|*ntfs*) echo "ntfs" ;;
          *ExFAT*|*exfat*|*exFAT*) echo "exfat" ;;
          *) echo "$fstype" ;;
        esac
        return 0
      fi
    fi
    # Fallback: parse mount output
    fstype=$(mount 2>/dev/null | grep " on $path " | sed 's/.*(\([^,]*\).*/\1/' | head -1) || true
    if [[ -n "$fstype" ]]; then
      echo "$fstype"
      return 0
    fi
  fi

  echo "unknown"
}

# Detect storage type for a given path's underlying device
# Returns: ssd, hdd, nvme, network, removable, unknown
_fsuite_detect_storage_type() {
  local path="${1:-/}"
  local os fstype device rota
  os=$(_fsuite_detect_os)

  # First check if it's a network filesystem
  fstype=$(_fsuite_detect_filesystem_type "$path")
  case "$fstype" in
    nfs|nfs4|cifs|smbfs|fuse.sshfs|fuse.rclone|9p|afs|glusterfs|ceph)
      echo "network"
      return 0
      ;;
  esac

  if [[ "$os" == "linux" ]]; then
    # Get device from df
    device=$(df "$path" 2>/dev/null | tail -1 | awk '{print $1}') || true
    if [[ -z "$device" || "$device" == "-" ]]; then
      echo "unknown"
      return 0
    fi

    # Handle tmpfs, devtmpfs, etc.
    case "$fstype" in
      tmpfs|devtmpfs|ramfs|overlay)
        echo "tmpfs"
        return 0
        ;;
    esac

    # Check for NVMe explicitly (before ROTA check)
    if [[ "$device" == *nvme* ]]; then
      echo "nvme"
      return 0
    fi

    # Extract base device name (strip /dev/ and partition numbers)
    local base_device
    base_device=$(basename "$device" | sed -E 's/p?[0-9]+$//')

    # Try lsblk for ROTA (rotational) flag
    if command -v lsblk >/dev/null 2>&1; then
      rota=$(lsblk -n -d -o ROTA "/dev/$base_device" 2>/dev/null | head -1 | tr -d ' ') || true
      if [[ "$rota" == "0" ]]; then
        echo "ssd"
        return 0
      elif [[ "$rota" == "1" ]]; then
        echo "hdd"
        return 0
      fi
    fi

    # Fallback: check sysfs directly
    local sysfs_rota="/sys/block/$base_device/queue/rotational"
    if [[ -r "$sysfs_rota" ]]; then
      rota=$(cat "$sysfs_rota" 2>/dev/null) || true
      if [[ "$rota" == "0" ]]; then
        echo "ssd"
        return 0
      elif [[ "$rota" == "1" ]]; then
        echo "hdd"
        return 0
      fi
    fi

    # Check if removable (USB drives, SD cards)
    local sysfs_removable="/sys/block/$base_device/removable"
    if [[ -r "$sysfs_removable" ]]; then
      local removable
      removable=$(cat "$sysfs_removable" 2>/dev/null) || true
      if [[ "$removable" == "1" ]]; then
        echo "removable"
        return 0
      fi
    fi

  elif [[ "$os" == "macos" ]]; then
    # Use diskutil info to check for Solid State
    if command -v diskutil >/dev/null 2>&1; then
      local is_ssd is_removable
      is_ssd=$(diskutil info "$path" 2>/dev/null | grep "Solid State:" | awk '{print $3}') || true
      if [[ "$is_ssd" == "Yes" ]]; then
        echo "ssd"
        return 0
      elif [[ "$is_ssd" == "No" ]]; then
        echo "hdd"
        return 0
      fi

      # Check for removable/external
      is_removable=$(diskutil info "$path" 2>/dev/null | grep "Removable Media:" | awk '{print $3}') || true
      if [[ "$is_removable" == "Yes" || "$is_removable" == "Removable" ]]; then
        echo "removable"
        return 0
      fi
    fi
  fi

  echo "unknown"
}

# -------------------------
# Tier-Aware Collection
# -------------------------

# Collects hardware telemetry based on tier level
# Sets _FSUITE_HW_* variables
# $1 = tier level (0-3)
# $2 = target path (optional, for filesystem/storage detection)
_fsuite_collect_hw_telemetry() {
  local tier="${1:-1}"
  local target_path="${2:-}"

  # Initialize all to defaults
  _FSUITE_HW_CPU_TEMP_MC=-1
  _FSUITE_HW_DISK_TEMP_MC=-1
  _FSUITE_HW_RAM_TOTAL_KB=-1
  _FSUITE_HW_RAM_AVAIL_KB=-1
  _FSUITE_HW_LOAD_AVG_1M="-1"
  _FSUITE_HW_FILESYSTEM_TYPE="unknown"
  _FSUITE_HW_STORAGE_TYPE="unknown"

  # Tier 0: no telemetry
  if (( tier == 0 )); then
    return 0
  fi

  # Tier 1: basic (timing + bytes only, no hardware)
  if (( tier == 1 )); then
    return 0
  fi

  # Tier 2+: collect hardware metrics
  if (( tier >= 2 )); then
    _FSUITE_HW_CPU_TEMP_MC=$(_fsuite_cpu_temp_mc)
    _FSUITE_HW_DISK_TEMP_MC=$(_fsuite_disk_temp_mc)
    _FSUITE_HW_RAM_TOTAL_KB=$(_fsuite_ram_total_kb)
    _FSUITE_HW_RAM_AVAIL_KB=$(_fsuite_ram_available_kb)
    _FSUITE_HW_LOAD_AVG_1M=$(_fsuite_load_avg_1m)

    # Filesystem and storage detection (path-dependent)
    if [[ -n "$target_path" ]] && [[ -e "$target_path" ]]; then
      _FSUITE_HW_FILESYSTEM_TYPE=$(_fsuite_detect_filesystem_type "$target_path")
      _FSUITE_HW_STORAGE_TYPE=$(_fsuite_detect_storage_type "$target_path")
    fi
  fi

  # Tier 3: also generate machine profile
  if (( tier >= 3 )); then
    _fsuite_generate_machine_profile
  fi
}

# -------------------------
# Machine Profile (Tier 3)
# -------------------------

# Generates a one-time machine profile snapshot
# Atomic write: tmp file + mv + flock
_fsuite_generate_machine_profile() {
  local profile_dir="$HOME/.fsuite"
  local profile_file="$profile_dir/machine_profile.json"
  local lock_file="$profile_dir/.machine_profile.lock"

  # Skip if profile already exists and is recent (within 24 hours)
  if [[ -f "$profile_file" ]]; then
    local now mtime age_seconds
    now=$(date +%s)
    mtime=$(stat -c %Y "$profile_file" 2>/dev/null || stat -f %m "$profile_file" 2>/dev/null) || mtime=0
    age_seconds=$(( now - mtime ))
    if (( age_seconds < 86400 )); then
      return 0
    fi
  fi

  mkdir -p "$profile_dir" 2>/dev/null || return 0

  # Atomic write with portable locking (flock on Linux, mkdir fallback on macOS)
  local lock_acquired=0
  _fsuite_acquire_lock() {
    if command -v flock >/dev/null 2>&1; then
      exec 200>"$lock_file"
      flock -x 200 2>/dev/null && lock_acquired=1
    else
      # mkdir-based lock for macOS/BSD (atomic operation)
      local max_attempts=10 attempt=0
      while (( attempt < max_attempts )); do
        if mkdir "$lock_file.d" 2>/dev/null; then
          lock_acquired=1
          break
        fi
        sleep 0.1
        (( attempt++ ))
      done
    fi
  }
  _fsuite_release_lock() {
    if command -v flock >/dev/null 2>&1; then
      exec 200>&- 2>/dev/null || true
    else
      rmdir "$lock_file.d" 2>/dev/null || true
    fi
  }

  _fsuite_acquire_lock
  if (( lock_acquired == 0 )); then
    return 0  # Skip if can't acquire lock
  fi

  (

    # Double-check after acquiring lock
    if [[ -f "$profile_file" ]]; then
      local now mtime age_seconds
      now=$(date +%s)
      mtime=$(stat -c %Y "$profile_file" 2>/dev/null || stat -f %m "$profile_file" 2>/dev/null) || mtime=0
      age_seconds=$(( now - mtime ))
      if (( age_seconds < 86400 )); then
        return 0
      fi
    fi

    local os cpu_model cpu_cores ram_kb disk_model
    os=$(_fsuite_detect_os)

    if [[ "$os" == "linux" ]]; then
      cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//') || cpu_model="unknown"
      cpu_cores=$(nproc 2>/dev/null) || cpu_cores="-1"
      disk_model=$(lsblk -d -o MODEL 2>/dev/null | grep -v MODEL | head -1 | tr -d '[:space:]') || disk_model="unknown"
    elif [[ "$os" == "macos" ]]; then
      cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null) || cpu_model="unknown"
      cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null) || cpu_cores="-1"
      disk_model="unknown"
    else
      cpu_model="unknown"
      cpu_cores="-1"
      disk_model="unknown"
    fi

    ram_kb=$(_fsuite_ram_total_kb)

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")

    # Escape strings for JSON
    cpu_model=$(echo "$cpu_model" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
    disk_model=$(echo "$disk_model" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')

    local tmp_file="$profile_dir/.machine_profile.tmp.$$"
    cat > "$tmp_file" <<EOF
{
  "generated_at": "$ts",
  "os": "$os",
  "cpu_model": "$cpu_model",
  "cpu_cores": $cpu_cores,
  "ram_total_kb": $ram_kb,
  "disk_model": "$disk_model"
}
EOF
    mv "$tmp_file" "$profile_file" 2>/dev/null || rm -f "$tmp_file"

  )

  _fsuite_release_lock
}

# -------------------------
# JSON Field Generator
# -------------------------

# Generates the hardware telemetry JSON fields (without leading/trailing comma)
# Returns empty string if tier < 2
_fsuite_hw_json_fields() {
  local tier="${1:-1}"

  if (( tier < 2 )); then
    echo ""
    return 0
  fi

  echo "\"cpu_temp_mc\":${_FSUITE_HW_CPU_TEMP_MC:--1},\"disk_temp_mc\":${_FSUITE_HW_DISK_TEMP_MC:--1},\"ram_total_kb\":${_FSUITE_HW_RAM_TOTAL_KB:--1},\"ram_available_kb\":${_FSUITE_HW_RAM_AVAIL_KB:--1},\"load_avg_1m\":\"${_FSUITE_HW_LOAD_AVG_1M:--1}\",\"filesystem_type\":\"${_FSUITE_HW_FILESYSTEM_TYPE:-unknown}\",\"storage_type\":\"${_FSUITE_HW_STORAGE_TYPE:-unknown}\""
}
