#!/bin/bash
#
# eddy-ng interactive installer
#
# Supports three sensor types:
#   1) Eddy Duo (RP2040) - patchless: pip package + pre-built firmware
#   2) Cartographer (RP2040) - patchless: pip package (no firmware flash)
#   3) Other (Eddy Coil, etc.) - traditional: pip + Klipper source patching
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

# ─── Argument parsing ───────────────────────────────────────────────────────

KLIPPER_DIR=""
KLIPPY_ENV=""
SENSOR_TYPE=""
UNINSTALL=0

usage() {
    echo "Usage: $0 [OPTIONS] [KLIPPER_DIR]"
    echo ""
    echo "Options:"
    echo "  --duo              Select Eddy Duo sensor (patchless install)"
    echo "  --cartographer     Select Cartographer sensor (patchless install)"
    echo "  --other            Select other Eddy sensor (traditional install)"
    echo "  -e, --klippy-env   Klippy virtualenv directory"
    echo "  -u, --uninstall    Uninstall eddy-ng"
    echo "  -h, --help         Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duo)         SENSOR_TYPE="duo"; shift ;;
        --cartographer) SENSOR_TYPE="cartographer"; shift ;;
        --other)       SENSOR_TYPE="other"; shift ;;
        -e|--klippy-env) KLIPPY_ENV="$2"; shift 2 ;;
        -u|--uninstall)  UNINSTALL=1; shift ;;
        -h|--help)     usage ;;
        -*)            error "Unknown option: $1"; usage ;;
        *)             KLIPPER_DIR="$1"; shift ;;
    esac
done

# ─── Detect Klipper / Kalico ────────────────────────────────────────────────

find_klipper_dir() {
    if [ -n "$KLIPPER_DIR" ]; then
        return
    fi
    if [ -d "$HOME/klipper" ]; then
        KLIPPER_DIR="$HOME/klipper"
    elif [ -d "$HOME/kalico" ]; then
        KLIPPER_DIR="$HOME/kalico"
    else
        error "Klipper directory not found. Specify: $0 /path/to/klipper"
        exit 1
    fi
}

find_klippy_env() {
    if [ -n "$KLIPPY_ENV" ]; then
        return
    fi
    if [ -d "$HOME/klippy-env" ]; then
        KLIPPY_ENV="$HOME/klippy-env"
    elif [ -d "$HOME/kalico-env" ]; then
        KLIPPY_ENV="$HOME/kalico-env"
    else
        error "Klippy virtualenv not found. Specify: $0 --klippy-env /path/to/env"
        exit 1
    fi
}

detect_kalico() {
    IS_KALICO=0
    if [ -f "$KLIPPER_DIR/klippy/extras/danger_options.py" ]; then
        IS_KALICO=1
    fi
}

# ─── Scaffolding directory ──────────────────────────────────────────────────

get_scaffolding_dir() {
    if [ $IS_KALICO -eq 1 ] || [ -d "$KLIPPER_DIR/klippy/plugins" ]; then
        echo "$KLIPPER_DIR/klippy/plugins"
    else
        echo "$KLIPPER_DIR/klippy/extras"
    fi
}

# ─── Cleanup legacy installations ───────────────────────────────────────────

remove_legacy() {
    local scaff_dir
    scaff_dir=$(get_scaffolding_dir)
    local extras_dir="$KLIPPER_DIR/klippy/extras"

    # Remove old symlinks/files from both possible locations
    for dir in "$extras_dir" "$KLIPPER_DIR/klippy/plugins"; do
        [ ! -d "$dir" ] && continue
        for f in probe_eddy_ng.py ldc1612_ng.py; do
            if [ -L "$dir/$f" ] || [ -f "$dir/$f" ]; then
                info "Removing legacy file: $dir/$f"
                rm -f "$dir/$f"
            fi
        done
        if [ -L "$dir/probe_eddy_ng" ] || [ -d "$dir/probe_eddy_ng" ]; then
            info "Removing legacy directory: $dir/probe_eddy_ng"
            rm -rf "$dir/probe_eddy_ng"
        fi
    done

    # Remove legacy firmware symlinks
    if [ -L "$KLIPPER_DIR/src/sensor_ldc1612_ng.c" ] || [ -f "$KLIPPER_DIR/src/sensor_ldc1612_ng.c" ]; then
        info "Removing legacy firmware file: $KLIPPER_DIR/src/sensor_ldc1612_ng.c"
        rm -f "$KLIPPER_DIR/src/sensor_ldc1612_ng.c"
    fi
    if [ -L "$KLIPPER_DIR/src/extras/eddy-ng" ]; then
        info "Removing legacy firmware link: $KLIPPER_DIR/src/extras/eddy-ng"
        rm -f "$KLIPPER_DIR/src/extras/eddy-ng"
    fi
}

