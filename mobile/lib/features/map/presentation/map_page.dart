import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/ui/road_theme.dart';
import '../data/hazard_repository.dart';
import '../data/open_meteo_weather_service.dart';
import '../domain/hazard_report.dart';

const _fallbackCenter = LatLng(12.9716, 77.5946);
const _liveHazardRadiusMeters = 200000.0;

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  String? _selectedReportId;
  final _mapController = MapController();
  late final Future<LatLng> _centerFuture;
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _currentLocation;
  Timer? _weatherRefreshTimer;
  ({double lat, double lng})? _weatherCoords;

  @override
  void initState() {
    super.initState();
    _centerFuture = _resolveCurrentCenter();
    Future<void>.microtask(_bootstrapCurrentLocation);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _weatherRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hazardReports = ref.watch(hazardReportsProvider);

    return FutureBuilder<LatLng>(
      future: _centerFuture,
      builder: (context, snapshot) {
        final center = _currentLocation ?? snapshot.data ?? _fallbackCenter;
        final reports = hazardReports.asData?.value ?? const <HazardReport>[];
        final referencePoint = _currentLocation ?? center;
        final nearbyReports = _filterReportsByRadius(reports, referencePoint);
        final selectedReport = _findSelectedReport(nearbyReports);
        final weatherCoords = _roundedWeatherCoords(center);
        final weatherLocationLabel =
            '${weatherCoords.lat.toStringAsFixed(4)}, ${weatherCoords.lng.toStringAsFixed(4)}';
        final currentLocationText = _currentLocation == null
            ? 'Locating current position...'
            : '${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}';
        _ensureWeatherAutoRefresh(weatherCoords);
        final weatherAsync = ref.watch(
          currentMapWeatherProvider(weatherCoords),
        );

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              RoadPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: RoadSectionHeader(
                            title: 'Live Hazard Map',
                            subtitle: 'Issue, severity, and weather awareness',
                            icon: Icons.map_outlined,
                          ),
                        ),
                        RoadStatusChip(
                          label: '${nearbyReports.length} active (200 km)',
                          color: const Color(0xFF1B7F49),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.my_location_rounded,
                          size: 16,
                          color: Color(0xFF1B7F49),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            currentLocationText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1B7F49),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: <Widget>[
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: 13,
                          onTap: (_, _) {
                            if (_selectedReportId != null) {
                              setState(() => _selectedReportId = null);
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.guardian.grid.mobile',
                          ),
                          MarkerLayer(
                            markers: <Marker>[
                              if (_currentLocation != null)
                                _buildCurrentLocationMarker(_currentLocation!),
                              ...nearbyReports.map(
                                  (report) => Marker(
                                    point: LatLng(
                                      report.location.latitude,
                                      report.location.longitude,
                                    ),
                                    width: 52,
                                    height: 52,
                                    child: Tooltip(
                                      message:
                                          '${_prettify(report.hazardType)} (${_prettify(report.severity)})',
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _selectedReportId = report.id,
                                        ),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.94,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _severityColor(
                                                report.severity,
                                              ),
                                              width: 2,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Icon(
                                              Icons.warning_amber_rounded,
                                              color: _severityColor(
                                                report.severity,
                                              ),
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _WeatherOverlayCard(
                          weatherAsync: weatherAsync,
                          weatherLocationLabel: weatherLocationLabel,
                          onRefresh: () {
                            ref.invalidate(
                              currentMapWeatherProvider(weatherCoords),
                            );
                          },
                        ),
                      ),
                      Positioned(top: 10, right: 10, child: _LegendCard()),
                      if (selectedReport != null)
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: _SelectedHazardCard(
                            report: selectedReport,
                            onClose: () =>
                                setState(() => _selectedReportId = null),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              RoadPanel(
                child: hazardReports.when(
                  data: (loadedReports) {
                    final filteredReports = _filterReportsByRadius(
                      loadedReports,
                      referencePoint,
                    );
                    if (filteredReports.isEmpty) {
                      return const Text(
                        'No hazards within 200 km of your current location.',
                        style: TextStyle(
                          color: RoadUi.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }

                    final latest = filteredReports
                        .take(3)
                        .toList(growable: false);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live hazards (200 km): ${filteredReports.length}',
                          style: const TextStyle(
                            color: RoadUi.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...latest.map(
                          (report) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${_prettify(report.hazardType)} - ${_prettify(report.severity)}',
                              style: const TextStyle(
                                color: RoadUi.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Text(
                    'Loading live hazards...',
                    style: TextStyle(
                      color: RoadUi.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  error: (error, _) => Text(
                    _hazardErrorMessage(error),
                    style: const TextStyle(
                      color: Color(0xFFB52929),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  HazardReport? _findSelectedReport(List<HazardReport> reports) {
    if (_selectedReportId == null) {
      return null;
    }
    for (final report in reports) {
      if (report.id == _selectedReportId) {
        return report;
      }
    }
    return null;
  }

  List<HazardReport> _filterReportsByRadius(
    List<HazardReport> reports,
    LatLng center,
  ) {
    return reports.where((report) {
      final distance = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        report.location.latitude,
        report.location.longitude,
      );
      return distance <= _liveHazardRadiusMeters;
    }).toList(growable: false);
  }

  ({double lat, double lng}) _roundedWeatherCoords(LatLng center) {
    return (
      lat: _roundTo(center.latitude, 2),
      lng: _roundTo(center.longitude, 2),
    );
  }

  void _ensureWeatherAutoRefresh(({double lat, double lng}) coords) {
    if (_weatherCoords == coords && _weatherRefreshTimer != null) {
      return;
    }

    _weatherRefreshTimer?.cancel();
    _weatherCoords = coords;
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(currentMapWeatherProvider(coords));
    });
  }

  double _roundTo(double value, int decimalPlaces) {
    final factor = decimalPlaces == 0
        ? 1.0
        : math.pow(10, decimalPlaces).toDouble();
    return (value * factor).roundToDouble() / factor;
  }

  Future<void> _bootstrapCurrentLocation() async {
    final canTrack = await _canUseLocation();
    if (!canTrack) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // Keep map functional even if first GPS fix is delayed.
    }

    await _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    final canTrack = await _canUseLocation();
    if (!canTrack) {
      return;
    }

    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    });
  }

  Future<bool> _canUseLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Marker _buildCurrentLocationMarker(LatLng point) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: Tooltip(
        message: 'Current location',
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x332C68E4),
            border: Border.all(color: const Color(0x772C68E4), width: 1.2),
          ),
          child: Center(
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2C68E4),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherOverlayCard extends StatelessWidget {
  const _WeatherOverlayCard({
    required this.weatherAsync,
    required this.weatherLocationLabel,
    required this.onRefresh,
  });

  final AsyncValue<MapWeatherSnapshot> weatherAsync;
  final String weatherLocationLabel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: weatherAsync.when(
            loading: () => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Loading weather...',
                  style: TextStyle(
                    color: RoadUi.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    weatherLocationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RoadUi.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            error: (error, _) => Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: Color(0xFFB52929),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'Weather unavailable',
                        style: TextStyle(
                          color: Color(0xFFB52929),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        weatherLocationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: RoadUi.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  tooltip: 'Retry weather',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            data: (weather) {
              final cautionColor = _weatherCautionColor(weather.caution);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_outlined,
                        size: 16,
                        color: RoadUi.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          weather.condition,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: RoadUi.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        tooltip: 'Refresh weather',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Weather at: $weatherLocationLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RoadUi.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${weather.temperatureC.toStringAsFixed(1)} C | Rain ${weather.precipitationMm.toStringAsFixed(1)} mm',
                    style: const TextStyle(
                      color: RoadUi.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Wind ${weather.windKmh.toStringAsFixed(1)} km/h',
                    style: const TextStyle(
                      color: RoadUi.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cautionColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cautionColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      'Road: ${weather.caution}',
                      style: TextStyle(
                        color: cautionColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Color _weatherCautionColor(String caution) {
    switch (caution.toLowerCase()) {
      case 'high risk':
        return const Color(0xFFC12020);
      case 'caution':
        return const Color(0xFFCE7800);
      default:
        return const Color(0xFF1B7F49);
    }
  }
}

class _SelectedHazardCard extends StatelessWidget {
  const _SelectedHazardCard({required this.report, required this.onClose});

  final HazardReport report;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: _severityColor(report.severity),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _prettify(report.hazardType),
                    style: const TextStyle(
                      color: RoadUi.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Severity: ${_prettify(report.severity)}',
                    style: TextStyle(
                      color: _severityColor(report.severity),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((report.locationText ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      report.locationText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RoadUi.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _LegendRow(label: 'Critical', color: Color(0xFF8D0C0C)),
            _LegendRow(label: 'High', color: Color(0xFFC12020)),
            _LegendRow(label: 'Medium', color: Color(0xFFCE7800)),
            _LegendRow(label: 'Low', color: Color(0xFFBC8E00)),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: RoadUi.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

String _prettify(String raw) {
  final normalized = raw.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) {
    return raw;
  }
  return normalized
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) {
        final lower = word.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

Color _severityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return Colors.red.shade900;
    case 'high':
      return Colors.red.shade600;
    case 'medium':
      return Colors.orange.shade700;
    default:
      return Colors.amber.shade700;
  }
}

String _hazardErrorMessage(Object error) {
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return 'Permission denied while reading hazards. Check Firebase rules and sign-in.';
    }
    if (error.code == 'unavailable') {
      return 'Hazard stream unavailable. Check internet/Firebase connection.';
    }
    if (error.code == 'failed-precondition') {
      return 'Firestore query needs an index or valid query fields.';
    }
    return 'Hazard read failed (${error.code}). ${error.message ?? ''}'.trim();
  }

  final text = error.toString();
  if (text.isEmpty) {
    return 'Unable to read hazards right now.';
  }
  return 'Unable to read hazards: $text';
}

Future<LatLng> _resolveCurrentCenter() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _fallbackCenter;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return _fallbackCenter;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    return _fallbackCenter;
  }
}
