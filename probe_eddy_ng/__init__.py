# EDDY-ng probe package
# This file may be distributed under the terms of the GNU GPLv3 license.
from __future__ import annotations

from ._compat import ConfigWrapper
from .probe import ProbeEddy
from .params import ProbeEddyParams, ProbeEddyProbeResult
from .frequency_map import ProbeEddyFrequencyMap
from .sampler import ProbeEddySampler
from .endstop import ProbeEddyEndstopWrapper
from .scanning import ProbeEddyScanningProbe
from .bed_mesh_helper import BedMeshScanHelper

__all__ = [
    "ProbeEddy",
    "ProbeEddyParams",
    "ProbeEddyProbeResult",
    "ProbeEddyFrequencyMap",
    "ProbeEddySampler",
    "ProbeEddyEndstopWrapper",
    "ProbeEddyScanningProbe",
    "BedMeshScanHelper",
    "load_config_prefix",
]


def load_config_prefix(config: ConfigWrapper):
    return ProbeEddy(config)
