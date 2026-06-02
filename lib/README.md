# lib/ — Shared detection and utility functions

**bootstrap-foundation** — Copyright 2026 GrEEV.com KG

Source or dot-import these files at the top of any setup script.
They are **side-effect-free** until you call the exported functions.

---

## Function contract

| File | Language | Call | Exports |
|---|---|---|---|
| `detect-os.sh` | sh (POSIX) | `detect_os` | `$OS`, `$PKG_MGR` |
| `detect-hardware.sh` | sh (POSIX) | `detect_hardware` | `$HW_*` vars, see below |
| `detect-hardware.ps1` | PowerShell | `Detect-Hardware` | `$global:HW` hashtable |
| `secret-backends.sh` | sh (POSIX) | see file | credential helpers |
| `clone-repos.sh` | sh (POSIX) | see file | repo checkout helpers |

---

## detect-hardware.sh exports

| Variable | Type | Description |
|---|---|---|
| `HW_RAM_MB` | int (MB) | Total system RAM |
| `HW_VRAM_MB` | int (MB) | Discrete GPU VRAM (0 if none or unified) |
| `HW_UNIFIED_MB` | int (MB) | Apple unified memory (0 on non-Apple) |
| `HW_INFERENCE_MB` | int (MB) | Usable memory for model inference |
| `HW_CPU_ARCH` | string | `x86_64 \| arm64 \| armv7 \| unknown` |
| `HW_CHIPSET` | string | `apple-silicon \| intel \| amd \| arm-generic \| unknown` |
| `HW_APPLE_CHIP` | string | `m1 \| m2 \| m3 \| m4 \| unknown` |
| `HW_GPU_VENDOR` | string | `apple \| nvidia \| amd \| intel \| none` |
| `HW_NODE_PROFILE` | string | `primary \| secondary \| qnap \| windows-thin \| micro` |
| `HW_PROFILE_REASON` | string | Human-readable classification explanation |

### Helper functions

```sh
print_hw_summary   # human-readable table to stdout
hw_json            # single-line JSON, pipe to a file or downstream tool
```

---

## Typical usage in a setup script

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../lib"  # or path to bootstrap-foundation/lib

. "$LIB/detect-os.sh"
detect_os

. "$LIB/detect-hardware.sh"
detect_hardware

print_hw_summary

# Branch on detected profile
case "$HW_NODE_PROFILE" in
  primary)      MODEL=llama3.3:70b ;;
  secondary)    MODEL=llama3.1:8b  ;;
  qnap)         MODEL=qwen2.5:1.5b ;;
  windows-thin) MODEL=phi3.5-mini  ;;
  micro)        MODEL=qwen2.5:0.5b ;;
esac

echo "Pulling model for this node: $MODEL"
ollama pull "$MODEL"
```

---

## PowerShell (Windows)

```powershell
. .\lib\detect-hardware.ps1
$hw = Detect-Hardware
Print-HwSummary

$model = switch ($hw.NodeProfile) {
    'secondary'    { 'llama3.1:8b'  }
    'windows-thin' { 'phi3.5-mini'  }
    default        { 'qwen2.5:0.5b' }
}
Write-Host "Model for this node: $model"
```

---

## JSON output for downstream consumers

Bash:
```bash
hw_json > /tmp/hw-profile.json
# local-ai-stack cluster/discover.py reads this if present
```

PowerShell:
```powershell
HW-ToJson | Out-File -Encoding utf8 $env:TEMP\hw-profile.json
```

---

## Relationship to local-ai-stack

```
bootstrap-foundation/lib/detect-os.sh        }
                         detect-hardware.sh  }  consumed by
                         detect-hardware.ps1 }  local-ai-stack/cluster/install-*.sh
                                                local-ai-stack/cluster/install-windows-thin.ps1
                                                local-ai-stack/cluster/discover.py  (via hw-profile.json)
```

The `HW_NODE_PROFILE` and `HW_INFERENCE_MB` values flow directly into
model selection and proxy routing in local-ai-stack. The detection
lives upstream in bootstrap-foundation so any other project in the
stack can consume it without pulling in AI-specific dependencies.
