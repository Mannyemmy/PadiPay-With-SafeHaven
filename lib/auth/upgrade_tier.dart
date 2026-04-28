import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
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

class _UpgradeTierState extends State<UpgradeTier> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController ninController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  // BVN verification (tier 1)
  bool _bvnVerifying = false;
  bool? _bvnVerified; // null = not attempted, true = match, false = no match
  String? _bvnVerifyStatus;
  Map<String, bool>? _bvnFieldMatches; // per-field match result after verification
  Timer? _bvnVerifyTimer;

  // Name fields shown above BVN for tier 1
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

  void _setLoadingStep(int step) {
    _loadingStepNotifier.value = step;
  }
  File? _selfieFile;
  String? _selfieUrl;
  bool _isUploadingSelfie = false;

  StreamSubscription<DocumentSnapshot>? _userDocSub;
  bool _bvnFromQore = false;

  // BVN conflict detection
  bool _bvnConflict = false;
  Timer? _bvnCheckTimer;
  Timer? _draftSaveTimer;
  String? _lastQueriedBvn; // avoid repeated findUserByBvn calls for same BVN
  bool _externalBvnMatch =
      false; // true when an external Anchor customer exists for the BVN

  @override
  void initState() {
    super.initState();
    _fetchStates();
    _listenForIdNumber();
    // Perform an initial BVN conflict check if BVN exists in the user document
    _checkInitialBvnConflict();
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
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _autosaveDraft,
    );
  }

  Future<void> _autosaveDraft() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final Map<String, dynamic> updateData = {};

    if (widget.tier == 1 || widget.tier == 2) {
      final bvn = _controller.text.trim();
      if (bvn.isNotEmpty) updateData['bvn'] = bvn;

      if (widget.tier == 1) {
        final fn = _firstNameController.text.trim();
        final ln = _lastNameController.text.trim();
        if (fn.isNotEmpty) updateData['firstName'] = fn;
        if (ln.isNotEmpty) updateData['lastName'] = ln;
      }

      if (widget.tier == 2) {
        final fn = _firstNameController.text.trim();
        final ln = _lastNameController.text.trim();
        if (fn.isNotEmpty) updateData['firstName'] = fn;
        if (ln.isNotEmpty) updateData['lastName'] = ln;
      }

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

  void _showLoadingDialog() {
    if (_loadingDialogShowing || !mounted) return;
    _loadingDialogShowing = true;
    _loadingStepNotifier.value = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<int>(
          valueListenable: _loadingStepNotifier,
          builder: (context, step, __) {
            const stepLabels = ['Step 1', 'Step 2', 'Step 3'];
            final progress = step == 0 ? 0.05 : step / 3.0;
            final pct = step == 0 ? '' : '${(step / 3 * 100).round()}%';
            return Dialog(
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
                    const Text(
                      'Verifying your account',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Please wait, this may take a moment...',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(3, (i) {
                        final done = i < step;
                        final current = i == step - 1;
                        return Text(
                          stepLabels[i],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: current || done
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: done
                                ? primaryColor
                                : current
                                    ? primaryColor
                                    : Colors.grey.shade400,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        pct,
                        style: TextStyle(
                          fontSize: 12,
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ).whenComplete(() => _loadingDialogShowing = false);
  }

  void _hideLoadingDialog() {
    if (!_loadingDialogShowing || !mounted) return;
    _loadingDialogShowing = false;
    Navigator.of(context, rootNavigator: true).pop();
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
                const Text(
                  'Account Upgraded!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'You can now fully enjoy all Padi Pay features including higher transfer limits, bill payments, and much more.',
                  style: TextStyle(
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
                    child: const Text(
                      'Go to Dashboard',
                      style: TextStyle(
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
      final fm = Map<String, dynamic>.from(resData['fieldMatches'] as Map? ?? {});
      final rawBd = resData['bvnData'];
      final bvnDobRaw = rawBd != null ? (rawBd as Map)['birthdate']?.toString() : null;
      // BVN API returns YYYY-MM-DD; controller holds DD-MM-YYYY — convert for comparison
      final bvnDobDisplay = (bvnDobRaw != null && bvnDobRaw.isNotEmpty)
          ? _formatDateFromApi(bvnDobRaw)
          : null;
      final bvnGender = rawBd != null ? (rawBd as Map)['gender']?.toString() : null;
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
          if ((bvnData['gender'] ?? '').toString().isNotEmpty && selectedGender == null) {
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
            updates['firstName'] = _toTitleCase(bvnData['firstname'].toString());
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
            if (fn != null && fn.isNotEmpty && _firstNameController.text.isEmpty) {
              _firstNameController.text = _toTitleCase(fn);
            }
            final ln = bvnData['lastname']?.toString();
            if (ln != null && ln.isNotEmpty && _lastNameController.text.isEmpty) {
              _lastNameController.text = _toTitleCase(ln);
            }
          });
        }
      }
    } on FirebaseFunctionsException catch (e) {
      final raw = e.message ?? '';
      final userMsg = raw.toLowerCase().contains('404') || raw.toLowerCase().contains('not found')
          ? 'BVN not found'
          : raw.isNotEmpty
          ? raw
          : 'Verification failed — please try again';
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = userMsg;
      });
      print('BVN verification error: $e');
    } catch (e) {
      setState(() {
        _bvnVerified = false;
        _bvnVerifyStatus = 'Verification failed — please try again';
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
          if (_bvnVerified == null && bvnVerif != null && bvnVerif['verified'] == true) {
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
                    (item) => item.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ),
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
                            style: const TextStyle(
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
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Text(
                                'No results found',
                                style: TextStyle(color: Colors.grey.shade500),
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
                                            style: TextStyle(
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

  @override
  Widget build(BuildContext context) {
    // BVN can only be entered once name, DOB, gender are filled and user is 18+
    final bool bvnPrereqsMet = widget.tier == 2 &&
        _firstNameController.text.isNotEmpty &&
        _lastNameController.text.isNotEmpty &&
        _dobController.text.isNotEmpty &&
        selectedGender != null &&
        _isUnder18() != true;

    bool isFormValid;
    if (widget.tier == 2) {
      // If BVN is verified, allow submission even if a conflict was detected —
      // the submit flow resolves conflicts via BVN/email matching.
      final bvnAllowed = _bvnVerified == true || !_bvnConflict || _externalBvnMatch;
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
          _isUnder18() != true &&
          bvnAllowed;
    } else {
      isFormValid =
          ninController.text.isNotEmpty &&
          selectedIdType != null &&
          _idNumberController.text.isNotEmpty &&
          _expiryController.text.isNotEmpty;
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
                'Verify Your Identity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                "To comply with CBN guidelines, we are required to verify every customer.",
                style: TextStyle(color: Colors.grey.shade600),
              ),
              SizedBox(height: 20),

              if (widget.tier == 2 || widget.tier == 1) ...[
                // ── Name fields for BVN verification ─────────────────────────
                if (widget.tier == 1 || widget.tier == 2) ...[
                  Text(
                    'First Name',
                    style: TextStyle(
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
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['firstname'] == false ? Colors.red.shade400 : Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['firstname'] == false ? Colors.red.shade400 : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['firstname'] == false ? Colors.red : primaryColor, width: 2),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['firstname'] == false ? Colors.red.shade400 : Colors.grey.shade200),
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
                          Icon(Icons.error_outline, size: 13, color: Colors.red.shade600),
                          SizedBox(width: 4),
                          Text('First name does not match BVN records', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                        ],
                      ),
                    ),
                  SizedBox(height: 16),
                  Text(
                    'Last Name',
                    style: TextStyle(
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
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['lastname'] == false ? Colors.red.shade400 : Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['lastname'] == false ? Colors.red.shade400 : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['lastname'] == false ? Colors.red : primaryColor, width: 2),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _bvnFieldMatches?['lastname'] == false ? Colors.red.shade400 : Colors.grey.shade200),
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
                          Icon(Icons.error_outline, size: 13, color: Colors.red.shade600),
                          SizedBox(width: 4),
                          Text('Last name does not match BVN records', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                        ],
                      ),
                    ),
                  SizedBox(height: 20),
                ],

                // ── Everything below is UNCHANGED ─────────────────────────────
                Text(
                  'Date of Birth',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _dobController,
                  keyboardType: TextInputType.datetime,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) {
                    setState(() {});
                    _scheduleDraftAutosave();
                  },
                  decoration: InputDecoration(
                    hintText: 'DD-MM-YYYY',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
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
                        Icon(Icons.error_outline, size: 13, color: Colors.red.shade600),
                        SizedBox(width: 4),
                        Text('Date of birth does not match BVN records', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                      ],
                    ),
                  ),
                if (_isUnder18() == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 13, color: Colors.red.shade600),
                        SizedBox(width: 4),
                        Text('You must be 18 or older to upgrade', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                      ],
                    ),
                  ),
                SizedBox(height: 20),
                Text(
                  'Gender',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: _bvnFieldMatches?['gender'] == false ? Colors.red.shade400 : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedGender,
                      isExpanded: true,
                      hint: Text(
                        'Select Gender',
                        style: TextStyle(color: Colors.grey.shade500),
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
                        Icon(Icons.error_outline, size: 13, color: Colors.red.shade600),
                        SizedBox(width: 4),
                        Text('Gender does not match BVN records', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                      ],
                    ),
                  ),
                if (widget.tier == 1 || widget.tier == 2) ...[
                  SizedBox(height: 20),
                  Text(
                    'BVN',
                    style: TextStyle(
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
                    style: TextStyle(color: Colors.black87),
                    readOnly: widget.tier == 1
                        ? (_bvnFromQore || _bvnVerified == true)
                        : widget.tier == 2
                        ? (_bvnVerified == true || !bvnPrereqsMet)
                        : false,
                    onChanged: _onBvnChanged,
                    decoration: InputDecoration(
                      counterText: "",
                      hintText: widget.tier == 1 && _bvnFromQore
                          ? 'BVN (verification provided)'
                          : !bvnPrereqsMet && widget.tier == 2
                          ? 'Fill in name, date of birth & gender first'
                          : 'Enter BVN',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
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
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          primaryColor,
                                        ),
                                      ),
                                    ),
                                  )
                                : _bvnVerified == true
                                ? Icon(Icons.check_circle, color: Colors.green)
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
                            style: TextStyle(
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
                                : 'BVN verified — partial name match',
                            style: TextStyle(
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
                              (_bvnVerifyStatus != null && _bvnVerifyStatus != 'NO_MATCH' && _bvnVerifyStatus != 'EXACT_MATCH' && _bvnVerifyStatus != 'PARTIAL_MATCH')
                                  ? (_bvnVerifyStatus!.toLowerCase().contains('qoreid') || _bvnVerifyStatus!.contains('404')
                                      ? 'BVN not found'
                                      : _bvnVerifyStatus!)
                                  : 'Please fix unmatched fields above',
                              style: TextStyle(
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
                                style: TextStyle(
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
                        Icon(Icons.info_outline, size: 13, color: Colors.orange.shade700),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _isUnder18() == true
                                ? 'You must be 18 or older to enter your BVN'
                                : 'Fill in your name, date of birth and gender above first',
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                SizedBox(height: 20),
                Text(
                  'Street Address',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _streetController,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) {
                    setState(() {});
                    _scheduleDraftAutosave();
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter Street Address',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
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
                  style: TextStyle(
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedState ?? 'Select State',
                            style: TextStyle(
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
                  style: TextStyle(
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedCity ?? 'Select City / LGA',
                            style: TextStyle(
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
              ] else ...[
                // ── TIER 3: NIN + ID — completely unchanged ───────────────────
                Text(
                  "NIN",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  maxLength: 11,
                  controller: ninController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) {
                    setState(() {});
                    _scheduleDraftAutosave();
                  },
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: 'Enter NIN (11 digits)',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
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
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'ID Type',
                  style: TextStyle(
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
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          )
                          .copyWith(borderRadius: BorderRadius.circular(8))
                          .toBoxDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedIdType,
                      isExpanded: true,
                      hint: Text(
                        'Select ID Type',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      items:
                          [
                                'PASSPORT',
                                'DRIVERS_LICENSE',
                                'VOTERS_CARD',
                                'NATIONAL_ID',
                              ]
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(id),
                                ),
                              )
                              .toList(),
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
                  style: TextStyle(
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
                  style: TextStyle(color: Colors.black87),
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
                    hintStyle: TextStyle(color: Colors.grey.shade500),
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
                Text(
                  'Expiry Date',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _expiryController,
                  keyboardType: TextInputType.datetime,
                  style: TextStyle(color: Colors.black87),
                  onChanged: (_) {
                    setState(() {});
                    _scheduleDraftAutosave();
                  },
                  decoration: InputDecoration(
                    hintText: 'DD-MM-YYYY',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
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
                    'Upgrade to Tier ${widget.tier}',
                    style: TextStyle(
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

  bool _isUsableAnchorCustomer(Map<String, dynamic> attrs) {
    final status = attrs['status']?.toString().toUpperCase();
    if (status == null || status.isEmpty) return true;
    return status != 'DELETED' && status != 'INACTIVE';
  }

  Future<String?> _showPhoneConflictBottomSheet(String currentPhone) async {
    String phoneValue = currentPhone;
    String? errorText;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
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
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phone Number Already Registered',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This phone number has already been registered to an account. Would you like to change it?',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      initialValue: phoneValue,
                      keyboardType: TextInputType.phone,
                      onChanged: (value) => phoneValue = value,
                      decoration: InputDecoration(
                        hintText: 'Enter new phone number (11 digits)',
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
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Cancel'),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                            ),
                            onPressed: () {
                              final raw = phoneValue.trim();
                              var normalized = raw;
                              if (normalized.startsWith('+234')) {
                                normalized =
                                    '0${normalized.replaceFirst('+234', '')}';
                              }
                              final digits = normalized.replaceAll(
                                RegExp(r'\D'),
                                '',
                              );
                              if (!(digits.length == 11 &&
                                  digits.startsWith('0'))) {
                                setModalState(() {
                                  errorText =
                                      'Enter a valid 11-digit phone number starting with 0';
                                });
                                return;
                              }
                              Navigator.pop(ctx, digits);
                            },
                            child: Text(
                              'Change Number',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    return result;
  }

  Future<String?> _tryMatchExistingCustomerByBvn(
    String? bvn,
    DocumentReference docRef,
    String uid,
  ) async {
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
            if (!_isUsableAnchorCustomer(attrs)) {
              print(
                'Skipping BVN-matched customer ${it['id']} due to status: ${attrs['status']}',
              );
              continue;
            }
            final foundId = it['id']?.toString() ?? '';
            print('Found matching customer in fetchAllCustomers: $foundId');

            try {
              final Map<String, dynamic> updateMap = {
                'getAnchorData.customerCreation': {'data': it},
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

    // Date of birth - prefer root dateOfBirth, else try getAnchorData.customerCreation
    String? dob = data['dateOfBirth']?.toString();
    if ((dob == null || dob.isEmpty) && data['getAnchorData'] is Map) {
      final gc =
          (data['getAnchorData'] as Map)['customerCreation']
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
    if ((gender == null || gender.isEmpty) && data['getAnchorData'] is Map) {
      final gc =
          (data['getAnchorData'] as Map)['customerCreation']
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
        data['getAnchorData'] is Map) {
      final gc =
          (data['getAnchorData'] as Map)['customerCreation']
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

    // Mark external match flag if getAnchorData exists
    if (data['getAnchorData'] is Map) {
      if (!_externalBvnMatch && mounted) {
        setState(() => _externalBvnMatch = true);
      }
    }
  }

  Future<dynamic> _callCloudFunction(
    String name,
    Map<String, dynamic> payload, {
    int retries = 2,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      final start = DateTime.now();
      try {
        HttpsCallable func = FirebaseFunctions.instance.httpsCallable(name);
        final result = await func.call(payload).timeout(timeout);
        final duration = DateTime.now().difference(start);
        print(
          '_callCloudFunction $name attempt $attempt took ${duration.inMilliseconds} ms',
        );
        print('_callCloudFunction $name response: ${result.data}');
        return result.data;
      } on FirebaseFunctionsException catch (e, st) {
        final duration = DateTime.now().difference(start);
        print(
          'Error in $name (attempt $attempt) after ${duration.inMilliseconds} ms: ${e.code} ${e.message} ${e.details}',
        );
        print(st);
        if (attempt > retries) {
          throw Exception('$name failed: ${e.message}');
        }
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      } catch (e, st) {
        final duration = DateTime.now().difference(start);
        print(
          'Error in $name (attempt $attempt) after ${duration.inMilliseconds} ms: $e',
        );
        print(st);
        if (attempt > retries) {
          throw Exception('$name failed: $e');
        }
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  // _postJson removed - fetchAllCustomers is used instead for fetching customers by BVN.
  // _findUserByBvn removed - we use fetchAllCustomers cloud function exclusively now.
  Future<void> _maybeFetchGetAnchorByBvn(String bvn) async {
    // Use fetchAllCustomers exclusively to find a customer with this BVN.
    if (bvn.isEmpty || bvn.length != 11) {
      if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
      return;
    }
    if (_lastQueriedBvn == bvn) return;
    _lastQueriedBvn = bvn;

    try {
      print('Searching fetchAllCustomers for BVN: $bvn');
      final functions = FirebaseFunctions.instance;
      final fetchRes = await functions
          .httpsCallable('fetchAllCustomers')
          .call();
      print('fetchAllCustomers Response (auto-fetch BVN): ${fetchRes.data}');
      final List<dynamic>? customers =
          (fetchRes.data is Map && fetchRes.data['data'] is List)
          ? List<dynamic>.from(fetchRes.data['data'] as List)
          : (fetchRes.data is List
                ? List<dynamic>.from(fetchRes.data as List)
                : null);

      if (customers == null || customers.isEmpty) {
        print('fetchAllCustomers returned no customers');
        if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
        return;
      }

      final String bvnToMatch = bvn.replaceAll(RegExp(r'\D'), '').trim();
      Map<String, dynamic>? matchedCustomer;
      Map<String, dynamic>? matchedVerification;
      String? matchedCustomerId;

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
            matchedCustomer = it;
            matchedVerification = (attrs['verification'] is Map)
                ? Map<String, dynamic>.from(attrs['verification'] as Map)
                : null;
            matchedCustomerId = it['id']?.toString() ?? '';
            break;
          }
        } catch (e) {
          // ignore
        }
      }

      if (matchedCustomer == null) {
        print('No matching customer found in fetchAllCustomers for BVN $bvn');
        if (_externalBvnMatch) setState(() => _externalBvnMatch = false);
        return;
      }

      // Mark external match
      if (!_externalBvnMatch && mounted) {
        setState(() => _externalBvnMatch = true);
      }

      print('Found matching customer in fetchAllCustomers: $matchedCustomerId');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final snap = await docRef.get();
      final snapData = snap.data();
      final existing = snapData?['getAnchorData'] as Map<String, dynamic>?;

      // Save customerCreation and upgradeKyc if available
      final Map<String, dynamic> updateMap = {};
      updateMap['getAnchorData.customerCreation'] = {'data': matchedCustomer};
      if (matchedVerification != null) {
        updateMap['getAnchorData.upgradeKyc'] = {
          'status': 'success',
          'data': matchedVerification,
        };
        final verLevel = (matchedVerification['level']?.toString() ?? '')
            .toUpperCase();
        final verStatus = (matchedVerification['status']?.toString() ?? '')
            .toLowerCase();
        if (verLevel == 'TIER_2' || verStatus == 'approved') {
          updateMap['getAnchorData.tier'] = 2;
        }
      }

      if (existing == null) {
        await docRef.update(updateMap);
        print(
          'Saved customerCreation (and upgradeKyc if present) to user document for user $uid',
        );
      } else {
        // Merge non-destructively: at least update upgradeKyc/tier if present
        final Map<String, dynamic> mergeUpdate = {};
        if (matchedVerification != null) {
          mergeUpdate['getAnchorData.upgradeKyc'] =
              updateMap['getAnchorData.upgradeKyc'];
          if (updateMap.containsKey('getAnchorData.tier')) {
            mergeUpdate['getAnchorData.tier'] = updateMap['getAnchorData.tier'];
          }
          await docRef.update(mergeUpdate);
          print(
            'Updated existing getAnchorData with upgradeKyc/tier for user $uid',
          );
        } else {
          print('Local getAnchorData exists; not overwriting customerCreation');
        }
      }

      // Refresh doc and populate form fields from saved data
      try {
        final refreshed = await docRef.get();
        _populateFieldsFromDoc(refreshed.data());
      } catch (e) {
        print('Failed to refresh user doc for autofill: $e');
      }

      // Attempt to create an electronic (virtual) account if missing
      try {
        final verifySnap = await docRef.get();
        final verifyData = verifySnap.data();
        final verifyGet = verifyData?['getAnchorData'] as Map<String, dynamic>?;
        final hasVirtual =
            verifyGet != null && verifyGet['virtualAccount'] != null;
        final customerId =
            verifyGet?['customerCreation']?['data']?['id']?.toString() ??
            matchedCustomerId;
        if (!hasVirtual && customerId != null && customerId.isNotEmpty) {
          print(
            'Attempting to create electronic account for customer: $customerId',
          );
          final createVaRes = await functions
              .httpsCallable('sudoCreateSubAccount')
              .call({
                'customerId': customerId,
                'userId': uid,
                'currency': 'NGN',
                'type': 'IndividualCustomer',
                'idempotencyKey': const Uuid().v4(),
              });
          print(
            'createElectronicAccount Response (auto-fetch): ${createVaRes.data}',
          );
          if (createVaRes.data != null) {
            await docRef.update({
              'getAnchorData.virtualAccount': createVaRes.data,
            });
            print('Created and saved electronic account for user $uid');
          } else {
            print('createElectronicAccount returned no data for $customerId');
          }
        } else {
          print(
            'Virtual account already present or missing customerId; skipping creation',
          );
        }
      } catch (e) {
        print('Failed to create electronic account as part of auto-fetch: $e');
        try {
          await docRef.update({
            'getAnchorData.virtualAccount_creation_error': e.toString(),
          });
        } catch (_) {}
      }
    } catch (e) {
      print('Error searching fetchAllCustomers during auto-find: $e');
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
      // Prefer the controller value, otherwise root bvn, otherwise qore idNumber
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
      // Query root 'bvn' field
      final q1 = await FirebaseFirestore.instance
          .collection('users')
          .where('bvn', isEqualTo: bvn)
          .get();
      // Query qore id number nested field
      final q2 = await FirebaseFirestore.instance
          .collection('users')
          .where('qoreIdData.verification.metadata.idNumber', isEqualTo: bvn)
          .get();

      final allDocs = <String, QueryDocumentSnapshot>{};
      for (var d in q1.docs) {
        allDocs[d.id] = d;
      }
      for (var d in q2.docs) {
        allDocs[d.id] = d;
      }

      final conflict = allDocs.keys.any((id) => id != user?.uid);
      if (mounted) setState(() => _bvnConflict = conflict);
    } catch (e) {
      print('Error checking BVN conflict: $e');
    }
  }

  Future<String?> _tryMatchExistingCustomerByEmail(
    String email,
    DocumentReference docRef,
    String uid,
  ) async {
    if (email.isEmpty) return null;

    try {
      final functions = FirebaseFunctions.instance;
      print('Searching fetchAllCustomers for email: $email');
      final fetchRes = await functions
          .httpsCallable('fetchAllCustomers')
          .call();
      print('fetchAllCustomers Response (email match): ${fetchRes.data}');
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
          print('Checking customer ${it['id']} with attributes: $attrs');
          String? itemEmail = attrs['email']?.toString();

          if (itemEmail != null &&
              itemEmail.toLowerCase() == email.toLowerCase()) {
            if (!_isUsableAnchorCustomer(attrs)) {
              print(
                'Skipping email-matched customer ${it['id']} due to status: ${attrs['status']}',
              );
              continue;
            }
            final foundId = it['id']?.toString() ?? '';
            print(
              'Found matching customer by email in fetchAllCustomers: $foundId',
            );

            try {
              final Map<String, dynamic> updateMap = {
                'getAnchorData.customerCreation': {'data': it},
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
      print('Error searching fetchAllCustomers for email: $e');
    }

    return null;
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

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
    });
    _showLoadingDialog();

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _hideLoadingDialog();
      showGenericError(
        errorMessage: 'No user logged in',
        errorType: 'UpgradeTier_NoUser',
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    DocumentReference docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid);

    try {
      // Get user data
      DocumentSnapshot snap = await docRef.get();
      if (!snap.exists) {
        showGenericError(
          errorMessage: 'User document not found in Firestore',
          errorType: 'UpgradeTier_UserDocNotFound',
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      Map<String, dynamic>? userData = snap.data() as Map<String, dynamic>?;
      if (userData == null) {
        showGenericError(
          errorMessage: 'User data is null',
          errorType: 'UpgradeTier_UserDataNull',
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (widget.tier == 1 || widget.tier == 2) {
        // Validate required fields for Tier 2
        // Fall back to controller values in case Firestore hasn't been updated yet
        String? firstName = (userData['firstName']?.toString() ?? '').isNotEmpty
            ? userData['firstName'].toString()
            : _firstNameController.text.trim().isNotEmpty
            ? _firstNameController.text.trim()
            : null;
        String? lastName = (userData['lastName']?.toString() ?? '').isNotEmpty
            ? userData['lastName'].toString()
            : _lastNameController.text.trim().isNotEmpty
            ? _lastNameController.text.trim()
            : null;
        String? email = userData['email']?.toString();
        String? phoneNumber = userData['phone']?.toString().replaceFirst('+234', '');

        if (firstName == null || firstName.trim().isEmpty) {
          print('Submit blocked: firstName missing');
          showGenericError(
            errorMessage: 'firstName is missing or empty in Firestore',
            errorType: 'UpgradeTier_MissingFirstName',
          );
          setState(() { _isLoading = false; });
          return;
        }
        if (lastName == null || lastName.trim().isEmpty) {
          print('Submit blocked: lastName missing');
          showGenericError(
            errorMessage: 'lastName is missing or empty in Firestore',
            errorType: 'UpgradeTier_MissingLastName',
          );
          setState(() { _isLoading = false; });
          return;
        }
        if (email == null || email.trim().isEmpty) {
          print('Submit blocked: email missing');
          showGenericError(
            errorMessage: 'email is missing or empty in Firestore',
            errorType: 'UpgradeTier_MissingEmail',
          );
          setState(() { _isLoading = false; });
          return;
        }
        if (phoneNumber == null || phoneNumber.trim().isEmpty) {
          print('Submit blocked: phone missing');
          showGenericError(
            errorMessage: 'phoneNumber is missing or empty in Firestore',
            errorType: 'UpgradeTier_MissingPhoneNumber',
          );
          setState(() { _isLoading = false; });
          return;
        }

        // Format phone number: Prepend '0' if 10 digits
        phoneNumber = phoneNumber.trim();
        if (phoneNumber.length == 10 &&
            RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
          phoneNumber = '0$phoneNumber';
        }
        // Validate phone number: Must be 11 digits and start with '0'
        if (!RegExp(r'^0\d{10}$').hasMatch(phoneNumber)) {
          print('Submit blocked: invalid phone format: $phoneNumber');
          showGenericError(
            errorMessage: 'Invalid phone number format: $phoneNumber',
            errorType: 'UpgradeTier_InvalidPhoneFormat',
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
        String phoneNumberForCreate = phoneNumber;

        // Parse DOB and check age for Tier 2
        var parts = _dobController.text.split('-');
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        DateTime birthDate = DateTime(year, month, day);
        DateTime today = DateTime.now();
        int age = today.year - birthDate.year;
        if (today.month < birthDate.month ||
            (today.month == birthDate.month && today.day < birthDate.day)) {
          age--;
        }
        if (age < 18) {
          showGenericError(
            errorMessage: 'User age is $age, must be at least 18',
            errorType: 'UpgradeTier_UnderageUser',
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // If BVN conflicts with another app user, attempt to resolve by matching
        // an existing Anchor customer by BVN/email before blocking submission.
        if (_bvnConflict && !_externalBvnMatch) {
          print(
            'BVN conflict detected; attempting existing customer match before blocking.',
          );
          String? resolvedCustomerId = await _tryMatchExistingCustomerByBvn(
            _controller.text,
            docRef,
            uid,
          );

          resolvedCustomerId ??= await _tryMatchExistingCustomerByEmail(
            email,
            docRef,
            uid,
          );

          if (resolvedCustomerId != null && resolvedCustomerId.isNotEmpty) {
            if (mounted) setState(() => _externalBvnMatch = true);
            print(
              'BVN conflict resolved via existing customer match: $resolvedCustomerId',
            );
          } else {
            print(
              'BVN conflict unresolved by matching; continuing to customer creation flow.',
            );
          }
        } else if (_bvnConflict && _externalBvnMatch) {
          print(
            'BVN conflict detected but external customer found; proceeding with external-match upgrade flow.',
          );
        }

        // Prepare Tier 2 data
        String formattedDateForApi = _formatDateForApi(_dobController.text);
        String gender = selectedGender!;
        String street = _streetController.text;
        String city = selectedCity!;
        String state = selectedState!;
        int postalCode = Random().nextInt(900000) + 100000;

        // Save Tier 2 data to Firestore
        Map<String, dynamic> updateData = {
          'bvn': _controller.text,
          'dateOfBirth': formattedDateForApi,
          'gender': gender,
          'address': {
            'street': street,
            'city': city,
            'state': state,
            'country': 'NG',
            'postalCode': postalCode,
          },
        };
        await docRef.update(updateData);

        // Create/Get existing GetAnchor Customer
        _setLoadingStep(1);
        final functions = FirebaseFunctions.instance;
        String? customerId =
            userData['getAnchorData']?['customerCreation']?['data']?['id']
                ?.toString();
        final String? savedCustomerStatus =
            userData['getAnchorData']?['customerCreation']?['data']?['attributes']?['status']
                ?.toString()
                .toUpperCase();
        if (customerId != null &&
            customerId.isNotEmpty &&
            (savedCustomerStatus == 'DELETED' ||
                savedCustomerStatus == 'INACTIVE')) {
          print(
            'Ignoring saved customerId $customerId due to unusable status: $savedCustomerStatus',
          );
          customerId = null;
        }
        try {
          if (customerId != null && customerId.isNotEmpty) {
            print(
              'Using existing customer from getAnchorData.customerCreation: $customerId',
            );
          }

          if (customerId == null || customerId.isEmpty) {
            print('Attempting to match existing customer by BVN');
            final matched = await _tryMatchExistingCustomerByBvn(
              _controller.text,
              docRef,
              uid,
            );
            if (matched != null) {
              customerId = matched;
              print(
                'Matched existing customer by BVN: $customerId; proceeding with KYC/VA steps',
              );
            }
          }

          if (customerId == null || customerId.isEmpty) {
            print('No BVN match found; attempting email match');
            final matchedByEmail = await _tryMatchExistingCustomerByEmail(
              email,
              docRef,
              uid,
            );
            if (matchedByEmail != null) {
              customerId = matchedByEmail;
              print(
                'Matched existing customer by email: $customerId; proceeding with KYC/VA steps',
              );
            }
          }

          // If no match found, create new customer
          if (customerId == null || customerId.isEmpty) {
            print(
              'No existing customer found by getAnchorData, BVN, or email; creating new customer',
            );
            HttpsCallable createUserFunc = functions.httpsCallable(
              'sudoCreateUser',
            );
            while (customerId == null) {
              final payload = {
                'firstName': firstName,
                'lastName': lastName,
                'email': email,
                'country': 'NG',
                'state': state,
                'addressLine1': street,
                'city': city,
                'postalCode': postalCode,
                'phoneNumber': phoneNumberForCreate,
              };
              print('Sending createGetanchorUser payload: $payload');
              try {
                final createUserResult = await createUserFunc.call(payload);
                print(
                  'Create GetAnchor User Response: ${createUserResult.data}',
                );
                customerId = createUserResult.data['data']['id'];

                // Save customer creation response
                await docRef.update({
                  'getAnchorData.customerCreation': createUserResult.data,
                  'phone': _normalizePhoneForUserDoc(phoneNumberForCreate),
                });
              } on FirebaseFunctionsException catch (e) {
                if (_isPhoneAlreadyExistsError(e)) {
                  final newPhone = await _showPhoneConflictBottomSheet(
                    phoneNumberForCreate,
                  );
                  if (newPhone == null || newPhone.isEmpty) {
                    throw Exception(
                      'Customer creation cancelled: phone number already exists',
                    );
                  }
                  phoneNumberForCreate = newPhone;
                  continue;
                }
                // BVN or Email already exists in the organisation — find the existing customer
                final errMsg = (e.message ?? '').toLowerCase();
                if (errMsg.contains('bvn already exists') ||
                    errMsg.contains('bvn already exist') ||
                    errMsg.contains('email already exist') ||
                    errMsg.contains('customer with email already exist')) {
                  final conflictType = (errMsg.contains('email already exist') ||
                          errMsg.contains('customer with email already exist'))
                      ? 'Email'
                      : 'BVN';
                  print(
                    '$conflictType already exists in org; falling back to email then BVN match',
                  );
                  // Try email match first
                  final emailMatched = await _tryMatchExistingCustomerByEmail(
                    email,
                    docRef,
                    uid,
                  );
                  if (emailMatched != null && emailMatched.isNotEmpty) {
                    customerId = emailMatched;
                    print(
                      'Recovered existing customer via email match after $conflictType conflict: $customerId',
                    );
                    break;
                  }
                  // Fall back to BVN match
                  final bvnMatched = await _tryMatchExistingCustomerByBvn(
                    _controller.text,
                    docRef,
                    uid,
                  );
                  if (bvnMatched != null && bvnMatched.isNotEmpty) {
                    customerId = bvnMatched;
                    print(
                      'Recovered existing customer via BVN match after $conflictType conflict: $customerId',
                    );
                    break; // exit the while loop with the found customerId
                  }
                  throw Exception(
                    '$conflictType already exists in organisation but could not find the existing customer.',
                  );
                }
                rethrow;
              }
            }
          }
        } catch (e, st) {
          print('Error matching/creating customer: $e');
          showGenericError(
            errorMessage: e.toString(),
            errorType: 'UpgradeTier_MatchOrCreateCustomer',
            stackTrace: st,
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Attempt KYC upgrade (if we have a customerId) but skip if upgrade already succeeded
        _setLoadingStep(2);
        if (customerId.isNotEmpty) {
          // re-fetch to check verification status and existing upgradeKyc
          final refreshed = await docRef.get();
          final Map<String, dynamic>? refreshedMap =
              refreshed.data() as Map<String, dynamic>?;
          final Map<String, dynamic>? storedUpgrade =
              (refreshedMap != null && refreshedMap['getAnchorData'] is Map)
              ? (refreshedMap['getAnchorData']
                        as Map<String, dynamic>)['upgradeKyc']
                    as Map<String, dynamic>?
              : null;

          // Check if customer is verified - get from customerCreation data
          final Map<String, dynamic>? customerCreationData =
              (refreshedMap != null && refreshedMap['getAnchorData'] is Map)
              ? (refreshedMap['getAnchorData']
                        as Map<String, dynamic>)['customerCreation']
                    as Map<String, dynamic>?
              : null;
          final Map<String, dynamic>? creationAttrs =
              customerCreationData?['data']?['attributes']
                  as Map<String, dynamic>?;
          final Map<String, dynamic>? custVerification =
              creationAttrs?['verification'] as Map<String, dynamic>?;
          final String custVerificationStatus =
              custVerification?['status']?.toString().toLowerCase() ??
              'unverified';

          final bool needsKycUpgrade =
              custVerificationStatus == 'unverified' ||
              custVerificationStatus == 'pending';
          final bool upgradeKycPreviouslySucceeded =
              storedUpgrade != null &&
              (storedUpgrade['success'] == true ||
                  (storedUpgrade['status']?.toString().toLowerCase() ==
                      'success') ||
                  (storedUpgrade['data'] is Map &&
                      (storedUpgrade['data']['success'] == true)));

          if (needsKycUpgrade && !upgradeKycPreviouslySucceeded) {
            print('Customer is unverified; calling upgradeCustomerKyc');
            HttpsCallable upgradeKycFunc = functions.httpsCallable(
              'sudoUpgradeCustomerKyc',
            );
            final String kycLevel = widget.tier == 1 ? 'TIER_1' : 'TIER_2';
            final kycPayload = {
              'customerId': customerId,
              // Tier 1 must send TIER_1, Tier 2 must send TIER_2.
              'level': kycLevel,
              'bvn': _controller.text,
              'dateOfBirth': formattedDateForApi,
              'gender': gender,
            };
            print('Sending upgradeCustomerKyc payload: $kycPayload');
            try {
              final upgradeKycResult = await upgradeKycFunc.call(kycPayload);
              print('Upgrade Customer KYC Response: ${upgradeKycResult.data}');
              await docRef.update({
                'getAnchorData.upgradeKyc': upgradeKycResult.data,
              });
            } on FirebaseFunctionsException catch (e) {
              final errMsg = (e.message ?? '').toLowerCase();
              if (errMsg.contains('bvn already exists') ||
                  errMsg.contains('bvn already exist')) {
                // BVN already KYC'd at this level — treat as success and proceed
                print(
                  'upgradeCustomerKyc: BVN already exists in org — customer already upgraded, skipping.',
                );
                await docRef.update({
                  'getAnchorData.upgradeKyc': {
                    'status': 'success',
                    'skipped': true,
                    'reason': 'BVN already exists in organisation',
                  },
                });
              } else {
                rethrow;
              }
            }
          } else if (upgradeKycPreviouslySucceeded) {
            print('Skipping KYC upgrade: previous upgrade already succeeded');
          } else {
            print('Customer is already verified; skipping KYC upgrade');
          }
        } else {
          print('No customerId available for KYC upgrade');
        }

        // Create Electronic Account (if not already created)
        _setLoadingStep(3);
        final refreshedAfterKyc = await docRef.get();
        final Map<String, dynamic>? refreshedAfterMap =
            refreshedAfterKyc.data() as Map<String, dynamic>?;
        final existingVa = refreshedAfterMap != null
            ? (refreshedAfterMap['getAnchorData'] is Map
                  ? (refreshedAfterMap['getAnchorData']
                        as Map<String, dynamic>)['virtualAccount']
                  : null)
            : null;
        if (existingVa != null) {
          print('Electronic account already exists, skipping creation');
          final currentTier =
              refreshedAfterMap != null &&
                  refreshedAfterMap['getAnchorData'] is Map
              ? (refreshedAfterMap['getAnchorData']
                    as Map<String, dynamic>)['tier']
              : null;
          if (currentTier != widget.tier) {
            await docRef.update({'getAnchorData.tier': widget.tier});
          }
        } else {
          if (customerId.isEmpty) {
            print('No customerId available to create electronic account');
          } else {
            try {
              String customerTypeForAccount = 'IndividualCustomer';
              if (refreshedAfterMap != null &&
                  refreshedAfterMap['getAnchorData'] is Map) {
                final getAnchorData = Map<String, dynamic>.from(
                  refreshedAfterMap['getAnchorData'] as Map,
                );
                if (getAnchorData['customerCreation'] is Map) {
                  final customerCreation = Map<String, dynamic>.from(
                    getAnchorData['customerCreation'] as Map,
                  );
                  if (customerCreation['data'] is Map) {
                    final customerData = Map<String, dynamic>.from(
                      customerCreation['data'] as Map,
                    );
                    final resolvedType = customerData['type']?.toString();
                    if (resolvedType != null && resolvedType.isNotEmpty) {
                      customerTypeForAccount = resolvedType;
                    }
                  }
                }
              }
              HttpsCallable createAccountFunc = functions.httpsCallable(
                'sudoCreateSubAccount',
              );
              final idempotencyKey = Uuid().v4();
              final accountPayload = {
                'customerId': customerId,
                'currency': 'NGN',
                'type': customerTypeForAccount,
                'idempotencyKey': idempotencyKey,
              };
              print('Sending createElectronicAccount payload: $accountPayload');
              dynamic createAccountResult;
              try {
                createAccountResult = await createAccountFunc.call(
                  accountPayload,
                );
              } on FirebaseFunctionsException catch (createErr) {
                final lowerMsg = (createErr.message ?? '').toLowerCase();
                if (lowerMsg.contains('customerid not valid')) {
                  print(
                    'createElectronicAccount failed due to invalid customerId; attempting customer recreation and retry.',
                  );

                  final recreatePayload = {
                    'firstName': firstName,
                    'lastName': lastName,
                    'email': email,
                    'country': 'NG',
                    'state': state,
                    'addressLine1': street,
                    'city': city,
                    'postalCode': postalCode,
                    'phoneNumber': phoneNumberForCreate,
                  };

                  final recreateResult = await functions
                      .httpsCallable('sudoCreateUser')
                      .call(recreatePayload);

                  final recreatedCustomerId =
                      recreateResult.data['data']?['id']?.toString();
                  final recreatedType =
                      recreateResult.data['data']?['type']?.toString() ??
                      customerTypeForAccount;

                  if (recreatedCustomerId == null ||
                      recreatedCustomerId.isEmpty) {
                    throw Exception(
                      'Failed to recover from invalid customerId: recreated customer has no id.',
                    );
                  }

                  await docRef.update({
                    'getAnchorData.customerCreation': recreateResult.data,
                    'phone': _normalizePhoneForUserDoc(phoneNumberForCreate),
                  });

                  final retryPayload = {
                    'customerId': recreatedCustomerId,
                    'currency': 'NGN',
                    'type': recreatedType,
                    'idempotencyKey': Uuid().v4(),
                  };
                  print(
                    'Retrying createElectronicAccount with recreated customer: $retryPayload',
                  );

                  createAccountResult = await createAccountFunc.call(
                    retryPayload,
                  );
                } else {
                  rethrow;
                }
              }
              print(
                'Create Electronic Account Response: ${createAccountResult.data}',
              );
              await docRef.update({
                'getAnchorData.virtualAccount': createAccountResult.data,
                'getAnchorData.tier': widget.tier,
              });
              print('✅ Electronic account created and tier saved successfully');
              // Send virtual account details email
              try {
                final dynamic vaRaw = createAccountResult.data;
                final dynamic vaData = vaRaw is Map ? vaRaw['data'] : null;
                final String? vaAccountId = vaData is Map
                    ? vaData['id']?.toString()
                    : null;

                // Fetch real (non-masked) account number and bank name via
                // fetchAccountNumber, the same way the home page does it.
                String vaAccountNumber = 'N/A';
                String vaBankName = 'N/A';
                if (vaAccountId != null && vaAccountId.isNotEmpty) {
                  try {
                    final fetchRes = await FirebaseFunctions.instance
                        .httpsCallable('sudoFetchAccountNumber')
                        .call({'accountId': vaAccountId});
                    final dynamic resp = fetchRes.data;
                    if (resp is Map) {
                      final String? an =
                          resp['accountNumber']?.toString() ??
                          resp['data']?['attributes']?['accountNumber']
                              ?.toString();
                      final dynamic bank = resp['bank'] ?? resp['data']?['attributes']?['bank'];
                      final String? bn = bank is Map
                          ? bank['name']?.toString()
                          : bank?.toString();
                      if (an != null && an.isNotEmpty) vaAccountNumber = an;
                      if (bn != null && bn.isNotEmpty) vaBankName = bn;
                      // Persist resolved values to Firestore
                      final Map<String, dynamic> resolved = {};
                      if (an != null && an.isNotEmpty) {
                        resolved['getAnchorData.virtualAccount.data.attributes.accountNumber'] = an;
                      }
                      if (bank != null) {
                        resolved['getAnchorData.virtualAccount.data.attributes.bank'] =
                            bank is Map ? bank : {'name': bn};
                      }
                      if (resolved.isNotEmpty) {
                        await docRef.update(resolved);
                      }
                    }
                  } catch (fetchErr) {
                    print('fetchAccountNumber error (will use masked value): $fetchErr');
                    // Fall back to raw response values
                    final dynamic vaAttrs = vaData is Map ? vaData['attributes'] : null;
                    if (vaAttrs is Map) {
                      vaAccountNumber = vaAttrs['accountNumber']?.toString() ?? 'N/A';
                      final dynamic rawBank = vaAttrs['bank'];
                      vaBankName = rawBank is Map
                          ? rawBank['name']?.toString() ?? 'N/A'
                          : rawBank?.toString() ?? 'N/A';
                    }
                  }
                } else {
                  // No accountId — fall back to raw response attrs
                  final dynamic vaAttrs = vaData is Map ? vaData['attributes'] : null;
                  if (vaAttrs is Map) {
                    vaAccountNumber = vaAttrs['accountNumber']?.toString() ?? 'N/A';
                    final dynamic rawBank = vaAttrs['bank'];
                    vaBankName = rawBank is Map
                        ? rawBank['name']?.toString() ?? 'N/A'
                        : rawBank?.toString() ?? 'N/A';
                  }
                }
                final String userEmailForVa =
                    userData['email']?.toString() ?? '';
                final String userFirstName =
                    userData['firstName']?.toString() ?? 'User';
                if (userEmailForVa.isNotEmpty) {
                  final sendEmailResult = await FirebaseFunctions.instance
                      .httpsCallable('sendEmail')
                      .call({
                        'to': userEmailForVa,
                        'subject': '🎉 Your PadiPay Virtual Account is Ready',
                        'html':
                            '<!DOCTYPE html><html><head><meta charset="UTF-8"/></head><body style="margin:0;padding:0;background:#f0f2f5;font-family:Helvetica,Arial,sans-serif;">'
                            '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;"><tr><td align="center">'
                            '<table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">'
                            '<tr><td align="center" style="padding-bottom:24px;"><span style="font-size:22px;font-weight:700;color:#1a1a2e;">Padi<span style="color:#4f46e5;">Pay</span></span></td></tr>'
                            '<tr><td style="background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.07);">'
                            '<table width="100%" cellpadding="0" cellspacing="0">'
                            '<tr><td style="background:linear-gradient(135deg,#4f46e5,#7c3aed);height:5px;font-size:0;">&nbsp;</td></tr>'
                            '<tr><td style="padding:40px 48px 36px;">'
                            '<p style="margin:0 0 8px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#4f46e5;">Account Ready</p>'
                            '<h1 style="margin:0 0 16px;font-size:26px;font-weight:700;color:#0f0f1a;">Your Virtual Account is Ready!</h1>'
                            '<p style="margin:0 0 24px;font-size:15px;color:#6b7280;line-height:1.6;">Hi $userFirstName, your PadiPay virtual bank account has been created. Use the details below to receive payments.</p>'
                            '<table width="100%" cellpadding="16" cellspacing="0" style="background:#f5f3ff;border:1.5px solid #e0d9ff;border-radius:12px;margin:0 0 24px;">'
                            '<tr><td align="center">'
                            '<p style="margin:0;font-size:13px;font-weight:600;color:#4f46e5;letter-spacing:1px;text-transform:uppercase;">Account Number</p>'
                            '<p style="margin:8px 0;font-size:32px;font-weight:800;letter-spacing:6px;color:#1a1a2e;">$vaAccountNumber</p>'
                            '<p style="margin:0;font-size:14px;color:#6b7280;"><strong>Bank:</strong> $vaBankName</p>'
                            '</td></tr></table>'
                            '<p style="margin:0;font-size:13px;color:#9ca3af;line-height:1.6;">Share these details with anyone who needs to send you money. Funds will reflect in your PadiPay wallet instantly.</p>'
                            '</td></tr>'
                            '<tr><td style="padding:0 48px;"><div style="border-top:1px solid #f3f4f6;"></div></td></tr>'
                            '<tr><td style="padding:24px 48px;"><p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay</p></td></tr>'
                            '</table></td></tr></table></td></tr></table></body></html>',
                      });
                  print('sendEmail Response: ${sendEmailResult.data}');
                }
              } catch (emailErr) {
                print('Error sending virtual account email: $emailErr');
              }
            } catch (e, st) {
              print('Error creating electronic account: $e');
              // Still save tier even if VA creation failed, so user can retry
              try {
                await docRef.update({'getAnchorData.tier': widget.tier});
                print('Saved tier to document despite VA creation failure');
              } catch (e2) {
                print('Failed to save tier: $e2');
              }
              // Log the error
              await logErrorToFirestore(
                e.toString(),
                'UpgradeTier_ElectronicAccountCreation',
                st,
              );
              // Verify if virtualAccount was actually saved despite the error
              try {
                final verify = await docRef.get();
                final verifyData = verify.data() as Map<String, dynamic>?;
                final verifyVa =
                    verifyData?['getAnchorData']?['virtualAccount'];
                if (verifyVa != null) {
                  print(
                    'Virtual account was saved despite API error; showing success',
                  );
                  showSimpleDialog(
                    'Account upgraded successfully',
                    Colors.green,
                  );
                  navigateTo(context, HomePage());
                  return;
                }
              } catch (_) {}
              // Only show error if virtualAccount is missing
              showSimpleDialog(
                'Account updated but virtual account setup incomplete. You can still use basic features.',
                Colors.orange,
              );
            }
          }
        }
      } else {
        // Tier 3: Only call upgradeCustomerKyc and update Firestore
        // Get customerId
        String? customerId =
            userData['getAnchorData']?['customerCreation']?['data']?['id'];
        if (customerId == null) {
          showGenericError(
            errorMessage: 'customerId not found in user getAnchorData',
            errorType: 'UpgradeTier_Tier3MissingCustomerId',
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Save Tier 3 data to Firestore
        Map<String, dynamic> updateData = {
          'nin': ninController.text,
          'idType': selectedIdType,
          'idNumber': _idNumberController.text,
          'expiryDate': _formatDateForApi(_expiryController.text),
        };
        await docRef.update(updateData);

        // Call upgradeCustomerKyc for Tier 3
        try {
          final functions = FirebaseFunctions.instance;
          HttpsCallable upgradeKycFunc = functions.httpsCallable(
            'sudoUpgradeCustomerKyc',
          );
          final kycPayload = {
            'customerId': customerId,
            'level': 'TIER_3',
            'idType': selectedIdType,
            'idNumber': _idNumberController.text,
            'expiryDate': _formatDateForApi(_expiryController.text),
          };
          print('Sending upgradeCustomerKyc payload: $kycPayload');
          final upgradeKycResult = await upgradeKycFunc.call(kycPayload);
          print('Upgrade Customer KYC Response: ${upgradeKycResult.data}');

          // Update Firestore with KYC response and tier
          await docRef.update({
            'getAnchorData.upgradeKyc': upgradeKycResult.data,
            'getAnchorData.tier': widget.tier,
          });
        } catch (e, st) {
          showGenericError(
            errorMessage: e.toString(),
            errorType: 'UpgradeTier_Tier3UpgradeKyc',
            stackTrace: st,
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      print('✅ Account upgraded successfully');
      _hideLoadingDialog();
      await _showSuccessModal();
    } catch (e, st) {
      print('Error during submission: $e');
      showGenericError(
        errorMessage: e.toString(),
        errorType: 'UpgradeTier_SubmissionError',
        stackTrace: st,
      );
    } finally {
      _hideLoadingDialog();
      setState(() {
        _isLoading = false;
      });
    }
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
