#!/bin/sh
# =============================================================================
# lib/detect-hardware.sh
# Hardware capability detection: RAM, VRAM, unified memory, CPU arch, chipset.
# Source this file AFTER detect-os.sh:
#   . ./lib/detect-os.sh && detect_os
#   . ./lib/detect-hardware.sh && detect_hardware
#
# Exports (all integers, MB unless noted):
#   HW_RAM_MB          total system RAM in megabytes
#   HW_VRAM_MB         discrete VRAM in MB (0 if none or unified)
#   HW_UNIFIED_MB      Apple unified memory in MB (0 on non-Apple)
#   HW_INFERENCE_MB    usable memory for model inference:
#                        = HW_UNIFIED_MB  (Apple Silicon)
#                        = HW_VRAM_MB     (discrete GPU)
#                        = HW_RAM_MB / 2  (CPU-only fallback)
#   HW_CPU_ARCH        x86_64 | arm64 | armv7 | unknown
#   HW_CHIPSET         apple-silicon | intel | amd | arm-generic | unknown
#   HW_APPLE_CHIP      m1|m2|m3|m4|unknown (only meaningful on Apple Silicon)
#   HW_GPU_VENDOR      apple | nvidia | amd | intel | none
#   HW_NODE_PROFILE    primary | secondary | qnap | windows-thin | micro
#                      (auto-classified, can be overridden downstream)
#   HW_PROFILE_REASON  human-readable string explaining the classification
#
# Requires: uname, awk. Optional: sysctl (macOS), free (Linux),
#           nvidia-smi (NVIDIA), rocm-smi (AMD GPU), system_profiler (macOS).
#
# License: AGPL-3.0-or-later OR MIT — Copyright 2026 GrEEV.com KG
# =============================================================================

