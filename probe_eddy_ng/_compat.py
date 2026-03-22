# Klipper/Kalico compatibility imports
# This file may be distributed under the terms of the GNU GPLv3 license.
from __future__ import annotations

try:
    from klippy import mcu, pins, chelper
    from klippy.printer import Printer
    from klippy.configfile import ConfigWrapper
    from klippy.configfile import error as configerror
    from klippy.gcode import GCodeCommand
    from klippy.toolhead import ToolHead
    from klippy.extras import probe, manual_probe, bed_mesh
    from klippy.extras.homing import HomingMove

    IS_KALICO = True
    HAS_PROBE_RESULT_TYPE = False
except ImportError:
    import mcu  # type: ignore[no-redef]
    import pins  # type: ignore[no-redef]
    import chelper  # type: ignore[no-redef]
    from klippy import Printer  # type: ignore[no-redef]
    from configfile import ConfigWrapper  # type: ignore[no-redef]
    from configfile import error as configerror  # type: ignore[no-redef]
    from gcode import GCodeCommand  # type: ignore[no-redef]
    from toolhead import ToolHead  # type: ignore[no-redef]
    # When loaded as part of the probe_eddy_ng package inside klippy/extras,
    # the parent package is klippy.extras (stock Klipper) or the plugin package (Kalico).
    # We need to go up one level to reach klippy.extras for sibling modules.
    import importlib
    probe = importlib.import_module("..probe", __package__)
    manual_probe = importlib.import_module("..manual_probe", __package__)
    bed_mesh = importlib.import_module("..bed_mesh", __package__)
    HomingMove = importlib.import_module("..homing", __package__).HomingMove

    IS_KALICO = False
    HAS_PROBE_RESULT_TYPE = hasattr(manual_probe, "ProbeResult")

# Import the sensor driver from the parent package
import importlib as _importlib
ldc1612_ng = _importlib.import_module("..ldc1612_ng", __package__)

try:
    import plotly  # noqa
except ImportError:
    plotly = None  # type: ignore[assignment]

try:
    import scipy  # noqa
except ImportError:
    scipy = None  # type: ignore[assignment]
