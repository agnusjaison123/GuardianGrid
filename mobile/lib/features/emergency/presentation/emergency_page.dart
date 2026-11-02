import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/ui/app_snackbar.dart';
import '../../../core/ui/road_theme.dart';
import '../../map/data/open_meteo_weather_service.dart';
import '../data/emergency_alert_service.dart';
import '../data/emergency_contact.dart';
import '../data/emergency_contacts_repository.dart';
import '../data/emergency_local_notifications.dart';
import '../data/emergency_voice_alert.dart';
import '../data/obd_telemetry_service.dart';

class EmergencyPage extends ConsumerStatefulWidget {
  const EmergencyPage({super.key});

  @override
  ConsumerState<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends ConsumerState<EmergencyPage> {
  static const _accThreshold = 9.0;
  static const _gyroThreshold = 4.0;
  static const _highSpeedThreshold = 18.0;
  static const _lowSpeedThreshold = 7.0;
  static const _triggerWindow = Duration(seconds: 3);
  static const _speedDropWindow = Duration(seconds: 8);
  static const _signalHoldWindow = Duration(seconds: 4);
  static const _cooldown = Duration(minutes: 5);
  static const _fallbackLat = 12.9716;
  static const _fallbackLng = 77.5946;

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<int>? _queueSub;
  StreamSubscription<ObdTelemetrySnapshot>? _obdSub;
  Timer? _cancelTimer;

  bool _monitoringEnabled = true;
  bool _isMonitoring = false;
  bool _pendingAlert = false;
  bool _dispatching = false;
  bool _permissionBlocked = false;
  int _countdown = 0;
  int _queuedAlerts = 0;
  int _contacts = 0;

  double _accMag = 0;
  double _gyroMag = 0;
  double _speedKmh = 0;
  double? _lat;
  double? _lng;
  bool _obdConnected = false;
  String _obdStatus = 'OBD-II disconnected';
  double? _obdSpeedKmh;
  double? _obdRpm;

  DateTime? _accAt;
  DateTime? _gyroAt;
  DateTime? _gpsAt;
  ({double speedKmh, DateTime at})? _lastHighSpeed;
  DateTime? _lastCrashAt;
  DateTime? _lastAlertAt;

  ({double lat, double lng}) _weatherCoords = (
    lat: _fallbackLat,
    lng: _fallbackLng,
  );
  String _status = 'Initializing automatic monitor...';
  String _lastAlert = 'No alert sent yet';

  int _manualContactSeed = 0;
  final List<_ManualContactDraft> _manualContactDrafts = <_ManualContactDraft>[
    _ManualContactDraft(id: 0),
  ];

  late final EmergencyAlertService _alertService;
  late final EmergencyLocalNotifications _notifications;
  late final EmergencyVoiceAlert _voiceAlert;
  late final ObdTelemetryService _obdTelemetryService;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;

    _alertService = ref.read(emergencyAlertServiceProvider);
    _notifications = ref.read(emergencyLocalNotificationsProvider);
    _voiceAlert = ref.read(emergencyVoiceAlertProvider);
    _obdTelemetryService = ref.read(obdTelemetryServiceProvider);
    _queueSub = _alertService.watchQueueCount().listen((count) {
      if (mounted) setState(() => _queuedAlerts = count);
    });
    _obdSub = _obdTelemetryService.stream.listen(_onObdTelemetry);

    Future<void>.microtask(() async {
      await _notifications.initialize();
      await _voiceAlert.initialize();
      await _alertService.initialize();
      await _obdTelemetryService.initializeAndAutoConnect();
      _alertService.startQueueRetryLoop();
      final queueCount = await _alertService.queuedCount();
      final contacts = await _loadContactsCount();
      if (!mounted) return;
      setState(() {
        _queuedAlerts = queueCount;
        _contacts = contacts;
      });
      if (_monitoringEnabled) {
        await _startMonitoring();
      }
    });
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _obdSub?.cancel();
    if (!kIsWeb) {
      _alertService.stopQueueRetryLoop();
      unawaited(_voiceAlert.stop());
      unawaited(_obdTelemetryService.disconnect());
    }
    for (final draft in _manualContactDrafts) {
      draft.dispose();
    }
    _stopMonitoring(updateUi: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const _WebOnlyCard();
    final weatherAsync = ref.watch(currentMapWeatherProvider(_weatherCoords));

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        _buildControlPanel(),
        const SizedBox(height: 10),
        _buildEmergencyStatusCard(),
        const SizedBox(height: 10),
        _buildManualContactCard(),
        const SizedBox(height: 10),
        _buildLocationCard(),
        const SizedBox(height: 10),
        _buildObdCard(),
        const SizedBox(height: 10),
        _buildWeatherCard(weatherAsync),
        const SizedBox(height: 10),
        if (_pendingAlert) _buildCountdownCard(),
        if (_pendingAlert) const SizedBox(height: 10),
        _buildIndicatorsCard(),
        const SizedBox(height: 10),
        _buildQueueCard(),
        const SizedBox(height: 10),
        const RoadPanel(
          child: _InfoTile(
            icon: Icons.info_outline_rounded,
            title: 'Crash detection rule',
            subtitle:
                'Alert starts when impact + rotation + sudden speed drop (GPS/OBD-II) align within a short window. For very hard low-speed impact, speed-drop fallback can trigger too.',
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return RoadPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: RoadSectionHeader(
                  title: 'Emergency Monitor',
                  subtitle:
                      'Real phone accelerometer + gyroscope + GPS (+ OBD-II optional)',
                  icon: Icons.health_and_safety_outlined,
                ),
              ),
              RoadStatusChip(
                label: _isMonitoring ? 'Active' : 'Inactive',
                color: _isMonitoring
                    ? const Color(0xFF1B7F49)
                    : const Color(0xFF8A8F9B),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Automatic monitoring',
                  style: TextStyle(
                    color: RoadUi.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: _monitoringEnabled,
                onChanged: _dispatching ? null : _toggleMonitoring,
              ),
            ],
          ),
          if (_permissionBlocked) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _dispatching ? null : _startMonitoring,
              icon: const Icon(Icons.location_searching_outlined),
              label: const Text('Grant Location Permission'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _status,
            style: const TextStyle(
              color: RoadUi.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyStatusCard() {
    final manualContacts = _manualContactsFromInput();
    final hasInvalidManualPhone = _hasInvalidManualContactPhone();
    return RoadPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Emergency Status',
            style: TextStyle(
              color: RoadUi.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _statusRow(
            'Emergency contacts',
            _contacts > 0
                ? '$_contacts phone contacts configured'
                : 'No phone contact configured',
            _contacts > 0 ? const Color(0xFF1B7F49) : const Color(0xFFC12020),
          ),
          const SizedBox(height: 6),
          _statusRow(
            'Manual contacts',
            hasInvalidManualPhone
                ? 'Fix invalid phone numbers'
                : manualContacts.isNotEmpty
                ? '${manualContacts.length} ready from textbox'
                : 'Not set',
            hasInvalidManualPhone
                ? const Color(0xFFC12020)
                : manualContacts.isNotEmpty
                ? const Color(0xFF1B7F49)
                : const Color(0xFF8A8F9B),
          ),
          const SizedBox(height: 6),
          _statusRow(
            'OBD-II',
            _obdConnected ? 'Connected' : 'Not connected',
            _obdConnected
                ? const Color(0xFF1B7F49)
                : const Color(0xFF8A8F9B),
          ),
          const SizedBox(height: 6),
          _statusRow(
            'Alert method',
            'In-app alert + Email + SMS (+ offline queue)',
            const Color(0xFF2C68E4),
          ),
          const SizedBox(height: 6),
          _statusRow('Last alert', _lastAlert, const Color(0xFF61708B)),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    final coords = (_lat != null && _lng != null)
        ? '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}'
        : 'Waiting for GPS fix';
    final speedSource = (_obdConnected && _obdSpeedKmh != null)
        ? 'OBD-II speed'
        : 'GPS speed';
    return RoadPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Live GPS',
            style: TextStyle(
              color: RoadUi.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coordinates: $coords',
            style: const TextStyle(
              color: RoadUi.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$speedSource: ${_speedKmh.toStringAsFixed(1)} km/h',
            style: const TextStyle(
              color: RoadUi.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObdCard() {
    final statusColor = _obdConnected
        ? const Color(0xFF1B7F49)
        : const Color(0xFFCE7800);
    final speedText = _obdSpeedKmh == null
        ? '--'
        : '${_obdSpeedKmh!.toStringAsFixed(1)} km/h';
    final rpmText = _obdRpm == null ? '--' : _obdRpm!.toStringAsFixed(0);

    return RoadPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'OBD-II Telemetry',
                  style: TextStyle(
                    color: RoadUi.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _dispatching ? null : _reconnectObd,
                icon: const Icon(Icons.usb_rounded, size: 18),
                label: const Text('Reconnect'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _statusRow(
            'Connection',
            _obdConnected ? 'Connected' : 'Disconnected',
            statusColor,
          ),
          const SizedBox(height: 6),
          _statusRow('Adapter', _obdStatus, const Color(0xFF61708B)),
          const SizedBox(height: 6),
          _statusRow('Vehicle speed', speedText, const Color(0xFF2C68E4)),
          const SizedBox(height: 6),
          _statusRow('Engine RPM', rpmText, const Color(0xFF2C68E4)),
          if (!_obdConnected) ...[
            const SizedBox(height: 8),
            Text(
              _obdStatus,
              style: const TextStyle(
                color: RoadUi.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualContactCard() {
    final hasInvalidManualPhone = _hasInvalidManualContactPhone();

    return RoadPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Manual Emergency Contacts',
                  style: TextStyle(
                    color: RoadUi.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _dispatching ? null : _addManualContactRow,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Optional fallback contacts used when dispatching crash alerts.',
            style: TextStyle(
              color: RoadUi.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasInvalidManualPhone) ...[
            const SizedBox(height: 8),
            const Text(
              'One or more manual contact phone numbers are invalid.',
              style: TextStyle(
                color: Color(0xFFC12020),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < _manualContactDrafts.length; i++) ...[
            _buildManualContactRow(_manualContactDrafts[i], i),
            if (i != _manualContactDrafts.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildManualContactRow(_ManualContactDraft draft, int index) {
    final phoneRaw = draft.phoneController.text.trim();
    final hasPhone = phoneRaw.isNotEmpty;
    final phoneValid = !hasPhone || _isValidPhone(phoneRaw);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7DFEB)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Contact ${index + 1}',
                style: const TextStyle(
                  color: RoadUi.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Remove contact',
                onPressed:
                    _dispatching || _manualContactDrafts.length == 1
                    ? null
                    : () => _removeManualContactRow(draft.id),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextField(
            controller: draft.nameController,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Contact name',
              hintText: 'Parent / Friend / Guardian',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Contact phone',
              hintText: '+91XXXXXXXXXX',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              errorText: phoneValid ? null : 'Enter a valid phone number.',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addManualContactRow() {
    setState(() {
      _manualContactSeed += 1;
      _manualContactDrafts.add(_ManualContactDraft(id: _manualContactSeed));
    });
  }

  void _removeManualContactRow(int id) {
    if (_manualContactDrafts.length == 1) {
      return;
    }
    final index = _manualContactDrafts.indexWhere((draft) => draft.id == id);
    if (index < 0) {
      return;
    }
    setState(() {
      final draft = _manualContactDrafts.removeAt(index);
      draft.dispose();
    });
  }

  Widget _buildWeatherCard(AsyncValue<MapWeatherSnapshot> weatherAsync) {
    return RoadPanel(
      child: weatherAsync.when(
        loading: () => const Text(
          'Loading local weather...',
          style: TextStyle(
            color: RoadUi.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        error: (error, _) => const Text(
          'Weather unavailable. Monitoring continues.',
          style: TextStyle(
            color: Color(0xFFB52929),
            fontWeight: FontWeight.w700,
          ),
        ),
        data: (weather) {
          final color = _weatherColor(weather.caution);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Local weather | ${weather.condition}',
                style: const TextStyle(
                  color: RoadUi.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${weather.temperatureC.toStringAsFixed(1)} C | Rain ${weather.precipitationMm.toStringAsFixed(1)} mm | Wind ${weather.windKmh.toStringAsFixed(1)} km/h',
                style: const TextStyle(
                  color: RoadUi.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.45)),
                ),
                child: Text(
                  'Road weather risk: ${weather.caution}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIndicatorsCard() {
    final accActive = _isSignalActive(_accAt);
    final gyroActive = _isSignalActive(_gyroAt);
    final speedDropActive = _isSignalActive(_gpsAt);
    final tripleActive = _isTripleTriggered();

    return RoadPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _Indicator(
                width: width,
                title: 'Accelerometer',
                status: accActive ? 'Impact detected' : 'Normal',
                active: accActive,
              ),
              _Indicator(
                width: width,
                title: 'Gyroscope',
                status: gyroActive ? 'Rotation spike' : 'Normal',
                active: gyroActive,
              ),
              _Indicator(
                width: width,
                title: 'Speed Drop (GPS/OBD)',
                status: speedDropActive
                    ? 'Sudden drop detected'
                    : _lastHighSpeed == null
                    ? 'Waiting for speed spike'
                    : 'Tracking drop...',
                active: speedDropActive,
              ),
              _Indicator(
                width: width,
                title: 'Crash Window',
                status: tripleActive ? 'All conditions met' : 'Waiting for 3 signals',
                active: tripleActive,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQueueCard() {
    return RoadPanel(
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_upload_outlined, color: RoadUi.caution),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Queued alerts: $_queuedAlerts (auto-retry every 30s)',
              style: const TextStyle(
                color: RoadUi.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _dispatching ? null : _retryQueueNow,
            child: const Text('Retry now'),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3B0B0)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB52929)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Possible crash detected. Sending alert in $_countdown s.',
              style: const TextStyle(
                color: Color(0xFF8E1E1E),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancelPendingAlert,
            child: const Text('I\'m OK'),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, Color color) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: const TextStyle(
              color: RoadUi.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleMonitoring(bool enabled) async {
    setState(() => _monitoringEnabled = enabled);
    if (!enabled) {
      _stopMonitoring();
      setState(() => _status = 'Monitoring turned off manually.');
      return;
    }
    await _startMonitoring();
  }

  Future<void> _startMonitoring() async {
    if (kIsWeb || !_monitoringEnabled || _isMonitoring) return;
    final ok = await _ensureLocationPermission();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _permissionBlocked = true;
        _status = 'Location permission blocked. Enable permission to monitor.';
      });
      showAppSnackBar(
        context,
        'Allow location permission for emergency monitoring.',
      );
      return;
    }

    try {
      _accSub = accelerometerEventStream().listen(_onAcc);
      _gyroSub = gyroscopeEventStream().listen(_onGyro);
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen(_onPos);
      setState(() {
        _permissionBlocked = false;
        _isMonitoring = true;
        _status = 'Monitoring active using phone sensors and GPS.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Failed to start monitoring.');
      showAppSnackBar(context, 'Failed to start emergency monitoring.');
    }
  }

  void _stopMonitoring({bool updateUi = true}) {
    _accSub?.cancel();
    _gyroSub?.cancel();
    _posSub?.cancel();
    _cancelTimer?.cancel();
    _accSub = null;
    _gyroSub = null;
    _posSub = null;
    _cancelTimer = null;
    _isMonitoring = false;
    _pendingAlert = false;
    _countdown = 0;
    if (updateUi && mounted) setState(() {});
  }

  void _onAcc(AccelerometerEvent e) {
    if (!_isMonitoring || !mounted) return;
    final now = DateTime.now();
    final rawMag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final linearMag = (rawMag - 9.81).abs();
    final hit = linearMag >= _accThreshold;
    final synthesizeSpeedDrop =
        _lastHighSpeed == null &&
        linearMag >= (_accThreshold * 1.6) &&
        _speedKmh <= _lowSpeedThreshold;

    setState(() {
      _accMag = linearMag;
      if (hit) {
        _accAt = now;
      }
      if (synthesizeSpeedDrop) {
        _gpsAt = now;
      }
    });
    if (hit || synthesizeSpeedDrop) {
      _checkCrashWindow();
    }
  }

  void _onGyro(GyroscopeEvent e) {
    if (!_isMonitoring || !mounted) return;
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final hit = mag >= _gyroThreshold;
    setState(() {
      _gyroMag = mag;
      if (hit) _gyroAt = DateTime.now();
    });
    if (hit) _checkCrashWindow();
  }

  void _onPos(Position p) {
    if (!_isMonitoring || !mounted) return;
    final speed = (p.speed.isFinite ? p.speed : 0) * 3.6;
    final lat2 = _roundTo(p.latitude, 2);
    final lng2 = _roundTo(p.longitude, 2);
    setState(() {
      if (!_obdConnected || _obdSpeedKmh == null) {
        _speedKmh = speed;
      }
      _lat = p.latitude;
      _lng = p.longitude;
      if (_weatherCoords.lat != lat2 || _weatherCoords.lng != lng2) {
        _weatherCoords = (lat: lat2, lng: lng2);
      }
    });

    _checkSpeedDrop(speed, at: DateTime.now());
  }

  void _onObdTelemetry(ObdTelemetrySnapshot snapshot) {
    if (!mounted) {
      return;
    }
    setState(() {
      _obdConnected = snapshot.connected;
      _obdStatus = snapshot.status;
      _obdSpeedKmh = snapshot.speedKmh;
      _obdRpm = snapshot.rpm;
      if (snapshot.speedKmh != null) {
        _speedKmh = snapshot.speedKmh!;
      }
    });

    final speed = snapshot.speedKmh;
    if (_isMonitoring && speed != null) {
      _checkSpeedDrop(speed, at: snapshot.updatedAt ?? DateTime.now());
    }
  }

  Future<void> _reconnectObd() async {
    try {
      await _obdTelemetryService.initializeAndAutoConnect(forceReconnect: true);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Unable to connect OBD-II adapter.');
      }
    }
  }

  void _checkSpeedDrop(double speed, {required DateTime at}) {
    if (speed >= _highSpeedThreshold) {
      _lastHighSpeed = (speedKmh: speed, at: at);
      return;
    }
    final highSpeed = _lastHighSpeed;
    if (highSpeed == null) {
      return;
    }

    final elapsed = at.difference(highSpeed.at);
    if (elapsed > _speedDropWindow) {
      _lastHighSpeed = null;
      return;
    }

    if (speed <= _lowSpeedThreshold) {
      _lastHighSpeed = null;
      setState(() => _gpsAt = at);
      _checkCrashWindow();
    }
  }

  void _checkCrashWindow() {
    if (_pendingAlert || _dispatching) return;
    _pruneExpiredSignals();
    if (_lastCrashAt != null &&
        DateTime.now().difference(_lastCrashAt!) < _cooldown) {
      return;
    }
    final acc = _accAt;
    final gyro = _gyroAt;
    final gps = _gpsAt;
    if (acc == null || gyro == null || gps == null) return;
    final times = <DateTime>[acc, gyro, gps]..sort();
    if (times.last.difference(times.first) <= _triggerWindow) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _lastCrashAt = DateTime.now();
    _accAt = null;
    _gyroAt = null;
    _gpsAt = null;
    setState(() {
      _pendingAlert = true;
      _countdown = 10;
      _status = 'Possible crash detected. Countdown started.';
    });
    unawaited(_notifications.showCrashPrompt(seconds: _countdown));
    unawaited(_voiceAlert.speakCrashWarning(seconds: _countdown));
    _cancelTimer?.cancel();
    _cancelTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !_pendingAlert) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        unawaited(_confirmAlert());
        return;
      }
      setState(() => _countdown -= 1);
    });
  }

  void _cancelPendingAlert() {
    _cancelTimer?.cancel();
    setState(() {
      _pendingAlert = false;
      _countdown = 0;
      _status = 'Alert cancelled by user.';
    });
    unawaited(_voiceAlert.speakCancelled());
    showAppSnackBar(context, 'Alert cancelled.');
  }

  Future<void> _confirmAlert() async {
    if (!mounted || _dispatching) return;
    setState(() {
      _pendingAlert = false;
      _countdown = 0;
      _status = 'Sending emergency alert...';
    });
    await _dispatchAlert();
  }

  Future<void> _dispatchAlert() async {
    if (_dispatching) return;
    setState(() => _dispatching = true);
    try {
      if (_hasInvalidManualContactPhone()) {
        throw const EmergencyWorkflowException(
          'Fix invalid manual contact phone numbers before sending alert.',
        );
      }
      final coords = await _resolveAlertCoords();
      final manualContacts = _manualContactsFromInput();
      final result = await _alertService.dispatchEmergency(
        latitude: coords.latitude,
        longitude: coords.longitude,
        manualContacts: manualContacts,
      );
      if (!mounted) return;
      _lastAlertAt = DateTime.now();
      if (result.queued) {
        setState(() {
          _status = 'Offline: alert queued.';
          _lastAlert = 'Queued at ${_formatTime(_lastAlertAt!)}';
        });
        unawaited(_notifications.showAlertQueued());
        unawaited(_voiceAlert.speakQueued());
        showAppSnackBar(context, result.message ?? 'Alert queued for retry.');
        return;
      }
      final mode = result.dryRun ? 'dry-run' : 'live';
      final summary = 'Sent ${result.sent}, failed ${result.failed} ($mode)';
      final details = result.message;
      setState(() {
        _status = 'Emergency alert sent.';
        _lastAlert = '$summary at ${_formatTime(_lastAlertAt!)}';
      });
      if (result.sent > 0) {
        unawaited(_notifications.showAlertSent());
        unawaited(_voiceAlert.speakAlertSent());
      } else {
        unawaited(
          _voiceAlert.speakFailure(
            reason: details ?? 'No emergency contact could be reached.',
          ),
        );
      }
      showAppSnackBar(
        context,
        details == null || details.isEmpty ? summary : '$summary | $details',
      );
    } on EmergencyWorkflowException catch (e) {
      if (!mounted) return;
      _lastAlertAt = DateTime.now();
      setState(() {
        _status = 'Alert failed: ${e.message}';
        _lastAlert = 'Failed at ${_formatTime(_lastAlertAt!)}';
      });
      unawaited(_notifications.showAlertFailed());
      unawaited(_voiceAlert.speakFailure(reason: e.message));
      showAppSnackBar(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _lastAlertAt = DateTime.now();
      setState(() {
        _status = 'Alert failed unexpectedly.';
        _lastAlert = 'Failed at ${_formatTime(_lastAlertAt!)}';
      });
      unawaited(_notifications.showAlertFailed());
      unawaited(_voiceAlert.speakFailure());
      showAppSnackBar(context, 'Emergency alert failed unexpectedly.');
    } finally {
      if (mounted) setState(() => _dispatching = false);
    }
  }

  Future<void> _retryQueueNow() async {
    try {
      final delivered = await _alertService.flushQueuedAlerts();
      if (mounted) {
        showAppSnackBar(context, 'Queue retry delivered $delivered alerts.');
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Queue retry failed. Will retry automatically.',
        );
      }
    }
  }

  Future<int> _loadContactsCount() async {
    try {
      final repo = ref.read(emergencyContactsRepositoryProvider);
      final contacts = await repo.fetchContacts();
      return contacts.where((contact) {
        final phone = _normalizePhone(contact.phone ?? '');
        return phone.isNotEmpty && _isValidPhone(phone);
      }).length;
    } catch (_) {
      return 0;
    }
  }

  Future<({double latitude, double longitude})> _resolveAlertCoords() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return (latitude: _fallbackLat, longitude: _fallbackLng);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (latitude: _fallbackLat, longitude: _fallbackLng);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return (latitude: p.latitude, longitude: p.longitude);
    } catch (_) {
      return (latitude: _fallbackLat, longitude: _fallbackLng);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  List<EmergencyContact> _manualContactsFromInput() {
    final contacts = <EmergencyContact>[];

    for (final draft in _manualContactDrafts) {
      final rawPhone = draft.phoneController.text.trim();
      if (rawPhone.isEmpty || !_isValidPhone(rawPhone)) {
        continue;
      }

      final phone = _normalizePhone(rawPhone);
      final name = draft.nameController.text.trim().isEmpty
          ? 'Manual emergency contact'
          : draft.nameController.text.trim();

      contacts.add(EmergencyContact(name: name, phone: phone));
    }
    return contacts;
  }

  bool _hasInvalidManualContactPhone() => _manualContactDrafts.any((draft) {
    final rawPhone = draft.phoneController.text.trim();
    return rawPhone.isNotEmpty && !_isValidPhone(rawPhone);
  });

  String _normalizePhone(String phone) {
    final trimmed = phone.trim();
    final hasPlus = trimmed.startsWith('+');
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return '';
    }
    return hasPlus ? '+$digitsOnly' : digitsOnly;
  }

  bool _isValidPhone(String phone) =>
      RegExp(r'^\+?[0-9]{8,15}$').hasMatch(_normalizePhone(phone));

  bool _isTripleTriggered() =>
      _isSignalActive(_accAt) &&
      _isSignalActive(_gyroAt) &&
      _isSignalActive(_gpsAt);

  bool _isSignalActive(DateTime? timestamp) {
    if (timestamp == null) {
      return false;
    }
    return DateTime.now().difference(timestamp) <= _signalHoldWindow;
  }

  void _pruneExpiredSignals() {
    final now = DateTime.now();
    if (_accAt != null && now.difference(_accAt!) > _triggerWindow) {
      _accAt = null;
    }
    if (_gyroAt != null && now.difference(_gyroAt!) > _triggerWindow) {
      _gyroAt = null;
    }
    if (_gpsAt != null && now.difference(_gpsAt!) > _triggerWindow) {
      _gpsAt = null;
    }
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  double _roundTo(double v, int d) {
    final f = math.pow(10, d).toDouble();
    return (v * f).roundToDouble() / f;
  }

  Color _weatherColor(String caution) {
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

class _ManualContactDraft {
  _ManualContactDraft({required this.id})
    : nameController = TextEditingController(),
      phoneController = TextEditingController();

  final int id;
  final TextEditingController nameController;
  final TextEditingController phoneController;

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.width,
    required this.title,
    required this.status,
    required this.active,
  });

  final double width;
  final String title;
  final String status;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFC12020) : const Color(0xFF1B7F49);
    final icon = active ? Icons.error_outline : Icons.check_circle_outline;
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: RoadUi.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(top: 2),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: RoadUi.caution.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: RoadUi.caution),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: RoadUi.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: RoadUi.textMuted,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebOnlyCard extends StatelessWidget {
  const _WebOnlyCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(14),
      child: RoadPanel(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.phone_android_outlined, size: 48, color: RoadUi.caution),
            SizedBox(height: 12),
            Text(
              'Mobile Only Feature',
              style: TextStyle(
                color: RoadUi.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Guardian Monitor is available only on mobile devices.\nCrash detection needs accelerometer, gyroscope, and GPS.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: RoadUi.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