# ─── pip install ─────────────────────────────────────────────────────────────

install_pip_package() {
    header "Installing Python package"

    # Ensure numpy is available
    "$KLIPPY_ENV/bin/python" -c "
import sys
try:
    import numpy
    version = tuple(map(int, numpy.__version__.split('.')[:2]))
    if version >= (1, 16):
        sys.exit(0)
    sys.exit(1)
except ImportError:
    sys.exit(1)
" || {
        info "Installing numpy..."
        "$KLIPPY_ENV/bin/pip" install "numpy>=1.16"
    }

    info "Installing eddy-ng into $KLIPPY_ENV..."
    "$KLIPPY_ENV/bin/pip" install "$REPO_DIR"
    success "Python package installed"
}

uninstall_pip_package() {
    info "Uninstalling eddy-ng from $KLIPPY_ENV..."
    "$KLIPPY_ENV/bin/pip" uninstall -y eddy-ng 2>/dev/null || true
    success "Python package uninstalled"
}

# ─── Scaffolding ─────────────────────────────────────────────────────────────

create_scaffolding() {
    local scaff_dir
    scaff_dir=$(get_scaffolding_dir)

    header "Creating scaffolding files"

    # probe_eddy_ng.py scaffolding
    cp "$REPO_DIR/src/eddy_ng/scaffolding/probe_eddy_ng.py" "$scaff_dir/probe_eddy_ng.py"
    success "Created $scaff_dir/probe_eddy_ng.py"

    # ldc1612_ng.py scaffolding
    cp "$REPO_DIR/src/eddy_ng/scaffolding/ldc1612_ng.py" "$scaff_dir/ldc1612_ng.py"
    success "Created $scaff_dir/ldc1612_ng.py"

    # Add to .git/info/exclude (for stock Klipper only, not Kalico plugins dir)
    if [ $IS_KALICO -eq 0 ] && [ -d "$KLIPPER_DIR/.git" ]; then
        local exclude_file="$KLIPPER_DIR/.git/info/exclude"
        for f in "klippy/extras/probe_eddy_ng.py" "klippy/extras/ldc1612_ng.py"; do
            if ! grep -qF "$f" "$exclude_file" 2>/dev/null; then
                echo "$f" >> "$exclude_file"
            fi
        done
        info "Added scaffolding to git exclude"
    fi
}

remove_scaffolding() {
    local scaff_dir
    scaff_dir=$(get_scaffolding_dir)

    for f in probe_eddy_ng.py ldc1612_ng.py; do
        if [ -f "$scaff_dir/$f" ]; then
            rm -f "$scaff_dir/$f"
            info "Removed $scaff_dir/$f"
        fi
    done
}

# ─── Firmware: Makefile patching (for non-Duo sensors) ───────────────────────

install_firmware_patch() {
    header "Installing firmware module (Makefile patching)"

    local makefile="$KLIPPER_DIR/src/Makefile"

    if [ $IS_KALICO -eq 1 ]; then
        # Kalico: symlink the firmware extras directory
        local fw_dest="$KLIPPER_DIR/src/extras/eddy-ng"
        if [ -L "$fw_dest" ] || [ -d "$fw_dest" ]; then
            rm -rf "$fw_dest"
        fi
        ln -s "$REPO_DIR/eddy-ng" "$fw_dest"
        success "Firmware module linked to $fw_dest"
        info "In menuconfig, enable eddy-ng under firmware extras."
    else
        # Stock Klipper: symlink C file + patch Makefile
        local src_file="$KLIPPER_DIR/src/sensor_ldc1612_ng.c"
        local real_src="$REPO_DIR/eddy-ng/sensor_ldc1612_ng.c"

        if [ -L "$src_file" ] || [ -f "$src_file" ]; then
            rm -f "$src_file"
        fi
        ln -s "$(realpath "$real_src")" "$src_file"
        success "Firmware C file linked"

        if ! grep -q "sensor_ldc1612_ng.c" "$makefile" 2>/dev/null; then
            sed -i 's,sensor_ldc1612.c$,sensor_ldc1612.c sensor_ldc1612_ng.c,' "$makefile"
            success "Makefile patched"
        else
            success "Makefile already patched"
        fi
    fi

    echo ""
    warn "You need to rebuild and flash your printer's MCU firmware."
    echo "  Run: $REPO_DIR/flash.sh"
}

