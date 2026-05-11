// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:nigerian_states_and_lga/nigerian_states_and_lga.dart';
import 'package:card_app/ui/permission_explanation_sheet.dart';

class UpgradeTier extends StatefulWidget {
  final int tier;
  const UpgradeTier({super.key, required this.tier});

  @override
  State<UpgradeTier> createState() => _UpgradeTierState();
}

class _UpgradeTierState extends State<UpgradeTier>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController ninController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  // Add these to your state fields:
  AnimationController? _progressController;
  final ValueNotifier<String> _loadingStatusNotifier = ValueNotifier(
    'Preparing your details...',
  );
  bool _bvnVerifying = false;
  bool? _bvnVerified;
  String? _bvnVerifyStatus;
  Map<String, bool>? _bvnFieldMatches;
  Timer? _bvnVerifyTimer;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  List<String> states = [];
  String? selectedState;
  List<String> cities = [];
  String? selectedCity;
  String? selectedGender;
  String? selectedIdType;
  bool _isLoading = false;
  bool _loadingDialogShowing = false;
  bool _isGettingLocation = false;
  final ValueNotifier<int> _loadingStepNotifier = ValueNotifier(0);
  File? _selfieFile;
  String? _selfieUrl;
  bool _isUploadingSelfie = false;
  StreamSubscription<DocumentSnapshot>? _userDocSub;
  bool _bvnFromQore = false;
  bool _bvnConflict = false;
  Timer? _bvnCheckTimer;
  Timer? _draftSaveTimer;
  String? _lastQueriedBvn;
  bool _externalBvnMatch = false;

  // ── Cached data for performance ─────────────────────────────────────────
  Map<String, dynamic>? _cachedUserDoc;
  Map<String, dynamic>? _cachedSafehavenSetup;

  bool get _isIdentityVerificationStep => widget.tier == 1;

  String get _screenTitle => _isIdentityVerificationStep
      ? 'Verify Your Identity'
      : 'Complete Your Profile';

  String get _screenSubtitle => _isIdentityVerificationStep
      ? 'Confirm your BVN details, verify the OTP sent to your phone, and activate your wallet.'
      : 'Add a valid government ID to complete your profile details.';

  String get _primaryButtonText => _isIdentityVerificationStep
      ? 'Verify and Continue'
      : 'Verify and Upgrade';

  void _showLoadingDialog({bool resetStep = false}) {
    if (_loadingDialogShowing || !mounted) return;
    _loadingDialogShowing = true;
    _loadingStatusNotifier.value = 'Preparing your details...';

    // Dispose any existing controller AND clear the reference
    _progressController?.dispose();
    _progressController = null; // ⬅️ CRITICAL

    // Create a fresh controller
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..animateTo(0.88, curve: Curves.easeOut);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Verifying your account',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _progressController!,
                  builder: (context, _) {
                    final pct = (_progressController!.value * 100).round();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progressController!.value,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ValueListenableBuilder<String>(
                              valueListenable: _loadingStatusNotifier,
                              builder: (_, status, __) => Text(
                                status,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            Text(
                              '$pct%',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => _loadingDialogShowing = false);
  }

  void _forceHideLoadingDialog() {
    if (!mounted) return;
    // Just check null – if it's null, it's either never created or already disposed
    if (_progressController == null) return;
    _progressController!.stop();
    if (!_loadingDialogShowing) return;
    _loadingDialogShowing = false;
    if (!mounted) return;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}
  }

  Future<void> _forceHideAndShowError({
    required String errorMessage,
    required String errorType,
    StackTrace? stackTrace,
  }) async {
    _forceHideLoadingDialog();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    showGenericError(
      errorMessage: errorMessage,
      errorType: errorType,
      stackTrace: stackTrace,
    );
  }

  void _hideLoadingDialogImmediate() {
    if (!mounted) return;
    if (!_loadingDialogShowing) return;
    if (_progressController != null) {
      _progressController!.stop();
    }
    _loadingDialogShowing = false;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}
  }

  Future<void> _hideLoadingDialog() async {
    if (!mounted) return;
    if (!_loadingDialogShowing) return;
    _loadingDialogShowing = false;

    if (_progressController != null) {
      // Animate to 100% and wait for the pop to finish
      await _progressController!
          .animateTo(1.0, duration: const Duration(milliseconds: 400))
          .then((_) {
            if (!mounted) return;
            Navigator.of(context, rootNavigator: true).pop();
          });
    } else {
      // No animation, just pop
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
    }
  }

  // Helper to update loading message and progress
  void _setLoadingMessage(String message, {double targetProgress = 0.0}) {
    _loadingStatusNotifier.value = message;
    if (targetProgress > 0 &&
        _progressController != null &&
        _progressController!.value < targetProgress) {
      _progressController!.animateTo(
        targetProgress,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchStates();
    _listenForIdNumber();
    _checkInitialBvnConflict();
    _prefetchUserDataAndSetup();
  }

  Future<void> _prefetchUserDataAndSetup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        _cachedUserDoc = userDoc.data();
      }
      final setupDoc = await FirebaseFirestore.instance
          .collection('safehavenUserSetup')
          .doc(user.uid)
          .get();
      if (setupDoc.exists) {
        _cachedSafehavenSetup = setupDoc.data();
      }
      // Pre‑populate fields from cached data
      _populateFieldsFromDoc(_cachedUserDoc);
    } catch (e) {
      debugPrint('Error pre-fetching user data: $e');
    }
  }

  Future<void> _fetchStates() async {
    setState(() {
      states = NigerianStatesAndLGA.allStates;
    });
  }

  Future<void> _fetchCities(String state) async {
    setState(() {
      cities = NigerianStatesAndLGA.getStateLGAs(state);
      selectedCity = null;
    });
  }

  void _scheduleDraftAutosave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 700), _autosaveDraft);
  }

  Future<void> _autosaveDraft() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final Map<String, dynamic> updateData = {};

    if (widget.tier == 1 || widget.tier == 2) {
      final bvn = _controller.text.trim();
      if (bvn.isNotEmpty) updateData['bvn'] = bvn;

      final fn = _firstNameController.text.trim();
      final ln = _lastNameController.text.trim();
      if (fn.isNotEmpty) updateData['firstName'] = fn;
      if (ln.isNotEmpty) updateData['lastName'] = ln;

      final dob = _dobController.text.trim();
      if (dob.isNotEmpty) updateData['dateOfBirth'] = _formatDateForApi(dob);

      if (selectedGender != null && selectedGender!.isNotEmpty) {
        updateData['gender'] = selectedGender;
      }

      final street = _streetController.text.trim();
      if (street.isNotEmpty) updateData['address.street'] = street;
      if (selectedCity != null && selectedCity!.isNotEmpty) {
        updateData['address.city'] = selectedCity;
      }
      if (selectedState != null && selectedState!.isNotEmpty) {
        updateData['address.state'] = selectedState;
      }
      if (updateData.containsKey('address.street') ||
          updateData.containsKey('address.city') ||
          updateData.containsKey('address.state')) {
        updateData['address.country'] = 'NG';
      }
      if (_selfieUrl != null && _selfieUrl!.isNotEmpty) {
        updateData['kyc.selfieUrl'] = _selfieUrl;
      }
    } else {
      final nin = ninController.text.trim();
      if (nin.isNotEmpty) updateData['nin'] = nin;
      if (selectedIdType != null && selectedIdType!.isNotEmpty) {
        updateData['idType'] = selectedIdType;
      }
      final idNum = _idNumberController.text.trim();
      if (idNum.isNotEmpty) updateData['idNumber'] = idNum;
      final expiry = _expiryController.text.trim();
      if (expiry.isNotEmpty) {
        updateData['expiryDate'] = _formatDateForApi(expiry);
      }
    }

    if (updateData.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));
    } catch (e) {
      print('Draft autosave failed: $e');
    }
  }

  Future<void> _showSuccessModal() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE6F4EA),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF34A853),
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Account Upgraded!',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'You can now fully enjoy all Padi Pay features including higher transfer limits, bill payments, and much more.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      navigateTo(context, HomePage());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Go to Dashboard',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    if (_isGettingLocation) return;

    // Check if location permission is already granted
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      // Already granted, proceed directly
      await _handleGetLocation();
      return;
    }

    // Show explanation bottom sheet before requesting location permission
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      builder: (context) => PermissionExplanationSheet(
        type: PermissionType.location,
        onContinue: () async {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse) {
            await _handleGetLocation();
          } else if (permission == LocationPermission.denied) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied')),
            );
          } else if (permission == LocationPermission.deniedForever) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are permanently denied'),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _verifyBvn() async {
    final bvn = _controller.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (bvn.length != 11 || firstName.isEmpty || lastName.isEmpty) return;

    // Block verification if user is under 18
    if (_isUnder18() == true) {
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = 'You must be 18 or older to verify your BVN';
      });
      return;
    }

    setState(() {
      _bvnVerifying = true;
      _bvnVerified = null;
      _bvnVerifyStatus = null;
      _bvnFieldMatches = null;
    });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyBvnNoFace')
          .call({'bvn': bvn, 'firstName': firstName, 'lastName': lastName});
      print('verifyBvnNoFace Response: ${result.data}');

      final resData = result.data as Map<String, dynamic>;
      bool isVerified = resData['verified'] as bool? ?? false;
      String? verifyStatus = resData['status']?.toString();

      // Compute per-field match results BEFORE setting verified state
      final fm = Map<String, dynamic>.from(
        resData['fieldMatches'] as Map? ?? {},
      );
      final rawBd = resData['bvnData'];
      final bvnDobRaw = rawBd != null
          ? (rawBd as Map)['birthdate']?.toString()
          : null;
      // BVN API returns YYYY-MM-DD; controller holds DD-MM-YYYY  convert for comparison
      final bvnDobDisplay = (bvnDobRaw != null && bvnDobRaw.isNotEmpty)
          ? _formatDateFromApi(bvnDobRaw)
          : null;
      final bvnGender = rawBd != null
          ? (rawBd as Map)['gender']?.toString()
          : null;
      final enteredDob = _dobController.text.trim();
      final enteredGender = selectedGender;
      final fieldMatches = {
        'firstname': fm['firstname'] as bool? ?? false,
        'lastname': fm['lastname'] as bool? ?? false,
        'birthdate': enteredDob.isEmpty || (bvnDobDisplay ?? '').isEmpty
            ? true
            : enteredDob == bvnDobDisplay,
        'gender': (enteredGender ?? '').isEmpty || (bvnGender ?? '').isEmpty
            ? true
            : enteredGender!.toLowerCase() == bvnGender!.toLowerCase(),
      };
      // If any field doesn't match, override verified to false
      final anyMismatch = fieldMatches.values.any((v) => v == false);
      if (anyMismatch) {
        isVerified = false;
        verifyStatus = 'NO_MATCH';
      }

      setState(() {
        _bvnVerified = isVerified;
        _bvnVerifyStatus = verifyStatus;
        _bvnFieldMatches = fieldMatches;
      });

      // Save all BVN data returned by the function to Firestore
      final rawBvnData = resData['bvnData'];
      if (rawBvnData != null) {
        final bvnData = Map<String, dynamic>.from(rawBvnData as Map);
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final Map<String, dynamic> updates = {};

          // Persist each BVN field individually to avoid overwriting verifiedAt
          bvnData.forEach((key, value) {
            if (value != null) {
              updates['qoreIdData.bvnVerificationNoFace.$key'] = value;
            }
          });
          // Also save root-level fields used by _populateFieldsFromDoc
          // Always save current DOB (user may have edited it); fall back to BVN data
          final currentDob = _dobController.text.trim();
          if (currentDob.isNotEmpty) {
            updates['dateOfBirth'] = _formatDateForApi(currentDob);
          } else if ((bvnData['birthdate'] ?? '').toString().isNotEmpty) {
            updates['dateOfBirth'] = bvnData['birthdate'];
          }
          // Only save BVN gender if the user hasn't selected one yet
          if ((bvnData['gender'] ?? '').toString().isNotEmpty &&
              selectedGender == null) {
            updates['gender'] = bvnData['gender'];
          }
          if ((bvnData['phone'] ?? '').toString().isNotEmpty) {
            updates['phone'] = bvnData['phone'];
          }
          // Always save the current first/last name (user may have edited them)
          final currentFn = _firstNameController.text.trim();
          final currentLn = _lastNameController.text.trim();
          if (currentFn.isNotEmpty) updates['firstName'] = currentFn;
          if (currentLn.isNotEmpty) updates['lastName'] = currentLn;

          // Fall back to BVN-returned names only if fields are still empty
          if (currentFn.isEmpty &&
              (bvnData['firstname'] ?? '').toString().isNotEmpty) {
            updates['firstName'] = _toTitleCase(
              bvnData['firstname'].toString(),
            );
          }
          if (currentLn.isEmpty &&
              (bvnData['lastname'] ?? '').toString().isNotEmpty) {
            updates['lastName'] = _toTitleCase(bvnData['lastname'].toString());
          }

          // Always persist our locally-computed verified result so the
          // Firestore listener never restores a stale verified:true.
          updates['qoreIdData.bvnVerificationNoFace.verified'] = isVerified;
          updates['qoreIdData.bvnVerificationNoFace.status'] = verifyStatus;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update(updates);
        }

        // Update local state with BVN data
        if (mounted) {
          setState(() {
            final dob = bvnData['birthdate']?.toString();
            if (dob != null && dob.isNotEmpty && _dobController.text.isEmpty) {
              _dobController.text = _formatDateFromApi(dob);
            }
            final gender = bvnData['gender']?.toString();
            if (gender != null && gender.isNotEmpty && selectedGender == null) {
              selectedGender = gender;
            }
            final fn = bvnData['firstname']?.toString();
            if (fn != null &&
                fn.isNotEmpty &&
                _firstNameController.text.isEmpty) {
              _firstNameController.text = _toTitleCase(fn);
            }
            final ln = bvnData['lastname']?.toString();
            if (ln != null &&
                ln.isNotEmpty &&
                _lastNameController.text.isEmpty) {
              _lastNameController.text = _toTitleCase(ln);
            }
          });
        }
      }
    } on FirebaseFunctionsException catch (e) {
      final raw = e.message ?? '';
      final userMsg =
          raw.toLowerCase().contains('404') ||
              raw.toLowerCase().contains('not found')
          ? 'BVN not found'
          : raw.isNotEmpty
          ? raw
          : 'Verification failed please try again';
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = userMsg;
      });
      print('BVN verification error: $e');
    } catch (e) {
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = 'Verification failed  please try again';
      });
      print('BVN verification error: $e');
    } finally {
      setState(() => _bvnVerifying = false);
    }
  }

  void _listenForIdNumber() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data() ?? <String, dynamic>{};
          final qore = data['qoreIdData'] as Map<String, dynamic>?;
          final verification = qore?['verification'] as Map<String, dynamic>?;
          final metadata = verification?['metadata'] as Map<String, dynamic>?;
          final bvnVerif =
              qore?['bvnVerificationNoFace'] as Map<String, dynamic>?;
          final bvnFromVerification = bvnVerif?['bvn']?.toString();
          final idNumber = metadata?['idNumber']?.toString();
          final prefilledBvn =
              (bvnFromVerification != null && bvnFromVerification.isNotEmpty)
              ? bvnFromVerification
              : idNumber;
          if (!mounted) return;
          setState(() {
            if (prefilledBvn != null && prefilledBvn.isNotEmpty) {
              _controller.text = prefilledBvn;
              _bvnFromQore = true;
            } else {
              _bvnFromQore = false;
            }
          });
          // Restore persisted BVN verification only on initial load
          // (i.e. _bvnVerified == null means we haven't run verification yet).
          // Once the user has attempted verification locally, don't let
          // Firestore snapshots override the result.
          if (_bvnVerified == null &&
              bvnVerif != null &&
              bvnVerif['verified'] == true) {
            _bvnVerified = true;
            _bvnVerifyStatus = bvnVerif['status']?.toString();
          }

          // Pre-fill name controllers from user doc
          final docFn = data['firstName']?.toString() ?? '';
          final docLn = data['lastName']?.toString() ?? '';
          if (_firstNameController.text.isEmpty && docFn.isNotEmpty) {
            _firstNameController.text = docFn;
          }
          if (_lastNameController.text.isEmpty && docLn.isNotEmpty) {
            _lastNameController.text = docLn;
          }

          // Populate other fields from the user document if available
          _populateFieldsFromDoc(data);

          // trigger a BVN conflict check for any prefilled BVN
          if (prefilledBvn != null && prefilledBvn.isNotEmpty) {
            _checkBvnConflict(prefilledBvn);
          } else {
            _checkBvnConflict('');
          }
        });
  }

  Future<void> _handleGetLocation() async {
    setState(() {
      _isGettingLocation = true;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        final street =
            (place.street ?? '').toLowerCase().contains('unnamed road')
            ? ''
            : (place.street ?? '');

        setState(() {
          _streetController.text = "$street, ${place.subLocality ?? ''}"
              .trim()
              .trimLeft()
              .trimRight()
              .replaceAll(RegExp(r'^,|,$'), '');

          selectedState = _getStateFromName(place.administrativeArea ?? '');
          selectedCity = place.locality ?? place.subLocality;
        });

        if (selectedState != null) {
          await _fetchCities(selectedState!);
          if (cities.contains(selectedCity)) {
            selectedCity = selectedCity;
          } else {
            selectedCity = cities.isNotEmpty ? cities.first : null;
          }
        }

        _scheduleDraftAutosave();
      }
    } catch (e) {
      print('Error getting location: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  String? _getStateFromName(String stateName) {
    List<String> stateNames = [
      'Abia',
      'Adamawa',
      'Akwa Ibom',
      'Anambra',
      'Bauchi',
      'Bayelsa',
      'Benue',
      'Borno',
      'Cross River',
      'Delta',
      'Ebonyi',
      'Edo',
      'Ekiti',
      'Enugu',
      'FCT',
      'Gombe',
      'Imo',
      'Jigawa',
      'Kaduna',
      'Kano',
      'Katsina',
      'Kebbi',
      'Kogi',
      'Kwara',
      'Lagos',
      'Nasarawa',
      'Niger',
      'Ogun',
      'Ondo',
      'Osun',
      'Oyo',
      'Plateau',
      'Rivers',
      'Sokoto',
      'Taraba',
      'Yobe',
      'Zamfara',
    ];

    for (String state in stateNames) {
      if (stateName.toLowerCase().contains(state.toLowerCase()) ||
          state.toLowerCase().contains(stateName.toLowerCase())) {
        return state;
      }
    }
    return null;
  }

  Widget _buildLocationIcon() {
    if (_isGettingLocation) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _isGettingLocation ? null : _getCurrentLocation,
      child: Container(
        padding: EdgeInsets.all(12),
        child: FaIcon(
          FontAwesomeIcons.locationArrow,
          color: _isGettingLocation ? Colors.grey.shade400 : primaryColor,
          size: 20,
        ),
      ),
    );
  }

  Color _bvnBorderColor() {
    if (_bvnVerified == true) return Colors.green;
    if (_bvnVerified == false) return Colors.red.shade300;
    if (_bvnConflict && !_externalBvnMatch) return Colors.red;
    return Colors.grey.shade200;
  }

  Color _bvnFocusedBorderColor() {
    if (_bvnVerified == true) return Colors.green;
    if (_bvnVerified == false) return Colors.red;
    if (_bvnConflict && !_externalBvnMatch) return Colors.red;
    return primaryColor;
  }

  Future<String?> _showSearchableSelectionBottomSheet({
    required String title,
    required List<String> items,
    String? selectedValue,
  }) async {
    if (items.isEmpty) return null;
    String searchQuery = '';

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          bottom: true,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final filteredItems = items
                  .where(
                    (item) =>
                        item.toLowerCase().contains(searchQuery.toLowerCase()),
                  )
                  .toList();

              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        onChanged: (value) {
                          setModalState(() {
                            searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Text(
                                'No results found',
                                style: GoogleFonts.inter(color: Colors.grey.shade500),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredItems.length,
                              padding: const EdgeInsets.all(16),
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final isSelected = selectedValue == item;
                                return GestureDetector(
                                  onTap: () => Navigator.pop(context, item),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? primaryColor
                                            : Colors.grey.shade300,
                                        width: isSelected ? 2 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item,
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: isSelected
                                                  ? primaryColor
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(
                                            Icons.check_circle,
                                            color: primaryColor,
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openStateSelector() async {
    final selected = await _showSearchableSelectionBottomSheet(
      title: 'Select State',
      items: states,
      selectedValue: selectedState,
    );
    if (selected == null || selected == selectedState) return;

    setState(() {
      selectedState = selected;
      selectedCity = null;
    });
    await _fetchCities(selected);
    _scheduleDraftAutosave();
  }

  Future<void> _openCitySelector() async {
    if (selectedState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a state first')),
      );
      return;
    }
    final selected = await _showSearchableSelectionBottomSheet(
      title: 'Select City / LGA',
      items: cities,
      selectedValue: selectedCity,
    );
    if (selected == null) return;
    setState(() => selectedCity = selected);
    _scheduleDraftAutosave();
  }

  Future<void> _pickSelfie() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked != null) {
      setState(() {
        _selfieFile = File(picked.path);
        _selfieUrl = null; // reset so it re-uploads
      });
      await _autosaveSelfieDraft();
    }
  }

  Future<void> _autosaveSelfieDraft() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _selfieFile == null || _isUploadingSelfie) return;

    try {
      final url = await _uploadSelfie(uid);
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'kyc.selfieUrl': url,
      }, SetOptions(merge: true));
      _scheduleDraftAutosave();
    } catch (e) {
      print('Selfie draft autosave failed: $e');
    }
  }

  Future<String> _uploadSelfie(String uid) async {
    if (_selfieFile == null) throw Exception('No selfie selected');
    setState(() => _isUploadingSelfie = true);
    try {
      final ref = FirebaseStorage.instance.ref().child(
        'kyc_selfies/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ref.putFile(_selfieFile!);
      final url = await ref.getDownloadURL();
      setState(() => _selfieUrl = url);
      return url;
    } finally {
      setState(() => _isUploadingSelfie = false);
    }
  }

  // -------------------------------------------------------------------------
  //  SUBMIT METHOD (OPTIMIZED)
  // -------------------------------------------------------------------------

  Future<void> _submit() async {
    setState(() { _isLoading = true; });
    _showLoadingDialog(resetStep: true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _forceHideAndShowError(errorMessage: 'No user logged in', errorType: 'UpgradeTier_NoUser');
      setState(() { _isLoading = false; });
      return;
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

    try {
      // Use cached user doc if already loaded, otherwise fetch fresh
      Map<String, dynamic>? userData = _cachedUserDoc;
      if (userData == null) {
        final snap = await docRef.get();
        if (!snap.exists) throw Exception('User document not found');
        userData = snap.data();
      }

      if (widget.tier == 1 || widget.tier == 2) {
        // Extract required fields from userData or controllers
        String? firstName = (userData?['firstName']?.toString() ?? '').isNotEmpty
            ? userData!['firstName'].toString()
            : _firstNameController.text.trim().isNotEmpty
                ? _firstNameController.text.trim()
                : null;
        String? lastName = (userData?['lastName']?.toString() ?? '').isNotEmpty
            ? userData!['lastName'].toString()
            : _lastNameController.text.trim().isNotEmpty
                ? _lastNameController.text.trim()
                : null;
        String? email = userData?['email']?.toString();
        String? phoneNumber = userData?['phone']?.toString().replaceFirst('+234', '');

        if (firstName == null || firstName.isEmpty) throw Exception('First name missing');
        if (lastName == null || lastName.isEmpty) throw Exception('Last name missing');
        if (email == null || email.isEmpty) throw Exception('Email missing');
        if (phoneNumber == null || phoneNumber.isEmpty) throw Exception('Phone number missing');

        // Normalise phone
        phoneNumber = phoneNumber.trim();
        if (phoneNumber.length == 10 && RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
          phoneNumber = '0$phoneNumber';
        }
        if (!RegExp(r'^0\d{10}$').hasMatch(phoneNumber)) {
          throw Exception('Invalid phone number format: $phoneNumber');
        }
        final phoneNumberForCreate = phoneNumber;

        // Validate age
        final parts = _dobController.text.split('-');
        final birthDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        final age = DateTime.now().difference(birthDate).inDays ~/ 365;
        if (age < 18) throw Exception('User must be at least 18 years old');

        // Save basic data to Firestore
        final updateData = {
          'bvn': _controller.text,
          'dateOfBirth': _formatDateForApi(_dobController.text),
          'gender': selectedGender!,
          'address': {
            'street': _streetController.text,
            'city': selectedCity!,
            'state': selectedState!,
            'country': 'NG',
            'postalCode': Random().nextInt(900000) + 100000,
          },
        };
        await docRef.update(updateData);

        // 1. Check if we already have a customer ID
        String? customerId = userData?['safehavenData']?['customerCreation']?['data']?['id']?.toString();
        final String? savedCustomerStatus = userData?['safehavenData']?['customerCreation']?['data']?['attributes']?['status']?.toString().toUpperCase();
        if (customerId != null && customerId.isNotEmpty &&
            (savedCustomerStatus == 'DELETED' || savedCustomerStatus == 'INACTIVE')) {
          customerId = null;
        }

        // 2. If no customer, try to match via BVN conflict resolution (already handled)
        //    but for performance we skip creating a customer – SafeHaven subaccount uses profile data directly.

        // 3. Check if identity verification has already been performed
        final functions = FirebaseFunctions.instance;
        String? resolvedIdentityId;
        final bvn = _controller.text.trim();

        // Try to get existing identityId from cached safehavenUserSetup
        if (_cachedSafehavenSetup != null) {
          final existingId = _cachedSafehavenSetup!['identityId']?.toString();
          final existingStatus = _cachedSafehavenSetup!['identityCheckStatus']?.toString();
          if (existingId != null && existingId.isNotEmpty && existingStatus == 'SUCCESS') {
            resolvedIdentityId = existingId;
            _setLoadingMessage('Identity already verified – creating account...', targetProgress: 0.6);
          }
        }

        // If not already verified, run the identity flow (only for tier 1/2 and if we have a BVN)
        if (resolvedIdentityId == null && bvn.length == 11) {
          _setLoadingMessage('Initiating identity verification...', targetProgress: 0.3);
          // Call initiate
          final initiateFunc = functions.httpsCallable('safehavenInitiateIdentityVerification');
          await initiateFunc.call({'type': 'BVN', 'number': bvn});

          // Close loading dialog, show OTP sheet
          _forceHideLoadingDialog();
          final otp = await _showIdentityOtpBottomSheet();
          if (otp == null || otp.isEmpty) {
            throw Exception('Identity verification cancelled');
          }

          // Show loading again and poll for webhook result
          _showLoadingDialog();
          _setLoadingMessage('Verifying OTP...', targetProgress: 0.4);

          // Poll for success
          String? identityId;
          for (int i = 0; i < 20; i++) {
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) break;
            final setupSnap = await FirebaseFirestore.instance
                .collection('safehavenUserSetup')
                .doc(uid)
                .get();
            final data = setupSnap.data();
            final status = data?['identityCheckStatus']?.toString();
            final id = data?['identityId']?.toString();
            if (status == 'SUCCESS' && id != null && id.isNotEmpty) {
              identityId = id;
              break;
            }
            if (status == 'FAILED' || status == 'DECLINED') {
              throw Exception('Identity verification failed');
            }
          }
          if (identityId == null) throw Exception('Identity verification timed out');
          resolvedIdentityId = identityId;
          _setLoadingMessage('Identity confirmed – creating wallet...', targetProgress: 0.6);
        }

        // 4. Check if virtual account already exists
        final existingVa = userData?['safehavenData']?['virtualAccount'];
        if (existingVa != null) {
          _setLoadingMessage('Account already exists – upgrading tier...', targetProgress: 0.8);
          await docRef.update({'safehavenData.tier': widget.tier});
        } else {
          // 5. Create virtual account
          final createAccountFunc = functions.httpsCallable('safehavenCreateSubAccount');
          final idempotencyKey = const Uuid().v4();
          final accountPayload = {
            'customerId': customerId ?? uid,
            'currency': 'NGN',
            'type': 'IndividualCustomer',
            'idempotencyKey': idempotencyKey,
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            'phoneNumber': phoneNumberForCreate,
            'country': 'NG',
            'state': selectedState!,
            'addressLine1': _streetController.text,
            'city': selectedCity!,
            'postalCode': Random().nextInt(900000) + 100000,
            'bvn': bvn,
            if (resolvedIdentityId != null && resolvedIdentityId.isNotEmpty) 'identityId': resolvedIdentityId,
          };
          final createResult = await createAccountFunc.call(accountPayload);
          await docRef.update({
            'safehavenData.virtualAccount': createResult.data,
            'safehavenData.tier': widget.tier,
          });
          _setLoadingMessage('Virtual account created!', targetProgress: 0.9);
          // Send email notification (optional – keep existing)
        }

        // Refresh cached data
        _cachedUserDoc = (await docRef.get()).data();
      } else {
        // Tier 3 – just update the document with ID details
        await docRef.update({
          'nin': ninController.text,
          'idType': selectedIdType,
          'idNumber': _idNumberController.text,
          'expiryDate': _formatDateForApi(_expiryController.text),
          'safehavenData.tier': widget.tier,
        });
      }

      await _hideLoadingDialog();
      await _showSuccessModal();
    } catch (e) {
      await _forceHideAndShowError(
        errorMessage: e.toString(),
        errorType: 'UpgradeTier_SubmissionError',
        stackTrace: null,
      );
    } finally {
      if (mounted) _forceHideLoadingDialog();
      setState(() { _isLoading = false; });
    }
  }

  Future<String?> _showIdentityOtpBottomSheet() async {
    final otpController = TextEditingController();
    String? errorText;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Verify Your Identity',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'An OTP has been sent to your BVN registered phone number. Enter it below to verify your BVN.',
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Enter OTP',
                        hintText: '6-digit OTP',
                        counterText: '',
                        errorText: errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: primaryColor, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          final otp = otpController.text.trim();
                          if (otp.length < 4) {
                            setModalState(() {
                              errorText = 'Please enter a valid OTP';
                            });
                            return;
                          }
                          Navigator.pop(ctx, otp);
                        },
                        child: Text(
                          'Verify',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    // Delay dispose so the sheet's 650ms exit animation can finish building
    // the TextFormField before the controller is torn down.  Disposing
    // immediately causes a "TextEditingController used after being disposed"
    // error because Flutter rebuilds the animated sheet during the close
    // animation after the route's Future has already resolved.
    Future<void>.delayed(
      const Duration(milliseconds: 800),
      otpController.dispose,
    );
    return result;
  }

  // -------------------------------------------------------------------------
  //  BUILD METHOD (unchanged UI)
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // BVN can only be entered once name, DOB, gender are filled and user is 18+
    // Replace bvnPrereqsMet in build()
    final bool bvnPrereqsMet =
        (widget.tier == 1 || widget.tier == 2) &&
        _firstNameController.text.isNotEmpty &&
        _lastNameController.text.isNotEmpty &&
        _dobController.text.isNotEmpty &&
        selectedGender != null &&
        _isUnder18() != true;

    // Replace the isFormValid block in build()
    bool isFormValid;
    if (widget.tier == 1 || widget.tier == 2) {
      // Both tier 1 and tier 2 need the same fields + BVN verified
      isFormValid =
          _controller.text.isNotEmpty &&
          _bvnVerified == true &&
          _firstNameController.text.isNotEmpty &&
          _lastNameController.text.isNotEmpty &&
          _dobController.text.isNotEmpty &&
          _streetController.text.isNotEmpty &&
          selectedState != null &&
          selectedCity != null &&
          selectedGender != null &&
          _isUnder18() != true;
    } else {
      // Tier 3: NIN + ID type + ID number (no expiry required yet)
      isFormValid =
          selectedIdType != null && _idNumberController.text.isNotEmpty;
    }

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: true,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20),
                Row(
                  children: [
                    SizedBox(width: 10),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black54,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 30),
                Text(
                  _screenTitle,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
                Text(
                  _screenSubtitle,
                  style: GoogleFonts.inter(color: Colors.grey.shade600),
                ),
                SizedBox(height: 20),

                if (widget.tier == 1) ...[
                  // Name fields for BVN verification
                  Text(
                    'First Name',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _firstNameController,
                    readOnly: _bvnVerified == true,
                    onChanged: (_) {
                      if (_bvnVerified != null) {
                        setState(() {
                          _bvnVerified = null;
                          _bvnVerifyStatus = null;
                          _bvnFieldMatches = null;
                        });
                      }
                      _scheduleDraftAutosave();
                    },
                    decoration: InputDecoration(
                      hintText: 'First name',
                      hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['firstname'] == false
                              ? Colors.red.shade400
                              : Colors.grey.shade200,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['firstname'] == false
                              ? Colors.red.shade400
                              : Colors.grey.shade200,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['firstname'] == false
                              ? Colors.red
                              : primaryColor,
                          width: 2,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['firstname'] == false
                              ? Colors.red.shade400
                              : Colors.grey.shade200,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  if (_bvnFieldMatches?['firstname'] == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 13,
                            color: Colors.red.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'First name does not match BVN records',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 16),
                  Text(
                    'Last Name',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _lastNameController,
                    readOnly: _bvnVerified == true,
                    onChanged: (_) {
                      if (_bvnVerified != null) {
                        setState(() {
                          _bvnVerified = null;
                          _bvnVerifyStatus = null;
                          _bvnFieldMatches = null;
                        });
                      }
                      _scheduleDraftAutosave();
                    },
                    decoration: InputDecoration(
                      hintText: 'Last name',
                      hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['lastname'] == false
                              ? Colors.red.shade400
                              : Colors.grey.shade200,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['lastname'] == false
                              ? Colors.red.shade400
                              : Colors.grey.shade200,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['lastname'] == false
                              ? Colors.red
                              : primaryColor,
                          width: 2,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _bvnFieldMatches?['lastname'] == false
                              ? Colors.red.shade400
                              : Colors.grey.shade200,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  if (_bvnFieldMatches?['lastname'] == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 13,
                            color: Colors.red.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Last name does not match BVN records',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 20),

                  //  Everything below is UNCHANGED
                  Text(
                    'Date of Birth',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _dobController,
                    keyboardType: TextInputType.datetime,
                    style: GoogleFonts.inter(color: Colors.black87),
                    onChanged: (_) {
                      setState(() {});
                      _scheduleDraftAutosave();
                    },
                    decoration: InputDecoration(
                      hintText: 'DD-MM-YYYY',
                      hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      suffixIcon: Icon(
                        Icons.calendar_today,
                        color: Colors.grey.shade500,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    readOnly: true,
                    onTap: () => _selectDob(context),
                  ),
                  if (_bvnFieldMatches?['birthdate'] == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 13,
                            color: Colors.red.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Date of birth does not match BVN records',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_isUnder18() == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 13,
                            color: Colors.red.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'You must be 18 or older to upgrade',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 20),
                  Text(
                    'Gender',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _bvnFieldMatches?['gender'] == false
                            ? Colors.red.shade400
                            : Colors.grey.shade200,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedGender,
                        isExpanded: true,
                        hint: Text(
                          'Select Gender',
                          style: GoogleFonts.inter(color: Colors.grey.shade500),
                        ),
                        items: ['Male', 'Female', 'Others']
                            .map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() => selectedGender = val);
                          _scheduleDraftAutosave();
                        },
                      ),
                    ),
                  ),
                  if (_bvnFieldMatches?['gender'] == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 13,
                            color: Colors.red.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Gender does not match BVN records',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.tier == 1 || widget.tier == 2) ...[
                    SizedBox(height: 20),
                    Text(
                      'BVN',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      maxLength: 11,
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.inter(color: Colors.black87),
                      readOnly: (widget.tier == 1 || widget.tier == 2)
                          ? (_bvnVerified == true || (!bvnPrereqsMet))
                          : false,
                      onChanged: _onBvnChanged,
                      decoration: InputDecoration(
                        counterText: "",
                        hintText: widget.tier == 1 && _bvnFromQore
                            ? 'BVN (verification provided)'
                            : !bvnPrereqsMet && widget.tier == 2
                            ? 'Fill in name, date of birth & gender first'
                            : 'Enter BVN',
                        hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _bvnBorderColor()),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _bvnBorderColor()),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _bvnFocusedBorderColor(),
                            width: 2,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _bvnBorderColor()),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        suffixIcon: (widget.tier == 1 || widget.tier == 2)
                            ? _bvnVerifying
                                  ? Padding(
                                      padding: const EdgeInsets.all(14.0),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                primaryColor,
                                              ),
                                        ),
                                      ),
                                    )
                                  : _bvnVerified == true
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    )
                                  : _bvnVerified == false
                                  ? Icon(Icons.cancel, color: Colors.red)
                                  : null
                            : null,
                      ),
                    ),
                    if (widget.tier == 1 || widget.tier == 2) ...[
                      SizedBox(height: 6),
                      if (_bvnVerifying)
                        Row(
                          children: [
                            SizedBox(width: 2),
                            Text(
                              'Verifying BVN, please wait...',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        )
                      else if (_bvnVerified == true)
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 14,
                              color: Colors.green.shade600,
                            ),
                            SizedBox(width: 4),
                            Text(
                              _bvnVerifyStatus == 'EXACT_MATCH'
                                  ? 'BVN verified'
                                  : 'BVN verified  partial name match',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        )
                      else if (_bvnVerified == false)
                        Row(
                          children: [
                            Icon(
                              Icons.cancel_outlined,
                              size: 14,
                              color: Colors.red.shade600,
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                (_bvnVerifyStatus != null &&
                                        _bvnVerifyStatus != 'NO_MATCH' &&
                                        _bvnVerifyStatus != 'EXACT_MATCH' &&
                                        _bvnVerifyStatus != 'PARTIAL_MATCH')
                                    ? (_bvnVerifyStatus!.toLowerCase().contains(
                                                'qoreid',
                                              ) ||
                                              _bvnVerifyStatus!.contains('404')
                                          ? 'BVN not found'
                                          : _bvnVerifyStatus!)
                                    : 'Please fix unmatched fields above',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                            if (bvnPrereqsMet && _controller.text.length == 11)
                              GestureDetector(
                                onTap: _verifyBvn,
                                child: Text(
                                  'Retry',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                    if (!bvnPrereqsMet && widget.tier == 2) ...[
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 13,
                            color: Colors.orange.shade700,
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _isUnder18() == true
                                  ? 'You must be 18 or older to enter your BVN'
                                  : 'Fill in your name, date of birth and gender above first',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  SizedBox(height: 20),
                  Text(
                    'Street Address',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _streetController,
                    style: GoogleFonts.inter(color: Colors.black87),
                    onChanged: (_) {
                      setState(() {});
                      _scheduleDraftAutosave();
                    },
                    decoration: InputDecoration(
                      hintText: 'Enter Street Address',
                      hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      suffixIcon: _buildLocationIcon(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'State',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _openStateSelector,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      decoration:
                          OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              )
                              .copyWith(borderRadius: BorderRadius.circular(8))
                              .toBoxDecoration(),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedState ?? 'Select State',
                              style: GoogleFonts.inter(
                                color: selectedState == null
                                    ? Colors.grey.shade500
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'City / LGA',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _openCitySelector,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      decoration:
                          OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              )
                              .copyWith(borderRadius: BorderRadius.circular(8))
                              .toBoxDecoration(),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedCity ?? 'Select City / LGA',
                              style: GoogleFonts.inter(
                                color: selectedCity == null
                                    ? Colors.grey.shade500
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (widget.tier == 2) ...[
                  Text(
                    'ID Type',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration:
                        OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            )
                            .copyWith(borderRadius: BorderRadius.circular(8))
                            .toBoxDecoration(),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedIdType,
                        isExpanded: true,
                        hint: Text(
                          'Select ID Type',
                          style: GoogleFonts.inter(color: Colors.grey.shade500),
                        ),
                        // In the else branch (Tier 3 section), replace the items list:
                        items: [
                          DropdownMenuItem(value: 'NIN', child: Text('NIN')),
                          DropdownMenuItem(
                            value: 'PASSPORT',
                            child: Text('International Passport'),
                          ),
                          DropdownMenuItem(
                            value: 'DRIVERS_LICENSE',
                            child: Text("Driver's License"),
                          ),
                        ].toList(),
                        onChanged: (val) {
                          setState(() => selectedIdType = val);
                          _scheduleDraftAutosave();
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'ID Number',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    maxLength: selectedIdType == 'PASSPORT'
                        ? 9
                        : (selectedIdType == 'NATIONAL_ID' ? 11 : null),
                    controller: _idNumberController,
                    keyboardType: selectedIdType == 'PASSPORT'
                        ? TextInputType.text
                        : TextInputType.number,
                    style: GoogleFonts.inter(color: Colors.black87),
                    onChanged: (_) {
                      setState(() {});
                      _scheduleDraftAutosave();
                    },
                    decoration: InputDecoration(
                      counterText:
                          (selectedIdType == 'PASSPORT' ||
                              selectedIdType == 'NATIONAL_ID')
                          ? ""
                          : null,
                      hintText: selectedIdType == 'PASSPORT'
                          ? 'Enter Passport Number (9 characters)'
                          : (selectedIdType == 'NATIONAL_ID'
                                ? 'Enter National ID (11 digits)'
                                : 'Enter ID Number'),
                      hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  if (selectedIdType == 'PASSPORT' ||
                      selectedIdType == 'DRIVERS_LICENSE') ...[
                    SizedBox(height: 20),
                    Text(
                      'Expiry Date',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: _expiryController,
                      keyboardType: TextInputType.datetime,
                      style: GoogleFonts.inter(color: Colors.black87),
                      onChanged: (_) {
                        setState(() {});
                        _scheduleDraftAutosave();
                      },
                      decoration: InputDecoration(
                        hintText: 'DD-MM-YYYY',
                        hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: primaryColor, width: 2),
                        ),
                        suffixIcon: Icon(
                          Icons.calendar_today,
                          color: Colors.grey.shade500,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      readOnly: true,
                      onTap: () => _selectExpiry(context),
                    ),
                  ],
                ],

                SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (isFormValid && !_isLoading) ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: primaryColor.withValues(
                        alpha: 0.2,
                      ),
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _primaryButtonText,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  //  ALL original helper methods (unchanged)
  // -------------------------------------------------------------------------

  Future<void> _selectDob(BuildContext context) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      String formattedDate =
          "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
      setState(() {
        _dobController.text = formattedDate;
        _bvnFieldMatches = null;
      });
      _scheduleDraftAutosave();
    }
  }

  Future<void> _selectExpiry(BuildContext context) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      String formattedDate =
          "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
      setState(() {
        _expiryController.text = formattedDate;
      });
      _scheduleDraftAutosave();
    }
  }

  String _formatDateForApi(String date) {
    // Convert DD-MM-YYYY to YYYY-MM-DD
    var parts = date.split('-');
    if (parts.length != 3) return date;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  /// Returns true if the DOB in _dobController indicates user is under 18.
  /// Returns null if DOB is empty or unparseable.
  bool? _isUnder18() {
    final dob = _dobController.text.trim();
    if (dob.isEmpty) return null;
    final parts = dob.split('-');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    final birthDate = DateTime(year, month, day);
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age < 18;
  }

  bool _isPhoneAlreadyExistsError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('customer with phonenumber already exist') ||
        msg.contains('phone number already exist') ||
        msg.contains('phonenumber already exist');
  }

  String _normalizePhoneForUserDoc(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+234${digits.substring(1)}';
    }
    if (digits.length == 10) {
      return '+234$digits';
    }
    if (phone.startsWith('+234')) return phone;
    return phone;
  }

  bool _isUsableSudoCustomer(Map<String, dynamic> attrs) {
    final status = attrs['status']?.toString().toUpperCase();
    if (status == null || status.isEmpty) return true;
    return status != 'DELETED' && status != 'INACTIVE';
  }

  Future<String?> _tryMatchExistingCustomerByBvn(
    String? bvn,
    DocumentReference docRef,
    String uid,
  ) async {
    if (_externalBvnMatch && mounted) {
      setState(() => _externalBvnMatch = false);
    }
    return null;

    if (bvn == null) return null;
    final bvnToMatch = bvn.replaceAll(RegExp(r'\D'), '').trim();
    if (bvnToMatch.isEmpty) return null;

    try {
      final functions = FirebaseFunctions.instance;
      print('Searching fetchAllCustomers for BVN: $bvnToMatch');
      final fetchRes = await functions
          .httpsCallable('fetchAllCustomers')
          .call();
      print('fetchAllCustomers Response (BVN match): ${fetchRes.data}');
      final List<dynamic>? customers =
          (fetchRes.data is Map && fetchRes.data['data'] is List)
          ? List<dynamic>.from(fetchRes.data['data'] as List)
          : (fetchRes.data is List
                ? List<dynamic>.from(fetchRes.data as List)
                : null);

      if (customers == null || customers.isEmpty) return null;

      for (var item in customers) {
        try {
          final Map<String, dynamic> it = Map<String, dynamic>.from(
            item as Map,
          );
          final attrs = (it['attributes'] is Map)
              ? Map<String, dynamic>.from(it['attributes'] as Map)
              : <String, dynamic>{};
          String? itemBvn;

          if (attrs['identificationLevel2'] is Map) {
            itemBvn = (attrs['identificationLevel2'] as Map)['bvn']?.toString();
          }
          itemBvn ??= attrs['bvn']?.toString();

          if (itemBvn != null &&
              itemBvn.replaceAll(RegExp(r'\D'), '').trim() == bvnToMatch) {
            if (!_isUsableSudoCustomer(attrs)) {
              print(
                'Skipping BVN-matched customer ${it['id']} due to status: ${attrs['status']}',
              );
              continue;
            }
            final foundId = it['id']?.toString() ?? '';
            print('Found matching customer in fetchAllCustomers: $foundId');

            try {
              final Map<String, dynamic> updateMap = {
                'safehavenData.customerCreation': {'data': it},
              };

              // Don't save verification as upgradeKyc success here - let submission logic handle it
              // The submission flow will check customer verification status and decide whether to call upgradeKyc

              await docRef.update(updateMap);
              print(
                'Saved existing customer creation data to user document for user $uid',
              );
            } catch (e) {
              print('Failed to save existing customer data: $e');
            }

            // Account creation is handled later in the submit flow only.
            return foundId;
          }
        } catch (e) {
          // ignore malformed entries
        }
      }
    } catch (e) {
      print('Error searching fetchAllCustomers: $e');
    }

    // Safehaven flow no longer matches legacy Anchor customers here.
    if (_externalBvnMatch && mounted) {
      setState(() => _externalBvnMatch = false);
    }
    return null;
  }

  String _formatDateFromApi(String date) {
    // Convert YYYY-MM-DD (or YYYY-MM-DDT...) to DD-MM-YYYY for display
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(date);
    if (m != null) return '${m.group(3)}-${m.group(2)}-${m.group(1)}';
    return date;
  }

  String _toTitleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  void _populateFieldsFromDoc(Map<String, dynamic>? data) {
    if (data == null) return;

    final kyc = data['kyc'] as Map<String, dynamic>?;
    final savedSelfieUrl = kyc?['selfieUrl']?.toString();
    if (savedSelfieUrl != null &&
        savedSelfieUrl.isNotEmpty &&
        _selfieUrl != savedSelfieUrl) {
      _selfieUrl = savedSelfieUrl;
    }

    // BVN
    final qoreData = data['qoreIdData'] as Map<String, dynamic>?;
    final qoreBvnVerif =
        qoreData?['bvnVerificationNoFace'] as Map<String, dynamic>?;
    final qoreVerification = qoreData?['verification'] as Map<String, dynamic>?;
    final qoreMetadata = qoreVerification?['metadata'] as Map<String, dynamic>?;
    final bvn =
        data['bvn']?.toString() ??
        qoreBvnVerif?['bvn']?.toString() ??
        qoreMetadata?['idNumber']?.toString();
    if (bvn != null && bvn.isNotEmpty && _controller.text != bvn) {
      _controller.text = bvn;
    }

    // NIN
    final nin = data['nin']?.toString();
    if (nin != null && nin.isNotEmpty && ninController.text != nin) {
      ninController.text = nin;
    }

    // Date of birth - prefer root dateOfBirth, else try safehavenData.customerCreation
    String? dob = data['dateOfBirth']?.toString();
    if ((dob == null || dob.isEmpty) && data['safehavenData'] is Map) {
      final gc =
          (data['safehavenData'] as Map)['customerCreation']
              as Map<String, dynamic>?;
      final cdata = gc?['data'] as Map<String, dynamic>?;
      dob = cdata?['dateOfBirth']?.toString() ?? cdata?['dob']?.toString();
      if ((dob == null || dob.isEmpty) &&
          cdata != null &&
          cdata['attributes'] is Map) {
        final attrs = cdata['attributes'] as Map<String, dynamic>;
        dob = attrs['dateOfBirth']?.toString() ?? attrs['dob']?.toString();
      }
    }
    if (dob != null && dob.isNotEmpty) {
      final display = _formatDateFromApi(dob);
      if (_dobController.text != display) _dobController.text = display;
    }

    // Gender
    String? gender = data['gender']?.toString();
    if ((gender == null || gender.isEmpty) && data['safehavenData'] is Map) {
      final gc =
          (data['safehavenData'] as Map)['customerCreation']
              as Map<String, dynamic>?;
      final cdata = gc?['data'] as Map<String, dynamic>?;
      if (cdata != null) {
        gender = cdata['gender']?.toString();
        if (gender == null && cdata['attributes'] is Map) {
          gender = (cdata['attributes'] as Map)['gender']?.toString();
        }
      }
    }
    // Only set gender from doc if the user hasn't already made a selection
    if (gender != null && gender.isNotEmpty && selectedGender == null) {
      setState(() {
        selectedGender = gender;
      });
    }

    // Address: support both nested map and dotted firestore field-path keys.
    final addressRaw = data['address'];
    final address = addressRaw is Map
        ? Map<String, dynamic>.from(addressRaw)
        : null;

    final rootStreet =
        address?['street']?.toString() ?? data['address.street']?.toString();
    final rootCity =
        address?['city']?.toString() ?? data['address.city']?.toString();
    final rootState =
        address?['state']?.toString() ?? data['address.state']?.toString();

    if ((rootStreet ?? '').isNotEmpty && _streetController.text != rootStreet) {
      _streetController.text = rootStreet!;
    }

    if ((rootState ?? '').isNotEmpty && selectedState != rootState) {
      setState(() {
        selectedState = rootState;
      });
      _fetchCities(rootState!);
    }

    if ((rootCity ?? '').isNotEmpty && selectedCity != rootCity) {
      setState(() {
        selectedCity = rootCity;
      });
    }

    if ((rootStreet ?? '').isEmpty &&
        (rootCity ?? '').isEmpty &&
        (rootState ?? '').isEmpty &&
        data['safehavenData'] is Map) {
      final gc =
          (data['safehavenData'] as Map)['customerCreation']
              as Map<String, dynamic>?;
      final cdata = gc?['data'] as Map<String, dynamic>?;
      if (cdata != null && cdata['attributes'] is Map) {
        final attrs = cdata['attributes'] as Map<String, dynamic>;
        final street =
            attrs['street']?.toString() ?? attrs['address']?.toString() ?? '';
        final city = attrs['city']?.toString() ?? attrs['locality']?.toString();
        final state = attrs['state']?.toString();
        if (street.isNotEmpty && _streetController.text != street) {
          _streetController.text = street;
        }
        if (state != null && state.isNotEmpty && selectedState != state) {
          setState(() {
            selectedState = state;
          });
          _fetchCities(state);
        }
        if (city != null && city.isNotEmpty && selectedCity != city) {
          setState(() {
            selectedCity = city;
          });
        }
      }
    }
  }

  Future<void> _checkInitialBvnConflict() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      String? candidate = _controller.text.trim();
      if (candidate.isEmpty) {
        candidate = data?['bvn']?.toString();
      }
      if (candidate == null || candidate.isEmpty) {
        final qore = data?['qoreIdData'] as Map<String, dynamic>?;
        final bvnVerif =
            qore?['bvnVerificationNoFace'] as Map<String, dynamic>?;
        candidate = bvnVerif?['bvn']?.toString();
      }
      if (candidate == null || candidate.isEmpty) {
        final qore = data?['qoreIdData'] as Map<String, dynamic>?;
        final verification = qore?['verification'] as Map<String, dynamic>?;
        final metadata = verification?['metadata'] as Map<String, dynamic>?;
        candidate = metadata?['idNumber']?.toString();
      }
      if (candidate != null && candidate.isNotEmpty) {
        await _checkBvnConflict(candidate);
      }
    } catch (e) {
      print('Error during initial BVN conflict check: $e');
    }
  }

  Future<void> _checkBvnConflict(String bvn) async {
    if (bvn.isEmpty || bvn.length != 11) {
      if (_bvnConflict) setState(() => _bvnConflict = false);
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      final q1 = await FirebaseFirestore.instance
          .collection('users')
          .where('bvn', isEqualTo: bvn)
          .get();
      final q2 = await FirebaseFirestore.instance
          .collection('users')
          .where('qoreIdData.verification.metadata.idNumber', isEqualTo: bvn)
          .get();

      final allDocs = <String, QueryDocumentSnapshot>{};
      for (var doc in q1.docs) {
        allDocs[doc.id] = doc;
      }
      for (var doc in q2.docs) {
        allDocs[doc.id] = doc;
      }

      final conflict = allDocs.keys.any((id) => id != user?.uid);
      if (mounted) setState(() => _bvnConflict = conflict);
    } catch (e) {
      print('Error checking BVN conflict: $e');
    }
  }

  void _onBvnChanged(String val) {
    _bvnCheckTimer?.cancel();
    _bvnVerifyTimer?.cancel();

    _bvnCheckTimer = Timer(Duration(milliseconds: 500), () {
      _checkBvnConflict(val);
    });

    // Auto-verify when 11 digits entered, tier 1 and tier 2
    if ((widget.tier == 1 || widget.tier == 2) && val.length == 11) {
      _bvnVerifyTimer = Timer(Duration(milliseconds: 800), _verifyBvn);
    } else if (widget.tier == 1 || widget.tier == 2) {
      setState(() {
        _bvnVerified = null;
        _bvnVerifyStatus = null;
        _bvnFieldMatches = null;
      });
    }

    if (val.isEmpty || val.length != 11) {
      if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
    }
    _scheduleDraftAutosave();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _idNumberController.dispose();
    _expiryController.dispose();
    _dobController.dispose();
    _streetController.dispose();
    _userDocSub?.cancel();
    _bvnCheckTimer?.cancel();
    _bvnVerifyTimer?.cancel();
    _draftSaveTimer?.cancel();
    _loadingStepNotifier.dispose();
    _progressController?.dispose();
    _progressController = null; // <-- set to null after dispose
    _loadingStatusNotifier.dispose();
    super.dispose();
  }
}

extension OutlineInputBorderToBoxDecoration on OutlineInputBorder {
  BoxDecoration toBoxDecoration() {
    return BoxDecoration(
      borderRadius: borderRadius,
      border: Border.all(color: borderSide.color, width: borderSide.width),
    );
  }
}