# eddy-ng

Enhanced Eddy current probe support for [Klipper](https://github.com/Klipper3d/klipper) and [Kalico](https://github.com/KalicoCrew/kalico).

eddy-ng adds accurate Z-offset setting by physically making contact with the build surface ("tap"). Eddy current probes are very accurate, but suffer from drift due to temperature changes and surface conductivity variations. Instead of guesswork temperature compensation, eddy-ng takes a physical approach:

1. **Cold calibration** -- Calibrate at any temperature. The frequency-to-height mapping is stored as a JSON polynomial fit with full double precision.
2. **Coarse Z-home** -- Z-homing via the sensor uses this calibration regardless of current temperatures. Not accurate enough for printing, but sufficient for homing, gantry leveling, and other preparation.
3. **Precise tap** -- Just before printing (bed at print temp, nozzle warm but not hot), a precise Z-offset is determined by physically tapping the build surface. The nozzle touches the bed and the exact height is measured.
4. **Temperature-compensated mesh** -- The difference between sensor reading and actual tap height is saved as an offset. This offset compensates for thermal drift during bed mesh scanning.

## Supported Hardware

| Sensor Type | Description |
|---|---|
| `ldc1612` | TI LDC1612 inductive sensor |
| `btt_eddy` | BigTreeTech Eddy probe |
| `cartographer` | Cartographer probe |
| `mellow_fly` | Mellow Fly probe |
| `ldc1612_internal_clk` | LDC1612 with internal oscillator |

## Features

- **Butterworth bandpass filter** for tap detection (MCU-side, real-time)
- **Auto-threshold calibration** (`PROBE_EDDY_NG_CALIBRATE_THRESHOLD`) -- automatically finds the optimal tap sensitivity
- **Rapid bed mesh scanning** with lookahead motion planning
- **JSON calibration format** -- human-readable, exact precision via hex floats, replaces legacy pickle
- **Modular codebase** -- clean package structure with separated concerns
- **No Klipper source modifications** -- runtime integration without sed patches
- **Klipper + Kalico compatible** -- auto-detects and adapts to both firmware forks

## Requirements

- Python 3.8+
- NumPy
- Klipper or Kalico firmware
- An LDC1612-based eddy current probe

Optional:
- `scipy` -- only needed for custom Butterworth filter parameters (default filter coefficients are built-in)
- `plotly` -- for generating calibration and tap diagnostic plots

---

## Installation

### 1. Clone the repository

```bash
cd ~
git clone https://github.com/vvuk/eddy-ng.git
cd ~/eddy-ng
```

### 2. Run the install script

```bash
./install.sh
```

The script auto-detects whether you're running Klipper (`~/klipper`) or Kalico (`~/kalico`).

If your Klipper installation is in a non-standard location:

```bash
./install.sh /path/to/klipper
```

**What the installer does:**

| Component | Destination | Purpose |
|---|---|---|
| `probe_eddy_ng/` (package) | `klippy/extras/probe_eddy_ng/` | Python probe plugin |
| `ldc1612_ng.py` | `klippy/extras/ldc1612_ng.py` | Sensor driver |
| `sensor_ldc1612_ng.c` | `src/sensor_ldc1612_ng.c` | MCU firmware module |

By default, files are **symlinked** (so `git pull` updates apply immediately). Use `--copy` to copy files instead:

```bash
./install.sh --copy
```

**Kalico users:** The installer detects Kalico automatically and installs to `klippy/plugins/` instead. Symlinks are used so updates from `git pull` apply without reinstalling.

### 3. Build and flash MCU firmware

After installation, you need to rebuild the Klipper MCU firmware to include the eddy-ng sensor driver. Use the automated flash script:

```bash
cd ~/eddy-ng
./flash.sh
```

The script automatically:
- Detects your Klipper/Kalico installation
- Ensures eddy-ng is installed
- Opens `menuconfig` if no `.config` exists (select your MCU and enable LDC1612 support)
- Enables `CONFIG_WANT_LDC1612` if not already set
- Builds the firmware
- Auto-detects connected devices (USB, DFU, CAN) and offers flash options

**Common options:**

```bash
./flash.sh                              # Full build + interactive flash
./flash.sh --build-only                 # Build only, no flash
./flash.sh --menuconfig                 # Force menuconfig before build
./flash.sh --clean                      # Clean build first
./flash.sh --flash-device /dev/ttyACM0  # Specify flash device directly
./flash.sh /path/to/klipper             # Custom Klipper directory
```

**Supported flash methods:**
- USB Serial (auto-detected via `/dev/serial/by-id/`)
- DFU mode (via `dfu-util`)
- CAN bus (via Katapult/CANboot)
- SD card copy
- Manual device path

**Manual build (alternative):**

```bash
cd ~/klipper
make menuconfig   # Enable LDC1612 support under Sensors
make
make flash FLASH_DEVICE=/dev/serial/by-id/YOUR_DEVICE
```

### 4. Configure printer.cfg

Add the eddy-ng probe section to your `printer.cfg`. See [Example Configuration](#example-configuration) below for a complete reference.

### 5. Restart Klipper

```bash
sudo systemctl restart klipper
```

---

## Updating

### Updating eddy-ng only

```bash
cd ~/eddy-ng
git pull
sudo systemctl restart klipper
```

If you used the default symlink installation, `git pull` is sufficient -- symlinks point to the updated files. If you used `--copy`, re-run `./install.sh` after pulling.

### Updating Klipper (important!)

A Klipper update (`git pull` in `~/klipper`) **overwrites `src/Makefile`**, which removes the eddy-ng firmware patch. Use the update script to handle this automatically:

```bash
cd ~/eddy-ng
./update-klipper.sh
```

The script:
1. Updates eddy-ng (`git pull`)
2. Updates Klipper (`git pull`) -- stashes local changes if needed
3. Re-installs eddy-ng (re-patches `src/Makefile`, re-links files)
4. **Asks** whether to rebuild firmware -- detects if `src/` files changed and recommends accordingly
5. **Asks** whether to flash the rebuilt firmware
6. **Asks** whether to restart Klipper service

```
=== Step 4: Firmware ===

[WARN] Klipper was updated (a1b2c3d -> e4f5g6h).
[WARN] Detected 3 changed files in src/ or mcu.py -- firmware rebuild likely needed!

Rebuild MCU firmware? [y/N] y
[OK] Firmware rebuilt successfully

Flash firmware to MCU? [y/N] n
[INFO] Run ./flash.sh later to flash.
```

Use `--yes` to skip all prompts (auto-yes):

```bash
./update-klipper.sh --yes    # Non-interactive: update + rebuild + flash + restart
```

**Manual Klipper update (alternative):**

```bash
cd ~/klipper && git pull
cd ~/eddy-ng && ./install.sh     # Re-patch Makefile
sudo systemctl restart klipper   # Rebuild firmware only if needed
```

---

## Uninstallation

### Using the uninstall script

```bash
cd ~/eddy-ng
./uninstall.sh
```

Or with a custom Klipper path:

```bash
./uninstall.sh /path/to/klipper
```

### Manual uninstallation via install.py

```bash
cd ~/eddy-ng
python3 install.py --uninstall
```

**What the uninstaller does:**

1. Removes `probe_eddy_ng/` package from `klippy/extras/` (or `klippy/plugins/` for Kalico)
2. Removes `ldc1612_ng.py` from `klippy/extras/`
3. Removes `sensor_ldc1612_ng.c` from `src/`
4. Reverts the `src/Makefile` patch
5. Cleans up legacy single-file installations (`probe_eddy_ng.py`)
6. Reverts any legacy `bed_mesh.py` patches (from older eddy-ng versions)

After uninstalling, remove the `[probe_eddy_ng ...]` section from your `printer.cfg` and restart Klipper.

---

## Example Configuration

Below is a complete `printer.cfg` example with all available options and their defaults. You only need to set values that differ from the defaults.

```ini
# ============================================================================
# eddy-ng probe configuration
# ============================================================================
# Replace "my_eddy" with your preferred name. This name is used in
# all GCode commands (e.g. PROBE_EDDY_NG_TAP).
# ============================================================================

[probe_eddy_ng my_eddy]

# --- Sensor ---
# Type of LDC1612-based sensor connected.
# Options: ldc1612, btt_eddy, cartographer, mellow_fly, ldc1612_internal_clk
sensor_type: btt_eddy

# I2C bus configuration (depends on your board wiring)
i2c_mcu: mcu               # MCU the sensor is connected to
i2c_bus: i2c3a              # I2C bus name
i2c_speed: 400000           # I2C bus speed (Hz)

# --- Probe Offsets ---
# Physical offset between the probe coil center and the nozzle tip.
# MUST be set correctly -- eddy-ng will error if both are 0.0
# (unless allow_unsafe is True).
x_offset: -38.0
y_offset: -22.0

# --- Movement Speeds ---
#probe_speed: 5.0           # Speed for Z probing moves (mm/s)
#lift_speed: 10.0           # Speed for Z lift moves (mm/s)
#move_speed: 50.0           # Speed for XY positioning moves (mm/s)

# --- Z Homing ---
# These control the coarse Z-home via the eddy sensor.
#home_trigger_height: 2.0             # Height at which homing triggers (mm)
#home_trigger_safe_start_offset: 1.0  # Extra height above trigger to start (mm)

# --- Tap Detection ---
# Tap mode: "butter" (Butterworth bandpass filter) or "wma" (weighted moving average).
# Butter mode is recommended -- it is more precise and less noise-sensitive.
#tap_mode: butter

# Tap threshold -- sensitivity for detecting the nozzle touching the bed.
# Lower = more sensitive, higher = less sensitive.
# Use PROBE_EDDY_NG_CALIBRATE_THRESHOLD to find the optimal value automatically.
#tap_threshold: 250.0       # Default for butter mode (1000.0 for wma mode)

#tap_speed: 3.0             # Speed for tap moves (mm/s)
#tap_start_z: 3.0           # Z height to start tap from (mm)
#tap_target_z: -0.250       # Z target for tap (slightly below bed, mm)
#tap_adjust_z: 0.0          # Additional Z adjustment after tap (mm)

# --- Tap Sampling ---
#tap_samples: 3             # Number of consistent tap samples required
#tap_max_samples: 5         # Maximum tap attempts before failure
#tap_samples_stddev: 0.020  # Maximum standard deviation between samples (mm)
#tap_use_median: False      # Use median instead of mean for tap result

# --- Butterworth Filter (advanced) ---
# Only change these if you understand bandpass filter design.
# Custom values require scipy to be installed.
#tap_butter_lowcut: 5.0     # Low cutoff frequency (Hz)
#tap_butter_highcut: 25.0   # High cutoff frequency (Hz)
#tap_butter_order: 2        # Filter order

# --- Drive Current ---
# LDC1612 drive current register (0-31). 0 = use sensor default.
# Different currents can be used for regular probing vs. tap.
#reg_drive_current: 0
#tap_drive_current: 0

# --- Scanning / Bed Mesh ---
#scan_sample_time: 0.100        # Sample time per point during scanning (s)
#scan_sample_time_delay: 0.050  # Delay between scan samples (s)

# --- Calibration ---
#calibration_z_max: 15.0    # Maximum Z height during calibration (mm)
#calibration_points: 150    # Number of points to sample during calibration

# --- Safety & Debug ---
#allow_unsafe: False         # Allow x_offset=0 y_offset=0 (probe at nozzle)
#debug: True                 # Enable debug logging
#max_errors: 0               # Max sensor errors before aborting (0=unlimited)
#write_tap_plot: False       # Write HTML plot of final tap data
#write_every_tap_plot: False # Write HTML plot of every individual tap
```

### Minimal Configuration

For most users, only a few settings are needed:

```ini
[probe_eddy_ng my_eddy]
sensor_type: btt_eddy
i2c_mcu: mcu
i2c_bus: i2c3a
x_offset: -38.0
y_offset: -22.0
```

### Homing Configuration

To use the eddy probe for Z homing, add a virtual endstop:

```ini
[stepper_z]
endstop_pin: probe:z_virtual_endstop
# Remove or comment out any existing position_endstop line
#position_endstop: 0
homing_speed: 5
```

### Bed Mesh Configuration

```ini
[bed_mesh]
speed: 200
horizontal_move_z: 3
mesh_min: 30, 30
mesh_max: 320, 320
probe_count: 15, 15
algorithm: bicubic
```

### Print Start Macro Example

```ini
[gcode_macro PRINT_START]
gcode:
    # Home all axes
    G28

    # Heat bed to print temperature
    M190 S{params.BED_TEMP|default(60)}

    # Warm nozzle (not full temp -- avoid oozing during tap)
    M109 S150

    # Perform tap to get precise Z offset at print temperature
    PROBE_EDDY_NG_TAP

    # Bed mesh with temperature-compensated offset
    BED_MESH_CALIBRATE

    # Heat to full print temperature
    M109 S{params.EXTRUDER_TEMP|default(200)}

    # Start printing
    G0 Z2 F3000
```

---

## GCode Commands

### Calibration

| Command | Description |
|---|---|
| `PROBE_EDDY_NG_SETUP` | Interactive first-time setup wizard |
| `PROBE_EDDY_NG_CALIBRATE` | Calibrate frequency-to-height mapping |
| `PROBE_EDDY_NG_CALIBRATE_THRESHOLD` | Auto-find optimal tap threshold |
| `PROBE_EDDY_NG_CALIBRATION_STATUS` | Display calibration information |
| `PROBE_EDDY_NG_CLEAR_CALIBRATION` | Clear all calibration data |
| `PROBE_EDDY_NG_TEST_DRIVE_CURRENT` | Test a specific drive current |
| `PROBE_EDDY_NG_OPTIMIZE_DRIVE_CURRENT` | Test all DCs and find optimal for homing + tap |

### Probing

| Command | Description |
|---|---|
| `PROBE_EDDY_NG_PROBE` | Probe height (moves to trigger height) |
| `PROBE_EDDY_NG_PROBE_STATIC` | Probe height at current position (no move) |
| `PROBE_EDDY_NG_PROBE_ACCURACY` | Test probe repeatability |
| `PROBE_EDDY_NG_TAP` | Precise Z-offset by touching the bed |

### Configuration

| Command | Description |
|---|---|
| `PROBE_EDDY_NG_STATUS` | Show current status and last readings |
| `PROBE_EDDY_NG_SET_TAP_OFFSET` | Set/clear the tap offset for scanning |
| `PROBE_EDDY_NG_SET_TAP_ADJUST_Z` | Set additional tap Z adjustment |
| `Z_OFFSET_APPLY_PROBE` | Apply current G-Code Z offset to `tap_adjust_z` |

### Auto-Threshold Calibration

`PROBE_EDDY_NG_CALIBRATE_THRESHOLD` performs an ascending search to find the optimal tap threshold automatically:

```
PROBE_EDDY_NG_CALIBRATE_THRESHOLD [MODE=butter] [START=50] [MAX=2000] [SPEED=3.0] [SCREENING_SAMPLES=5] [VERIFICATION_SAMPLES=10] [SAMPLE_RANGE=0.010]
```

| Parameter | Default (butter) | Default (wma) | Description |
|---|---|---|---|
| `MODE` | `butter` | - | Detection mode: `butter` or `wma` |
| `START` | `50` | `200` | Starting threshold value |
| `MAX` | `2000` | `10000` | Maximum threshold to test |
| `SPEED` | `3.0` | `3.0` | Tap speed (mm/s) |
| `SCREENING_SAMPLES` | `5` | `5` | Quick screening taps per threshold |
| `VERIFICATION_SAMPLES` | `10` | `10` | Full verification taps |
| `SAMPLE_RANGE` | `0.010` | `0.010` | Required Z range (mm) for acceptance |

The calibrator tests thresholds with adaptive step sizes (larger steps when far from a working value, smaller steps when close). Each threshold goes through a quick screening phase, followed by full verification if screening passes. The first threshold that passes both phases is saved. Run `SAVE_CONFIG` afterwards to persist.

### Drive Current Optimization

`PROBE_EDDY_NG_OPTIMIZE_DRIVE_CURRENT` tests all drive currents in a range and selects the optimal one for both homing and tap:

```
PROBE_EDDY_NG_OPTIMIZE_DRIVE_CURRENT [START_DC=1] [END_DC=31] [TAP_VERIFY=5] [TOP_CANDIDATES=3] [MODE=butter] [SAVE=1] [DEBUG=0]
```

| Parameter | Default | Description |
|---|---|---|
| `START_DC` | `1` | First drive current to test |
| `END_DC` | `31` | Last drive current to test |
| `TAP_VERIFY` | `5` | Number of real test taps per top candidate (0 to skip) |
| `TOP_CANDIDATES` | `3` | How many top DCs to verify with real taps |
| `MODE` | `butter` | Tap mode for verification (`butter` or `wma`) |
| `SAVE` | `1` | Auto-save results (set 0 to preview only) |
| `DEBUG` | `0` | Write debug files for each DC |

The optimization runs in two phases:

**Phase 1 -- Calibration sweep:** For each drive current, a full Z sweep is performed and evaluated on:
- **RMSE** -- fit quality (lower is better)
- **Frequency spread** -- signal dynamic range (higher is better)
- **Height range** -- must cover the required range for homing (0.5-5.0mm) or tap (0.025-3.0mm)

**Phase 2 -- Tap verification:** The top `TOP_CANDIDATES` are tested with real taps. Each candidate performs `TAP_VERIFY` actual nozzle taps and is scored on:
- **Tap range** -- spread of Z values (lower is better)
- **Tap stddev** -- standard deviation of Z values (lower is better)
- **Success rate** -- percentage of taps that triggered correctly

The best DC for homing and tap are selected independently and saved as `reg_drive_current` and `tap_drive_current`. Run `SAVE_CONFIG` afterwards to persist.

---

## Typical Workflow

### First-Time Setup

1. Install eddy-ng and configure `printer.cfg`
2. Home X and Y axes
3. Run `PROBE_EDDY_NG_SETUP` -- interactive wizard guides you through initial positioning
4. Run `SAVE_CONFIG`
5. Run `PROBE_EDDY_NG_OPTIMIZE_DRIVE_CURRENT` -- finds best drive current for homing and tap
6. Run `SAVE_CONFIG`
7. Run `PROBE_EDDY_NG_CALIBRATE_THRESHOLD` -- finds optimal tap sensitivity
8. Run `SAVE_CONFIG`

Alternatively, step 3 (`PROBE_EDDY_NG_SETUP`) already finds a working drive current. Use `OPTIMIZE_DRIVE_CURRENT` afterwards if you want the **best** one, not just the first that works.

### Before Every Print

1. `G28` -- Home all axes (uses eddy for Z)
2. Heat bed to print temperature
3. `PROBE_EDDY_NG_TAP` -- Precise Z-offset at temperature
4. `BED_MESH_CALIBRATE` -- Bed mesh with thermal compensation
5. Start printing

---

## Project Structure

```
eddy-ng/
├── probe_eddy_ng/           # Python package (Klipper plugin)
│   ├── __init__.py          #   Package entry point & exports
│   ├── _compat.py           #   Klipper/Kalico compatibility layer
│   ├── probe.py             #   Main ProbeEddy class & GCode commands
│   ├── params.py            #   Configuration parameters & validation
│   ├── frequency_map.py     #   Calibration data (JSON serialization)
│   ├── sampler.py           #   Sensor sample collection
│   ├── endstop.py           #   Virtual endstop for Z homing
│   ├── scanning.py          #   Rapid bed mesh scanning
│   └── bed_mesh_helper.py   #   Bed mesh integration
├── ldc1612_ng.py            # LDC1612 sensor driver
├── eddy-ng/                 # MCU firmware module (C)
│   ├── sensor_ldc1612_ng.c  #   Sensor driver with tap detection
│   ├── Kconfig              #   Firmware build options
│   └── Makefile             #   Build integration
├── tests/                   # Test suite
│   └── test_frequency_map.py
├── install.py               # Install/uninstall script
├── install.sh               # Install wrapper
├── uninstall.sh             # Uninstall wrapper
├── flash.sh                 # Firmware build & flash automation
├── update-klipper.sh        # Safe Klipper update with re-patching
├── .github/workflows/       # CI pipeline
│   └── ci.yml
└── LICENSE                  # GPLv3
```

---

## Support

- **Discord:** [Sovol 3D Printers Discord](https://discord.gg/Zg45rA52G7) -- eddy-ng forum (not Sovol-specific, just where the project started)
- **Issues:** [GitHub Issues](https://github.com/vvuk/eddy-ng/issues)
- **Wiki:** [Full setup guide](https://github.com/vvuk/eddy-ng/wiki)

## License

This project is licensed under the [GNU General Public License v3](LICENSE).

Based on original `probe_eddy_current` code by Kevin O'Connor. Maintained by Vladimir Vukicevic.
