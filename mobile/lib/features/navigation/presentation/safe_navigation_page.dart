import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/network/dio_provider.dart';
import '../../../core/ui/app_snackbar.dart';
import '../../../core/ui/road_theme.dart';
import '../../map/data/hazard_repository.dart';
import '../../map/domain/hazard_report.dart';
import '../data/place_search_service.dart';

class SafeNavigationPage extends ConsumerStatefulWidget {
  const SafeNavigationPage({super.key});

  @override
  ConsumerState<SafeNavigationPage> createState() => _SafeNavigationPageState();
}

class _SafeNavigationPageState extends ConsumerState<SafeNavigationPage> {
  static const _fallbackCenter = LatLng(12.9716, 77.5946);

  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _mapController = MapController();

  Timer? _originDebounce;
  Timer? _destinationDebounce;

  List<PlaceSuggestion> _originSuggestions = const <PlaceSuggestion>[];
  List<PlaceSuggestion> _destinationSuggestions = const <PlaceSuggestion>[];

  PlaceSuggestion? _selectedOrigin;
  PlaceSuggestion? _selectedDestination;

  List<_SafeRouteOption> _routes = const <_SafeRouteOption>[];
  int _selectedRouteIndex = 0;
  bool _isLoadingRoutes = false;

  LatLng _mapCenter = _fallbackCenter;

