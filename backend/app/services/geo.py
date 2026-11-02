from __future__ import annotations

import math
from typing import Iterable

EARTH_RADIUS_M = 6_371_000.0


def haversine_distance_m(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return EARTH_RADIUS_M * c


def point_to_polyline_distance_m(
    point_lat: float,
    point_lng: float,
    polyline: Iterable[tuple[float, float]],
) -> float:
    coords = list(polyline)
    if not coords:
        return math.inf
    if len(coords) == 1:
        return haversine_distance_m(point_lat, point_lng, coords[0][0], coords[0][1])

    ref_lat = point_lat
    px, py = _to_xy(point_lat, point_lng, ref_lat)

    min_distance = math.inf
    for i in range(len(coords) - 1):
        ax, ay = _to_xy(coords[i][0], coords[i][1], ref_lat)
        bx, by = _to_xy(coords[i + 1][0], coords[i + 1][1], ref_lat)
        distance = _distance_point_to_segment(px, py, ax, ay, bx, by)
        if distance < min_distance:
            min_distance = distance
    return min_distance


def _to_xy(lat: float, lng: float, ref_lat: float) -> tuple[float, float]:
    x = math.radians(lng) * EARTH_RADIUS_M * math.cos(math.radians(ref_lat))
    y = math.radians(lat) * EARTH_RADIUS_M
    return x, y


def _distance_point_to_segment(
    px: float,
    py: float,
    ax: float,
    ay: float,
    bx: float,
    by: float,
) -> float:
    abx = bx - ax
    aby = by - ay
    apx = px - ax
    apy = py - ay

    ab_len_sq = abx * abx + aby * aby
    if ab_len_sq == 0:
        return math.hypot(px - ax, py - ay)

    t = (apx * abx + apy * aby) / ab_len_sq
    t = max(0.0, min(1.0, t))

    cx = ax + t * abx
    cy = ay + t * aby
    return math.hypot(px - cx, py - cy)