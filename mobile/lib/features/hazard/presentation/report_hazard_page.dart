import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/app_snackbar.dart';
import '../../../core/ui/road_theme.dart';
import '../data/deepfake_verification_service.dart';
import '../data/media_upload_service.dart';
import '../../navigation/data/place_search_service.dart';

class ReportHazardPage extends ConsumerStatefulWidget {
  const ReportHazardPage({super.key});

  @override
  ConsumerState<ReportHazardPage> createState() => _ReportHazardPageState();
}

class _ReportHazardPageState extends ConsumerState<ReportHazardPage> {
  static const _severityLevels = <String>['low', 'medium', 'high', 'critical'];

  final _picker = ImagePicker();
  final _hazardTypeController = TextEditingController();
  final _locationController = TextEditingController();
  Timer? _locationDebounce;

  XFile? _selectedPhoto;
  XFile? _selectedVideo;
  List<PlaceSuggestion> _locationSuggestions = const <PlaceSuggestion>[];
  PlaceSuggestion? _selectedLocation;
  String _selectedSeverity = _severityLevels.first;
  bool _isUploading = false;
  bool _isSearchingLocation = false;
  double _progress = 0;
  String _uploadStatus = '';

  @override
  void dispose() {
    _locationDebounce?.cancel();
    _hazardTypeController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const RoadPanel(
          child: RoadSectionHeader(
            title: 'Report Hazard',
            icon: Icons.report_gmailerrorred_outlined,
          ),
        ),
        const SizedBox(height: 12),
        RoadPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _hazardTypeController,
                enabled: !_isUploading,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Hazard Type',
                  prefixIcon: Icon(Icons.warning_amber_rounded),
                  hintText: 'e.g. pothole, waterlogging, fallen tree',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedSeverity,
                decoration: const InputDecoration(
                  labelText: 'Severity',
                  prefixIcon: Icon(Icons.priority_high_rounded),
                ),
                items: _severityLevels
                    .map(
                      (level) => DropdownMenuItem<String>(
                        value: level,
                        child: Text(level),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isUploading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedSeverity = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                enabled: !_isUploading,
                onChanged: _onLocationQueryChanged,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.streetAddress,
                decoration: InputDecoration(
                  labelText: 'Location',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  hintText: 'Search and select location',
                  suffixIcon: IconButton(
                    tooltip: 'Use current GPS coordinates',
                    onPressed: _isUploading ? null : _fillLocationFromGps,
                    icon: const Icon(Icons.my_location_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_isSearchingLocation)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (_selectedLocation != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Selected: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    color: RoadUi.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_locationSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildLocationSuggestionCard(),
              ],
              const SizedBox(height: 8),
              const Text(
                'Tip: pick a suggestion for best accuracy, or type "lat,lng".',
                style: TextStyle(
                  color: RoadUi.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Photo Evidence',
                style: TextStyle(
                  color: RoadUi.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedPhoto != null) ...[
                FutureBuilder<Uint8List>(
                  future: _selectedPhoto!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        snapshot.data!,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ] else
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFFF2F5FB),
                    border: Border.all(color: const Color(0xFFDDE3EE)),
                  ),
                  child: const Center(
                    child: Text(
                      'No photo selected yet',
                      style: TextStyle(
                        color: RoadUi.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isUploading ? null : _pickPhotoFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose Photo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF27303D),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUploading ? null : _capturePhotoFromCamera,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Capture Photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2F3B4E),
                        side: const BorderSide(color: Color(0xFFD2DAE8)),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Video Evidence',
                style: TextStyle(
                  color: RoadUi.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Optional',
                style: TextStyle(
                  color: RoadUi.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFFF2F5FB),
                  border: Border.all(color: const Color(0xFFDDE3EE)),
                ),
                child: Center(
                  child: Text(
                    _selectedVideo == null
                        ? 'No video selected yet'
                        : 'Selected: ${_displayName(_selectedVideo!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: RoadUi.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isUploading ? null : _pickVideoFromGallery,
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Choose Video'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF27303D),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUploading ? null : _captureVideoFromCamera,
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Capture Video'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2F3B4E),
                        side: const BorderSide(color: Color(0xFFD2DAE8)),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isUploading) ...[
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  color: RoadUi.caution,
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload progress: ${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: RoadUi.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_uploadStatus.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _uploadStatus,
                    style: const TextStyle(
                      color: RoadUi.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: _isUploading ? null : _submitReport,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Submit Report'),
                style: FilledButton.styleFrom(
                  backgroundColor: RoadUi.caution,
                  foregroundColor: const Color(0xFF1D1A0C),
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickPhotoFromGallery() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (photo == null) {
        return;
      }
      setState(() => _selectedPhoto = photo);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Unable to pick photo from gallery.');
    }
  }

  Future<void> _capturePhotoFromCamera() async {
    if (kIsWeb) {
      showAppSnackBar(
        context,
        'Camera capture is mobile only. Use file upload.',
      );
      return;
    }

    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null) {
        return;
      }
      setState(() => _selectedPhoto = photo);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Unable to open camera for photo capture.');
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (video == null) {
        return;
      }
      setState(() => _selectedVideo = video);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Unable to pick video from gallery.');
    }
  }

  Future<void> _captureVideoFromCamera() async {
    if (kIsWeb) {
      showAppSnackBar(
        context,
        'Video capture is mobile only. Use file upload.',
      );
      return;
    }

    try {
      final video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30),
      );
      if (video == null) {
        return;
      }
      setState(() => _selectedVideo = video);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Unable to open camera for video capture.');
    }
  }

  Future<void> _fillLocationFromGps() async {
    final geoPoint = await _tryResolveLocation();
    if (geoPoint == null) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Could not read GPS right now. Enter location manually.',
        );
      }
      return;
    }

    _locationController.text =
        '${geoPoint.latitude.toStringAsFixed(6)},'
        '${geoPoint.longitude.toStringAsFixed(6)}';
    setState(() {
      _selectedLocation = null;
      _locationSuggestions = const <PlaceSuggestion>[];
      _isSearchingLocation = false;
    });
    if (mounted) {
      showAppSnackBar(context, 'Location filled from current GPS.');
    }
  }

  Future<void> _submitReport() async {
    final photo = _selectedPhoto;
    final video = _selectedVideo;
    final selectedLocation = _selectedLocation;
    final user = FirebaseAuth.instance.currentUser;
    final hazardTypeText = _hazardTypeController.text.trim();
    final locationText = _locationController.text.trim();

    if (photo == null) {
      showAppSnackBar(context, 'Select a photo first.');
      return;
    }
    if (locationText.isEmpty) {
      showAppSnackBar(context, 'Enter location before submitting.');
      return;
    }
    if (hazardTypeText.isEmpty) {
      showAppSnackBar(context, 'Enter hazard type before submitting.');
      return;
    }
    if (user == null) {
      showAppSnackBar(context, 'Please sign in before reporting a hazard.');
      return;
    }

    setState(() {
      _isUploading = true;
      _progress = 0;
      _uploadStatus = 'Preparing media...';
    });

    try {
      final photoBytes = await photo.readAsBytes();
      final videoFile = video;
      final videoBytes = videoFile == null ? null : await videoFile.readAsBytes();

      _setUploadStatus('Running deepfake verification...');
      final verificationService = ref.read(deepfakeVerificationServiceProvider);
      final verification = (videoBytes == null || videoFile == null)
          ? await verificationService.verifyImage(
              imageBytes: photoBytes,
              imageFileName: _displayName(photo),
              hazardType: hazardTypeText,
              severity: _selectedSeverity,
              locationText: locationText,
            )
          : await verificationService.verifyMedia(
              photoBytes: photoBytes,
              photoFileName: _displayName(photo),
              videoBytes: videoBytes,
              videoFileName: _displayName(videoFile),
              hazardType: hazardTypeText,
              severity: _selectedSeverity,
              locationText: locationText,
            );

      if (!verification.isAuthentic) {
        if (mounted) {
          showAppSnackBar(
            context,
            'Deepfake detected in uploaded image/video (${verification.verdict}). Report blocked.',
          );
        }
        return;
      }

      final location = await _resolveLocationFromInput(
        locationText,
        selected: selectedLocation,
      );
      final firestore = FirebaseFirestore.instance;
      final reportId = firestore.collection('hazard_reports').doc().id;
      final mediaUploadService = ref.read(mediaUploadServiceProvider);

      _setUploadStatus('Uploading photo evidence...');
      final photoUrl = await mediaUploadService.uploadImage(
        bytes: photoBytes,
        fileName: _displayName(photo),
        publicId: '$reportId-photo',
        onProgress: (progress) {
          _setCombinedProgress(
            progressStart: 0,
            progressWeight: videoBytes == null ? 1 : 0.5,
            partProgress: progress,
          );
        },
      );

      String? videoUrl;
      if (videoBytes != null && videoFile != null) {
        _setUploadStatus('Uploading video evidence...');
        videoUrl = await mediaUploadService.uploadVideo(
          bytes: videoBytes,
          fileName: _displayName(videoFile),
          publicId: '$reportId-video',
          onProgress: (progress) {
            _setCombinedProgress(
              progressStart: 0.5,
              progressWeight: 0.5,
              partProgress: progress,
            );
          },
        );
      }

      _setUploadStatus('Saving report...');
      final payload = <String, dynamic>{
        'uid': user.uid,
        'location': location,
        'location_text': locationText,
        'hazard_type': hazardTypeText,
        'severity': _selectedSeverity,
        'confidence': verification.confidence,
        'image_url': photoUrl,
        'photo_url': photoUrl,
        'deepfake_verified': true,
        'deepfake_is_authentic': verification.isAuthentic,
        'deepfake_confidence': verification.confidence,
        'deepfake_verdict': verification.verdict,
        'deepfake_response': _sanitizeForFirestore(verification.raw),
        'status': 'verified',
        'expires_at': Timestamp.fromDate(
          DateTime.now().toUtc().add(const Duration(days: 14)),
        ),
        'created_at': FieldValue.serverTimestamp(),
      };
      if (videoUrl != null && videoUrl.trim().isNotEmpty) {
        payload['video_url'] = videoUrl;
      }
      await firestore.collection('hazard_reports').doc(reportId).set(payload);

      if (!mounted) {
        return;
      }

      showAppSnackBar(context, 'Hazard submitted and verified successfully.');
      setState(() {
        _selectedPhoto = null;
        _selectedVideo = null;
        _hazardTypeController.clear();
        _locationController.clear();
        _locationSuggestions = const <PlaceSuggestion>[];
        _selectedLocation = null;
        _isSearchingLocation = false;
        _progress = 0;
        _uploadStatus = '';
      });
    } on DeepfakeVerificationException catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, error.message);
    } on MediaUploadException catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, error.message);
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'permission-denied') {
        showAppSnackBar(
          context,
          'Permission denied while saving report. Check Firestore rules.',
        );
      } else if (error.code == 'unavailable') {
        showAppSnackBar(
          context,
          'Firestore is unavailable right now. Try again shortly.',
        );
      } else {
        showAppSnackBar(context, 'Could not save report (${error.code}).');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'Could not submit report. Check media, internet, and GPS.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
      }
    }
  }

  void _onLocationQueryChanged(String value) {
    if (_selectedLocation != null &&
        value.trim() != _selectedLocation!.displayName) {
      _selectedLocation = null;
    }

    _locationDebounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.length < 3) {
      setState(() {
        _isSearchingLocation = false;
        _locationSuggestions = const <PlaceSuggestion>[];
      });
      return;
    }

    setState(() => _isSearchingLocation = true);
    _locationDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref
          .read(placeSearchServiceProvider)
          .searchPlaces(trimmed);
      if (!mounted) {
        return;
      }
      if (_locationController.text.trim() != trimmed) {
        return;
      }
      setState(() {
        _isSearchingLocation = false;
        _locationSuggestions = results;
      });
    });
  }

  void _selectLocation(PlaceSuggestion place) {
    setState(() {
      _selectedLocation = place;
      _locationController.text = place.displayName;
      _locationSuggestions = const <PlaceSuggestion>[];
      _isSearchingLocation = false;
    });
    _locationController.selection = TextSelection.collapsed(
      offset: _locationController.text.length,
    );
  }

  Widget _buildLocationSuggestionCard() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD2DAE8)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _locationSuggestions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final place = _locationSuggestions[index];
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
            subtitle: Text(
              '${place.latitude.toStringAsFixed(5)}, ${place.longitude.toStringAsFixed(5)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RoadUi.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
            onTap: () => _selectLocation(place),
          );
        },
      ),
    );
  }

  Future<GeoPoint> _resolveLocationFromInput(
    String raw, {
    required PlaceSuggestion? selected,
  }) async {
    final typed = raw.trim();
    if (selected != null && typed == selected.displayName.trim()) {
      return GeoPoint(selected.latitude, selected.longitude);
    }

    final parsed = _parseLocationFromText(typed);
    if (parsed != null) {
      return parsed;
    }

    final geocoded = await _tryGeocodeLocation(typed);
    if (geocoded != null) {
      return geocoded;
    }
    return _resolveLocation();
  }

  Future<GeoPoint?> _tryGeocodeLocation(String raw) async {
    final query = raw.trim();
    if (query.length < 3) {
      return null;
    }

    final results = await ref.read(placeSearchServiceProvider).searchPlaces(
      query,
    );
    if (results.isEmpty) {
      return null;
    }
    final first = results.first;
    return GeoPoint(first.latitude, first.longitude);
  }

  void _setCombinedProgress({
    required double progressStart,
    required double progressWeight,
    required double partProgress,
  }) {
    if (!mounted) {
      return;
    }

    final normalizedPart = partProgress.clamp(0, 1).toDouble();
    final combined = progressStart + (normalizedPart * progressWeight);
    setState(() => _progress = combined.clamp(0, 1).toDouble());
  }

  void _setUploadStatus(String status) {
    if (!mounted) {
      return;
    }
    setState(() => _uploadStatus = status);
  }

  Object? _sanitizeForFirestore(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) {
      return value
          .map<Object?>((item) => _sanitizeForFirestore(item))
          .toList(growable: false);
    }
    if (value is Map) {
      return value.map<String, Object?>((key, item) {
        return MapEntry<String, Object?>(
          key.toString(),
          _sanitizeForFirestore(item),
        );
      });
    }
    return value.toString();
  }

  GeoPoint? _parseLocationFromText(String raw) {
    final matcher = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(raw);
    if (matcher == null) {
      return null;
    }

    final latitude = double.tryParse(matcher.group(1) ?? '');
    final longitude = double.tryParse(matcher.group(2) ?? '');
    if (latitude == null || longitude == null) {
      return null;
    }
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return GeoPoint(latitude, longitude);
  }

  String _displayName(XFile file) {
    final name = file.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final normalizedPath = file.path.replaceAll('\\', '/');
    final parts = normalizedPath.split('/');
    return parts.isEmpty ? 'media_file' : parts.last;
  }

  Future<GeoPoint?> _tryResolveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return GeoPoint(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<GeoPoint> _resolveLocation() async {
    const fallback = GeoPoint(12.9716, 77.5946);
    final resolved = await _tryResolveLocation();
    return resolved ?? fallback;
  }
}