detect_hardware() {
    HW_RAM_MB=0
    HW_VRAM_MB=0
    HW_UNIFIED_MB=0
    HW_INFERENCE_MB=0
    HW_CPU_ARCH=unknown
    HW_CHIPSET=unknown
    HW_APPLE_CHIP=unknown
    HW_GPU_VENDOR=none
    HW_NODE_PROFILE=micro
    HW_PROFILE_REASON="default (no detection succeeded)"

    # ------------------------------------------------------------------
    # CPU architecture (portable)
    # ------------------------------------------------------------------
    _arch=$(uname -m 2>/dev/null || echo unknown)
    case "$_arch" in
        x86_64|amd64)        HW_CPU_ARCH=x86_64 ;;
        aarch64|arm64)       HW_CPU_ARCH=arm64  ;;
        armv7*|armv6*)       HW_CPU_ARCH=armv7  ;;
        *)                   HW_CPU_ARCH=unknown ;;
    esac

    # ------------------------------------------------------------------
    # macOS / Apple Silicon
    # ------------------------------------------------------------------
    if [ "$(uname)" = Darwin ]; then
        # RAM (unified on Apple Silicon, physical on Intel Mac)
        HW_RAM_MB=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1024/1024}')
        [ -z "$HW_RAM_MB" ] && HW_RAM_MB=0

        # Chipset via sysctl (present on Apple Silicon)
        _chip_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo '')

        if sysctl -n hw.optional.arm64 2>/dev/null | grep -q '^1$'; then
            HW_CHIPSET=apple-silicon
            HW_UNIFIED_MB=$HW_RAM_MB
            HW_GPU_VENDOR=apple

            # Chip generation from system_profiler (available on all macOS)
            _chip_name=$(system_profiler SPHardwareDataType 2>/dev/null \
                | awk -F': ' '/Chip/{print tolower($2)}' | head -1)
            case "$_chip_name" in
                *m4*) HW_APPLE_CHIP=m4 ;;
                *m3*) HW_APPLE_CHIP=m3 ;;
                *m2*) HW_APPLE_CHIP=m2 ;;
                *m1*) HW_APPLE_CHIP=m1 ;;
                *)    HW_APPLE_CHIP=unknown ;;
            esac
        else
            HW_CHIPSET=intel
            HW_GPU_VENDOR=intel  # default; overridden below if discrete GPU found
        fi

        # macOS discrete GPU VRAM (Intel Mac with AMD/NVIDIA eGPU)
        if [ "$HW_CHIPSET" != apple-silicon ]; then
            _vram=$(system_profiler SPDisplaysDataType 2>/dev/null \
                | awk '/VRAM.*Total/{gsub(/[^0-9]/,"",$NF); if($NF+0>0) print $NF+0}' \
                | sort -rn | head -1)
            HW_VRAM_MB=${_vram:-0}
        fi
    fi

    # ------------------------------------------------------------------
    # Linux (including QNAP, Alpine, Ubuntu, generic ARM)
    # ------------------------------------------------------------------
    if [ "$(uname)" = Linux ]; then
        # RAM via /proc/meminfo (universally available)
        HW_RAM_MB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
        [ -z "$HW_RAM_MB" ] && HW_RAM_MB=0

        # CPU vendor
        if grep -qi 'Intel' /proc/cpuinfo 2>/dev/null; then
            HW_CHIPSET=intel
        elif grep -qi 'AMD' /proc/cpuinfo 2>/dev/null; then
            HW_CHIPSET=amd
        elif [ "$HW_CPU_ARCH" = arm64 ] || [ "$HW_CPU_ARCH" = armv7 ]; then
            HW_CHIPSET=arm-generic
        fi

        # NVIDIA VRAM via nvidia-smi
        if command -v nvidia-smi >/dev/null 2>&1; then
            _vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits \
                2>/dev/null | awk 'NR==1{print $1+0}')
            if [ -n "$_vram" ] && [ "$_vram" -gt 0 ] 2>/dev/null; then
                HW_VRAM_MB=$_vram
                HW_GPU_VENDOR=nvidia
            fi
        fi

        # AMD GPU VRAM via rocm-smi
        if [ "$HW_GPU_VENDOR" = none ] && command -v rocm-smi >/dev/null 2>&1; then
            _vram=$(rocm-smi --showmeminfo vram 2>/dev/null \
                | awk '/Total Memory/{gsub(/[^0-9]/,"",$NF); print int($NF/1024/1024)}' \
                | head -1)
            if [ -n "$_vram" ] && [ "$_vram" -gt 0 ] 2>/dev/null; then
                HW_VRAM_MB=$_vram
                HW_GPU_VENDOR=amd
            fi
        fi

        # Fallback: /sys for integrated/discrete GPU VRAM
        if [ "$HW_GPU_VENDOR" = none ]; then
            for _sysfile in /sys/class/drm/card*/device/mem_info_vram_total; do
                [ -r "$_sysfile" ] || continue
                _bytes=$(cat "$_sysfile" 2>/dev/null)
                if [ -n "$_bytes" ] && [ "$_bytes" -gt 0 ] 2>/dev/null; then
                    _mb=$(awk "BEGIN{printf \"%d\", $_bytes/1024/1024}")
                    if [ "$_mb" -gt "${HW_VRAM_MB:-0}" ] 2>/dev/null; then
                        HW_VRAM_MB=$_mb
                        HW_GPU_VENDOR=amd  # /sys/drm is usually AMD/integrated
                    fi
                fi
            done
        fi
    fi

    # ------------------------------------------------------------------
    # Compute HW_INFERENCE_MB: how much memory is usable for models
    # ------------------------------------------------------------------
    if [ "$HW_UNIFIED_MB" -gt 0 ] 2>/dev/null; then
        # Apple Silicon: unified memory, models sit in same pool as RAM
        # Reserve ~20% for OS/processes, use 80%
        HW_INFERENCE_MB=$(awk "BEGIN{printf \"%d\", $HW_UNIFIED_MB * 0.80}")
    elif [ "${HW_VRAM_MB:-0}" -gt 0 ] 2>/dev/null; then
        # Discrete GPU: VRAM is the bottleneck for GPU inference
        HW_INFERENCE_MB=$HW_VRAM_MB
    else
        # CPU-only: use half of system RAM (other half for OS + swap buffer)
        HW_INFERENCE_MB=$(awk "BEGIN{printf \"%d\", $HW_RAM_MB * 0.50}")
    fi

    # ------------------------------------------------------------------
    # Node profile classification
    # ------------------------------------------------------------------
    _classify_node_profile
}