  @override
  void dispose() {
    _originDebounce?.cancel();
    _destinationDebounce?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hazardsAsync = ref.watch(hazardReportsProvider);
    final allHazards = hazardsAsync.asData?.value ?? const <HazardReport>[];
    final activeHazards = _activeHazards(allHazards);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardVisible = bottomInset > 0;

    return Stack(
      children: <Widget>[
        Positioned.fill(child: _buildMapLayer(activeHazards)),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final suggestionMaxHeight = (constraints.maxHeight * 0.36).clamp(
                120.0,
                200.0,
              );

              return Stack(
                children: <Widget>[
                  Align(
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _buildSearchCard(),
                        if (_originSuggestions.isNotEmpty ||
                            _destinationSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildSuggestionCard(maxHeight: suggestionMaxHeight),
                        ],
                      ],
                    ),
                  ),
                  if (!keyboardVisible)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _buildRouteSheet(),
                    ),
                ],
              );
            },
          ),
        ),
        if (_isLoadingRoutes)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.24),
              child: const Center(
                child: CircularProgressIndicator(color: RoadUi.caution),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapLayer(List<HazardReport> activeHazards) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: _mapCenter, initialZoom: 13),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.guardian.grid.mobile',
        ),
        PolylineLayer(polylines: _buildRoutePolylines()),
        MarkerLayer(
          markers: <Marker>[
            ..._buildStartEndMarkers(),
            ...activeHazards.map(_hazardMarker),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.map_outlined, color: Color(0xFF2C68E4)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Search source and destination',
                    style: TextStyle(
                      color: RoadUi.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          TextField(
            controller: _originController,
            onChanged: _onOriginQueryChanged,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              hintText: 'Source',
              prefixIcon: Icon(Icons.trip_origin, color: Color(0xFF1D8C52)),
            ),
          ),
          const Divider(height: 1),
          TextField(
            controller: _destinationController,
            onChanged: _onDestinationQueryChanged,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _fetchSafeRoutes(),
            decoration: const InputDecoration(
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              hintText: 'Destination',
              prefixIcon: Icon(Icons.place_outlined, color: Color(0xFFD43A2F)),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoadingRoutes ? null : _fetchSafeRoutes,
                    icon: const Icon(Icons.alt_route_rounded),
                    label: const Text('Find Routes'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2C68E4),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _isLoadingRoutes ? null : _clearRouteResults,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(80, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard({required double maxHeight}) {
    final showingOrigin = _originSuggestions.isNotEmpty;
    final suggestions = showingOrigin
        ? _originSuggestions
        : _destinationSuggestions;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: <Widget>[
                Icon(
                  showingOrigin
                      ? Icons.my_location_outlined
                      : Icons.place_outlined,
                  size: 16,
                  color: RoadUi.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  showingOrigin ? 'Pick source' : 'Pick destination',
                  style: const TextStyle(
                    color: RoadUi.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final place = suggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    place.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RoadUi.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  onTap: () {
                    if (showingOrigin) {
                      _selectOrigin(place);
                    } else {
                      _selectDestination(place);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSheet() {
    if (_routes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDE3EE)),
        ),
        child: const Text(
          'Search and select source/destination to view safe and alternate routes.',
          style: TextStyle(
            color: RoadUi.textMuted,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SizedBox(
        height: 126,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _routes.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final route = _routes[index];
            final selected = index == _selectedRouteIndex;
            final label = index == 0 ? 'Primary' : 'Alternate ${index + 1}';

            return InkWell(
              onTap: () {
                setState(() => _selectedRouteIndex = index);
                _fitMapToRoute(route.polyline);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 210,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEEF4FF)
                      : const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF2C68E4)
                        : const Color(0xFFD9E1EE),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        color: RoadUi.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Risk ${route.riskScore.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: _riskColor(route.riskScore),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'ETA ${route.eta}',
                      style: const TextStyle(
                        color: RoadUi.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Risks nearby: ${route.riskCount}',
                      style: const TextStyle(
                        color: RoadUi.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onOriginQueryChanged(String value) {
    if (_selectedOrigin != null &&
        value.trim() != _selectedOrigin!.displayName) {
      _selectedOrigin = null;
    }

    _originDebounce?.cancel();
    _originDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref
          .read(placeSearchServiceProvider)
          .searchPlaces(value);
      if (!mounted) {
        return;
      }
      setState(() => _originSuggestions = results);
    });
  }

  void _onDestinationQueryChanged(String value) {
    if (_selectedDestination != null &&
        value.trim() != _selectedDestination!.displayName) {
      _selectedDestination = null;
    }

    _destinationDebounce?.cancel();
    _destinationDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref
          .read(placeSearchServiceProvider)
          .searchPlaces(value);
      if (!mounted) {
        return;
      }
      setState(() => _destinationSuggestions = results);
    });
  }

  void _selectOrigin(PlaceSuggestion place) {
    setState(() {
      _selectedOrigin = place;
      _originController.text = place.displayName;
      _originSuggestions = const <PlaceSuggestion>[];
    });
    _originController.selection = TextSelection.collapsed(
      offset: _originController.text.length,
    );
    _moveMap(LatLng(place.latitude, place.longitude), zoom: 14);
  }

  void _selectDestination(PlaceSuggestion place) {
    setState(() {
      _selectedDestination = place;
      _destinationController.text = place.displayName;
      _destinationSuggestions = const <PlaceSuggestion>[];
    });
    _destinationController.selection = TextSelection.collapsed(
      offset: _destinationController.text.length,
    );
  }

  Future<void> _fetchSafeRoutes() async {
    if (_isLoadingRoutes) {
      return;
    }

    setState(() => _isLoadingRoutes = true);

    final origin = await _resolvePlaceInput(
      _originController.text,
      selected: _selectedOrigin,
      fallbackName: 'Typed Source',
    );
    final destination = await _resolvePlaceInput(
      _destinationController.text,
      selected: _selectedDestination,
      fallbackName: 'Typed Destination',
    );

    if (origin == null || destination == null) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingRoutes = false);
      showAppSnackBar(
        context,
        'Could not resolve source/destination. Pick suggestion or type "lat,lng".',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    final dio = ref.read(apiDioProvider);

    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/route/safe',
        data: <String, dynamic>{
          'origin_lat': origin.latitude,
          'origin_lng': origin.longitude,
          'dest_lat': destination.latitude,
          'dest_lng': destination.longitude,
        },
      );

      final data = response.data ?? const <String, dynamic>{};
      final routesRaw = data['routes'];
      if (routesRaw is! List) {
        if (!mounted) {
          return;
        }
        setState(() => _routes = const <_SafeRouteOption>[]);
        showAppSnackBar(context, 'No route data returned from backend.');
        return;
      }

      final parsed = _parseRoutes(routesRaw);
      if (parsed.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() => _routes = const <_SafeRouteOption>[]);
        showAppSnackBar(
          context,
          'No routes available currently. Try another destination.',
        );
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedOrigin = origin;
        _selectedDestination = destination;
        _originController.text = origin.displayName;
        _destinationController.text = destination.displayName;
        _originSuggestions = const <PlaceSuggestion>[];
        _destinationSuggestions = const <PlaceSuggestion>[];
        _routes = parsed;
        _selectedRouteIndex = 0;
      });
      _originController.selection = TextSelection.collapsed(
        offset: _originController.text.length,
      );
      _destinationController.selection = TextSelection.collapsed(
        offset: _destinationController.text.length,
      );
      _fitMapToAllRoutes(parsed);
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error.response?.data;
      final backendMessage = detail is Map<String, dynamic>
          ? (detail['detail']?.toString() ?? '')
          : '';

      if (error.response?.statusCode == 401) {
        showAppSnackBar(context, 'Session expired. Sign in again.');
      } else if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        final allHazards =
            ref.read(hazardReportsProvider).asData?.value ??
            const <HazardReport>[];
        final activeHazards = _activeHazards(allHazards);
        final fallbackRoutes = await _fetchFallbackRoutesFromOsrm(
          origin: origin,
          destination: destination,
          activeHazards: activeHazards,
        );
        if (fallbackRoutes.isNotEmpty) {
          if (!mounted) {
            return;
          }
          setState(() {
            _selectedOrigin = origin;
            _selectedDestination = destination;
            _originController.text = origin.displayName;
            _destinationController.text = destination.displayName;
            _originSuggestions = const <PlaceSuggestion>[];
            _destinationSuggestions = const <PlaceSuggestion>[];
            _routes = fallbackRoutes;
            _selectedRouteIndex = 0;
          });
          _originController.selection = TextSelection.collapsed(
            offset: _originController.text.length,
          );
          _destinationController.selection = TextSelection.collapsed(
            offset: _destinationController.text.length,
          );
          _fitMapToAllRoutes(fallbackRoutes);
          showAppSnackBar(
            context,
            'Backend unreachable. Showing fallback routes from OSRM.',
          );
          return;
        }

        final baseUrl = dio.options.baseUrl;
        showAppSnackBar(
          context,
          'Backend unreachable at $baseUrl. Start API server, then use adb reverse or API_BASE_URL.',
        );
      } else if (backendMessage.isNotEmpty) {
        showAppSnackBar(context, backendMessage);
      } else {
        showAppSnackBar(context, 'Could not fetch routes.');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Unexpected error while fetching routes.');
    } finally {
      if (mounted) {
        setState(() => _isLoadingRoutes = false);
      }
    }
  }

  Future<PlaceSuggestion?> _resolvePlaceInput(
    String text, {
    required PlaceSuggestion? selected,
    required String fallbackName,
  }) async {
    final typed = text.trim();
    if (typed.isEmpty) {
      return selected;
    }

    if (selected != null && selected.displayName.trim() == typed) {
      return selected;
    }

    final latLng = _tryParseLatLng(typed, fallbackName: fallbackName);
    if (latLng != null) {
      return latLng;
    }

    final results = await ref.read(placeSearchServiceProvider).searchPlaces(
      typed,
    );
    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }

  List<_SafeRouteOption> _parseRoutes(List<dynamic> routesRaw) {
    final parsed = <_SafeRouteOption>[];

    for (final raw in routesRaw.whereType<Map>()) {
      final map = Map<String, dynamic>.from(raw);
      final polylineRaw = map['polyline'];
      if (polylineRaw is! List) {
        continue;
      }

      final points = <LatLng>[];
      for (final rawPoint in polylineRaw) {
        if (rawPoint is! List || rawPoint.length < 2) {
          continue;
        }
        final lat = (rawPoint[0] as num?)?.toDouble();
        final lng = (rawPoint[1] as num?)?.toDouble();
        if (lat == null || lng == null) {
          continue;
        }
        points.add(LatLng(lat, lng));
      }

      if (points.isEmpty) {
        continue;
      }

      final breakdownRaw = map['risk_breakdown'];
      final breakdown = breakdownRaw is Map
          ? Map<String, dynamic>.from(breakdownRaw)
          : const <String, dynamic>{};

      parsed.add(
        _SafeRouteOption(
          polyline: points,
          riskScore: (map['risk_score'] as num?)?.toDouble() ?? 0,
          eta: map['eta']?.toString() ?? '-',
          riskCount: (breakdown['nearby_hazards'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    return parsed;
  }

  Future<List<_SafeRouteOption>> _fetchFallbackRoutesFromOsrm({
    required PlaceSuggestion origin,
    required PlaceSuggestion destination,
    required List<HazardReport> activeHazards,
  }) async {
    final osrm = Dio(
      BaseOptions(
        baseUrl: 'https://router.project-osrm.org',
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    try {
      final response = await osrm.get<Map<String, dynamic>>(
        '/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}',
        queryParameters: const <String, dynamic>{
          'alternatives': '3',
          'overview': 'full',
          'steps': 'false',
          'geometries': 'geojson',
        },
      );

      final payload = response.data ?? const <String, dynamic>{};
      final routesRaw = payload['routes'];
      if (routesRaw is! List || routesRaw.isEmpty) {
        return const <_SafeRouteOption>[];
      }

      final parsed = <_SafeRouteOption>[];
      for (final raw in routesRaw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(raw);
        final geometryRaw = map['geometry'];
        if (geometryRaw is! Map) {
          continue;
        }
        final geometry = Map<String, dynamic>.from(geometryRaw);
        final coordinatesRaw = geometry['coordinates'];
        if (coordinatesRaw is! List) {
          continue;
        }

        final points = <LatLng>[];
        for (final rawPoint in coordinatesRaw) {
          if (rawPoint is! List || rawPoint.length < 2) {
            continue;
          }
          final lng = (rawPoint[0] as num?)?.toDouble();
          final lat = (rawPoint[1] as num?)?.toDouble();
          if (lat == null || lng == null) {
            continue;
          }
          points.add(LatLng(lat, lng));
        }
        if (points.isEmpty) {
          continue;
        }

        final durationSeconds = (map['duration'] as num?)?.toDouble() ?? 0;
        final riskCount = _countNearbyHazards(points, activeHazards);
        final riskScore = (riskCount * 18.0).clamp(0.0, 100.0).toDouble();

        parsed.add(
          _SafeRouteOption(
            polyline: points,
            riskScore: riskScore,
            eta: _formatEta(durationSeconds),
            riskCount: riskCount,
          ),
        );
      }

      parsed.sort((a, b) {
        final byRisk = a.riskScore.compareTo(b.riskScore);
        if (byRisk != 0) {
          return byRisk;
        }
        return a.riskCount.compareTo(b.riskCount);
      });

      return parsed.take(3).toList(growable: false);
    } on DioException {
      return const <_SafeRouteOption>[];
    } catch (_) {
      return const <_SafeRouteOption>[];
    }
  }

  PlaceSuggestion? _tryParseLatLng(
    String text, {
    required String fallbackName,
  }) {
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final lat = double.tryParse(match.group(1) ?? '');
    final lng = double.tryParse(match.group(2) ?? '');
    if (lat == null || lng == null) {
      return null;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return null;
    }

    return PlaceSuggestion(
      displayName: fallbackName,
      latitude: lat,
      longitude: lng,
    );
  }

  int _countNearbyHazards(List<LatLng> routePoints, List<HazardReport> hazards) {
    if (routePoints.isEmpty || hazards.isEmpty) {
      return 0;
    }

    const distance = Distance();
    final sampledRoute = <LatLng>[];
    final step = (routePoints.length / 40).ceil().clamp(1, routePoints.length);
    for (var i = 0; i < routePoints.length; i += step) {
      sampledRoute.add(routePoints[i]);
    }
    final last = routePoints.last;
    if (sampledRoute.isEmpty ||
        sampledRoute.last.latitude != last.latitude ||
        sampledRoute.last.longitude != last.longitude) {
      sampledRoute.add(last);
    }

    var count = 0;
    for (final hazard in hazards) {
      final hazardPoint = LatLng(
        hazard.location.latitude,
        hazard.location.longitude,
      );
      var nearestMeters = double.infinity;
      for (final routePoint in sampledRoute) {
        final meters = distance.as(LengthUnit.Meter, hazardPoint, routePoint);
        if (meters < nearestMeters) {
          nearestMeters = meters;
        }
        if (nearestMeters <= 120) {
          break;
        }
      }
      if (nearestMeters <= 120) {
        count += 1;
      }
    }
    return count;
  }

  String _formatEta(double durationSeconds) {
    final minutes = math.max(1, (durationSeconds / 60).round());
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainder = minutes % 60;
      if (remainder == 0) {
        return '${hours}h';
      }
      return '${hours}h ${remainder}m';
    }
    return '$minutes min';
  }

  void _fitMapToAllRoutes(List<_SafeRouteOption> routes) {
    final points = <LatLng>[];
    for (final route in routes) {
      points.addAll(route.polyline);
    }

    if (_selectedOrigin != null) {
      points.add(LatLng(_selectedOrigin!.latitude, _selectedOrigin!.longitude));
    }
    if (_selectedDestination != null) {
      points.add(
        LatLng(_selectedDestination!.latitude, _selectedDestination!.longitude),
      );
    }

    if (points.isEmpty) {
      return;
    }

    _fitBounds(points);
  }

  void _fitMapToRoute(List<LatLng> points) {
    if (points.isEmpty) {
      return;
    }
    _fitBounds(points);
  }

  void _fitBounds(List<LatLng> points) {
    final bounds = LatLngBounds.fromPoints(points);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(52)),
        );
      } catch (_) {
        // Ignore map fitting errors during early build frames.
      }
    });
  }

  void _moveMap(LatLng center, {double zoom = 13}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _mapController.move(center, zoom);
      } catch (_) {
        // Ignore map move errors during early build frames.
      }
    });
  }

  void _clearRouteResults() {
    setState(() {
      _routes = const <_SafeRouteOption>[];
      _selectedRouteIndex = 0;
      _originSuggestions = const <PlaceSuggestion>[];
      _destinationSuggestions = const <PlaceSuggestion>[];
    });
  }

  List<Polyline> _buildRoutePolylines() {
    if (_routes.isEmpty) {
      return const <Polyline>[];
    }

    return _routes
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final route = entry.value;
          final selected = index == _selectedRouteIndex;

          final color = index == 0
              ? const Color(0xFF2068F4)
              : const Color(0xFF00A36C);

          return Polyline(
            points: route.polyline,
            strokeWidth: selected ? 6 : 4,
            color: selected ? color : color.withValues(alpha: 0.5),
          );
        })
        .toList(growable: false);
  }

  List<Marker> _buildStartEndMarkers() {
    final markers = <Marker>[];

    if (_selectedOrigin != null) {
      markers.add(
        Marker(
          point: LatLng(_selectedOrigin!.latitude, _selectedOrigin!.longitude),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.trip_origin,
            color: Color(0xFF1D8C52),
            size: 28,
          ),
        ),
      );
    }

    if (_selectedDestination != null) {
      markers.add(
        Marker(
          point: LatLng(
            _selectedDestination!.latitude,
            _selectedDestination!.longitude,
          ),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.flag_rounded,
            color: Color(0xFFD43A2F),
            size: 28,
          ),
        ),
      );
    }

    return markers;
  }

  List<HazardReport> _activeHazards(List<HazardReport> hazards) {
    final now = DateTime.now();
    return hazards
        .where((hazard) {
          if (hazard.status.toLowerCase() != 'verified') {
            return false;
          }
          final expiresAt = hazard.expiresAt;
          if (expiresAt != null && expiresAt.isBefore(now)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  Marker _hazardMarker(HazardReport report) {
    return Marker(
      point: LatLng(report.location.latitude, report.location.longitude),
      width: 34,
      height: 34,
      child: Tooltip(
        message: '${report.hazardType} (${report.severity})',
        child: Icon(
          Icons.warning_amber_rounded,
          size: 24,
          color: _severityColor(report.severity),
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFF8D0C0C);
      case 'high':
        return const Color(0xFFC12020);
      case 'medium':
        return const Color(0xFFCE7800);
      default:
        return const Color(0xFFBC8E00);
    }
  }

  Color _riskColor(double risk) {
    if (risk >= 70) {
      return const Color(0xFFC12020);
    }
    if (risk >= 40) {
      return const Color(0xFFCE7800);
    }
    return const Color(0xFF1B7F49);
  }
}

class _SafeRouteOption {
  const _SafeRouteOption({
    required this.polyline,
    required this.riskScore,
    required this.eta,
    required this.riskCount,
  });

  final List<LatLng> polyline;
  final double riskScore;
  final String eta;
  final int riskCount;
}