remove_firmware_patch() {
    local makefile="$KLIPPER_DIR/src/Makefile"
    if [ -f "$makefile" ]; then
        sed -i 's, sensor_ldc1612_ng.c,,' "$makefile"
        info "Makefile unpatched"
    fi
}

# ─── Duo: pre-built firmware flash ──────────────────────────────────────────

offer_duo_flash() {
    echo ""
    echo -e "${BOLD}Firmware for Eddy Duo${NC}"
    echo ""
    echo "Your Eddy Duo has its own RP2040 MCU. You can flash it with"
    echo "a pre-built firmware image (no Klipper source patching needed)."
    echo ""
    read -p "Flash Eddy Duo firmware now? [y/N]: " do_flash

    if [[ "$do_flash" =~ ^[yYjJ]$ ]]; then
        "$SCRIPT_DIR/flash-duo.sh" ${KLIPPER_DIR:+"$KLIPPER_DIR"}
    else
        echo ""
        info "You can flash later with: $SCRIPT_DIR/flash-duo.sh"
    fi
}

# ─── Uninstall ───────────────────────────────────────────────────────────────

do_uninstall() {
    header "Uninstalling eddy-ng"
    remove_legacy
    remove_scaffolding
    remove_firmware_patch
    uninstall_pip_package
    success "eddy-ng uninstalled"
}

# ─── Install flows ──────────────────────────────────────────────────────────

install_duo() {
    header "Installing eddy-ng for Eddy Duo (patchless)"

    remove_legacy
    install_pip_package
    create_scaffolding

    success "Python plugin installed (no Klipper source patching needed)"
    offer_duo_flash

    header "Done"
    echo -e "${GREEN}eddy-ng installed for Eddy Duo!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Make sure your Eddy Duo firmware is flashed"
    echo "  2. Check your printer.cfg (see $REPO_DIR/example-printer.cfg)"
    echo "  3. Restart Klipper: sudo systemctl restart klipper"
}

install_cartographer() {
    header "Installing eddy-ng for Cartographer (patchless)"

    remove_legacy
    install_pip_package
    create_scaffolding

    success "Python plugin installed (no Klipper source patching needed)"

    header "Done"
    echo -e "${GREEN}eddy-ng installed for Cartographer!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Set sensor_type: cartographer in your printer.cfg"
    echo "  2. Check your printer.cfg (see $REPO_DIR/example-printer.cfg)"
    echo "  3. Restart Klipper: sudo systemctl restart klipper"
}

install_other() {
    header "Installing eddy-ng for Eddy sensor (traditional)"

    remove_legacy
    install_pip_package
    create_scaffolding
    install_firmware_patch

    header "Done"
    echo -e "${GREEN}eddy-ng installed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Rebuild and flash your MCU firmware: $REPO_DIR/flash.sh"
    echo "  2. Check your printer.cfg (see $REPO_DIR/example-printer.cfg)"
    echo "  3. Restart Klipper: sudo systemctl restart klipper"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    find_klipper_dir
    find_klippy_env
    detect_kalico

    if [ $IS_KALICO -eq 1 ]; then
        info "Detected: Kalico at $KLIPPER_DIR"
    else
        info "Detected: Klipper at $KLIPPER_DIR"
    fi
    info "Virtualenv: $KLIPPY_ENV"

    if [ $UNINSTALL -eq 1 ]; then
        do_uninstall
        return
    fi

    # Sensor selection (interactive or via flag)
    if [ -z "$SENSOR_TYPE" ]; then
        header "eddy-ng Installer"
        echo "Which Eddy sensor do you have?"
        echo ""
        echo -e "  ${BOLD}1)${NC} Eddy Duo (RP2040-based, USB or CAN bus)"
        echo "     Patchless install: pip package + pre-built firmware"
        echo ""
        echo -e "  ${BOLD}2)${NC} Cartographer (RP2040-based, USB or CAN bus)"
        echo "     Patchless install: pip package (no firmware flash needed)"
        echo ""
        echo -e "  ${BOLD}3)${NC} Other (Eddy Coil, generic LDC1612, etc.)"
        echo "     Traditional install: pip package + Klipper source patching"
        echo ""
        read -p "Choose [1-3]: " choice

        case "$choice" in
            1) SENSOR_TYPE="duo" ;;
            2) SENSOR_TYPE="cartographer" ;;
            3) SENSOR_TYPE="other" ;;
            *) error "Invalid choice"; exit 1 ;;
        esac
    fi

    case "$SENSOR_TYPE" in
        duo)           install_duo ;;
        cartographer)  install_cartographer ;;
        other)         install_other ;;
        *)             error "Invalid sensor type: $SENSOR_TYPE"; exit 1 ;;
    esac
}

main