_classify_node_profile() {
    # OS context: if OS var not set, do a minimal check
    _os_hint=linux
    [ "$(uname)" = Darwin ] && _os_hint=macos
    [ -f /etc/qnap_ver ] || [ -f /etc/config/uLinux.conf ] && _os_hint=qnap

    # QNAP always gets the qnap profile regardless of RAM
    if [ "$_os_hint" = qnap ]; then
        HW_NODE_PROFILE=qnap
        HW_PROFILE_REASON="QNAP NAS detected (qnap profile regardless of RAM)"
        return
    fi

    # Apple Silicon with 32GB+ unified → primary coordinator
    if [ "$HW_CHIPSET" = apple-silicon ] && [ "${HW_UNIFIED_MB:-0}" -ge 32768 ] 2>/dev/null; then
        HW_NODE_PROFILE=primary
        HW_PROFILE_REASON="Apple Silicon ${HW_APPLE_CHIP}, ${HW_UNIFIED_MB}MB unified — primary coordinator"
        return
    fi

    # Apple Silicon with 16-31GB → secondary
    if [ "$HW_CHIPSET" = apple-silicon ] && [ "${HW_UNIFIED_MB:-0}" -ge 16384 ] 2>/dev/null; then
        HW_NODE_PROFILE=secondary
        HW_PROFILE_REASON="Apple Silicon ${HW_APPLE_CHIP}, ${HW_UNIFIED_MB}MB unified — secondary worker"
        return
    fi

    # High-RAM x86 Linux (32GB+) → secondary
    if [ "$HW_CPU_ARCH" = x86_64 ] && [ "${HW_RAM_MB:-0}" -ge 32768 ] 2>/dev/null; then
        HW_NODE_PROFILE=secondary
        HW_PROFILE_REASON="x86_64, ${HW_RAM_MB}MB RAM — secondary worker"
        return
    fi

    # Windows hint: not detectable from bash, caller overrides
    # Low-RAM x86 with some VRAM → windows-thin
    if [ "$HW_CPU_ARCH" = x86_64 ] \
        && [ "${HW_RAM_MB:-0}" -lt 24576 ] 2>/dev/null \
        && [ "${HW_VRAM_MB:-0}" -ge 1024 ] 2>/dev/null; then
        HW_NODE_PROFILE=windows-thin
        HW_PROFILE_REASON="x86_64, ${HW_RAM_MB}MB RAM, ${HW_VRAM_MB}MB VRAM — thin GPU node"
        return
    fi

    # ARM generic (Raspberry Pi, embedded) → micro
    if [ "$HW_CPU_ARCH" = arm64 ] || [ "$HW_CPU_ARCH" = armv7 ]; then
        HW_NODE_PROFILE=micro
        HW_PROFILE_REASON="ARM ${HW_CPU_ARCH}, ${HW_RAM_MB}MB RAM — micro node"
        return
    fi

    # Fallback
    HW_NODE_PROFILE=micro
    HW_PROFILE_REASON="fallback classification: RAM=${HW_RAM_MB}MB, VRAM=${HW_VRAM_MB}MB, arch=${HW_CPU_ARCH}"
}


# ------------------------------------------------------------------
# print_hw_summary — human-readable report, useful for setup scripts
# ------------------------------------------------------------------
print_hw_summary() {
    echo "--- Hardware Detection Summary ---"
    echo "  CPU arch    : $HW_CPU_ARCH"
    echo "  Chipset     : $HW_CHIPSET"
    [ "$HW_CHIPSET" = apple-silicon ] && echo "  Apple chip  : $HW_APPLE_CHIP"
    echo "  System RAM  : ${HW_RAM_MB} MB"
    [ "$HW_UNIFIED_MB" -gt 0 ] 2>/dev/null && echo "  Unified RAM : ${HW_UNIFIED_MB} MB (Apple)"
    echo "  GPU vendor  : $HW_GPU_VENDOR"
    [ "$HW_VRAM_MB" -gt 0 ]   2>/dev/null && echo "  VRAM        : ${HW_VRAM_MB} MB"
    echo "  Inference   : ${HW_INFERENCE_MB} MB usable for models"
    echo "  Node profile: $HW_NODE_PROFILE"
    echo "  Reason      : $HW_PROFILE_REASON"
    echo "----------------------------------"
}


# ------------------------------------------------------------------
# hw_json — emit a single-line JSON object for piping into other tools
# e.g.:  hw_json > /tmp/hw.json
#        python3 cluster/discover.py reads it at startup
# ------------------------------------------------------------------
hw_json() {
    printf '{"cpu_arch":"%s","chipset":"%s","apple_chip":"%s",'\
'"ram_mb":%d,"unified_mb":%d,"vram_mb":%d,"inference_mb":%d,'\
'"gpu_vendor":"%s","node_profile":"%s","profile_reason":"%s"}\n' \
        "$HW_CPU_ARCH" "$HW_CHIPSET" "$HW_APPLE_CHIP" \
        "$HW_RAM_MB" "$HW_UNIFIED_MB" "$HW_VRAM_MB" "$HW_INFERENCE_MB" \
        "$HW_GPU_VENDOR" "$HW_NODE_PROFILE" "$HW_PROFILE_REASON"
}
