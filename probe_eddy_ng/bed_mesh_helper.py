from __future__ import annotations

import numpy as np
from functools import cmp_to_key
from typing import TYPE_CHECKING, final

from ._compat import bed_mesh, ConfigWrapper

if TYPE_CHECKING:
    from .probe import ProbeEddy


@final
class BedMeshScanHelper:
    def __init__(self, eddy: ProbeEddy, config: ConfigWrapper):
        self._eddy = eddy
        self._printer = eddy._printer

        bmc = config.getsection("bed_mesh")
        self._bed_mesh = eddy._printer.load_object(bmc, "bed_mesh")
        self._x_points, self._y_points = bmc.getintlist("probe_count", count=2, note_valid=False)
        self._x_min, self._y_min = bmc.getfloatlist("mesh_min", count=2, note_valid=False)
        self._x_max, self._y_max = bmc.getfloatlist("mesh_max", count=2, note_valid=False)
        self._speed = bmc.getfloat("speed", 100.0, above=0.0, note_valid=False)
        self._scan_z = bmc.getfloat("horizontal_move_z", self._eddy.params.home_trigger_height, above=0.0, note_valid=False)

        self._x_offset = self._eddy.params.x_offset
        self._y_offset = self._eddy.params.y_offset

        self._mesh_points, self._mesh_path = self._generate_path()

    def _generate_path(self):
        x_vals = np.linspace(self._x_min, self._x_max, self._x_points)
        y_vals = np.linspace(self._y_min, self._y_max, self._y_points)
        path = []
        reverse = False

        for y in y_vals:
            row = [(x, y, True) for x in (reversed(x_vals) if reverse else x_vals)]
            path.extend(row)
            reverse = not reverse
        return path, path

    def _scan_path(self):
        th = self._eddy._toolhead
        times = []

        for pt in self._mesh_path:
            # TODO bounds
            th.manual_move([pt[0] - self._x_offset, pt[1] - self._y_offset, None], self._speed)
            th.register_lookahead_callback(lambda t: times.append(t))

        th.wait_moves()

        return times

    def _set_bed_mesh(self, heights):
        # heights is in the order of the _mesh_path points; convert to
        # be ordered min_y..max_y, min_x..max_x, then pull out the heights
        indexed_points = []
        i = 0
        for x, y, include in self._mesh_path:
            if not include:
                continue
            indexed_points.append((x, y, i))
            i += 1

        def sort_points(a, b):
            if a[1] < b[1]: # y first
                return -1
            if a[1] > b[1]:
                return 1
            if a[0] < b[0]: # then x
                return -1
            if a[0] > b[0]:
                return 1
            return 0

        indices = [ki for _, _, ki in sorted(indexed_points, key=cmp_to_key(sort_points))]

        ki = 0
        matrix = []
        for _ in range(self._y_points):
            row = []
            for _ in range(self._x_points):
                v = heights[indices[ki]]
                row.append(self._scan_z - v)
                ki += 1
            matrix.append(row)

        params = self._bed_mesh.bmc.mesh_config.copy()
        params.update({
            "min_x": self._x_min,
            "max_x": self._x_max,
            "min_y": self._y_min,
            "max_y": self._y_max,
            "x_count": self._x_points,
            "y_count": self._y_points,
        })
        mesh = bed_mesh.ZMesh(params, None)
        try:
            mesh.build_mesh(matrix)
        except bed_mesh.BedMeshError as e:
            raise self._printer.command_error(str(e))
        self._bed_mesh.set_mesh(mesh)
        self._eddy._log_msg("Mesh scan complete")

    def scan(self):
        th = self._eddy._toolhead

        # move to the start point
        v = self._mesh_path[0]
        th.manual_move([None, None, 10.0], self._eddy.params.lift_speed)
        th.manual_move([v[0] - self._x_offset, v[1] - self._y_offset, None], self._speed)
        th.manual_move([None, None, self._scan_z], self._eddy.params.probe_speed)
        th.wait_moves()

        heights = []

        sample_time = self._eddy.params.scan_sample_time

        with self._eddy.start_sampler() as sampler:
            path_times = self._scan_path()
            sampler.wait_for_sample_at_time(path_times[-1] + sample_time*2.)
            sampler.finish()

            heights = sampler.find_heights_at_times([(t - sample_time/2., t + sample_time/2.) for t in path_times])
            # Note plus tap_offset here, vs -tap_offset when probing. These are actual
            # heights, the other is "offset from real"
            heights = [h + self._eddy._tap_offset for h in heights]

            with open("/tmp/mesh.csv", "w") as mfile:
                mfile.write("time,x,y,z\n")
                for i in range(len(self._mesh_points)):
                    t = path_times[i]
                    x = self._mesh_points[i][0]
                    y = self._mesh_points[i][1]
                    z = heights[i]
                    mfile.write(f"{t},{x},{y},{z}\n")

            self._set_bed_mesh(heights)


def bed_mesh_ProbeManager_start_probe_override(self, gcmd):
    method = gcmd.get("METHOD", "automatic").lower()
    can_scan = False
    pprobe = self.printer.lookup_object("probe", None)
    if pprobe is not None:
        probe_name = pprobe.get_status(None).get("name", "")
        can_scan = "eddy" in probe_name
    if method == "rapid_scan" and can_scan:
        self.rapid_scan_helper.perform_rapid_scan(gcmd)
    else:
        self.probe_helper.start_probe(gcmd)
