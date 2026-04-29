import 'dart:convert';
import 'package:card_app/auth/upgrade_tier.dart';
import 'package:card_app/ui/feedback.dart';
import 'package:card_app/utils.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class ChooseUpgradeTier extends StatefulWidget {
  final String tier;
  const ChooseUpgradeTier({super.key, required this.tier});

  @override
  State<ChooseUpgradeTier> createState() => _ChooseUpgradeTierState();
}

class _ChooseUpgradeTierState extends State<ChooseUpgradeTier> {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController dobController = TextEditingController();

  List<String> states = [];
  String? selectedState;
  bool isLoadingStates = false;
  bool isLoading = false;
  DateTime? selectedDate;

  StreamSubscription<DocumentSnapshot>? _userDocSub;
  bool _bvnMatch = false;

  @override
  void initState() {
    super.initState();
    _fetchStates('Nigeria');
    _initDatePicker();
    _listenForBvnMatch();
  }

  // Force dd-MM-yyyy format by replacing any slashes with hyphens
  String _forceHyphenFormat(DateTime date) {
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    String year = date.year.toString();
    return '$day-$month-$year';
  }

  void _initDatePicker() {
    final now = DateTime.now();
    selectedDate = DateTime(now.year - 18, now.month, now.day);
    dobController.text = _forceHyphenFormat(selectedDate!);
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    addressController.dispose();
    dobController.dispose();
    super.dispose();
  }

  Future<void> _fetchStates(String country) async {
    setState(() {
      isLoadingStates = true;
      states = [];
      selectedState = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
          'https://countriesnow.space/api/v0.1/countries/states?country=${Uri.encodeQueryComponent(country)}',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['error'] == false) {
          final countryData = (data['data'] as List).firstWhere(
            (c) => c['name'].toString().toLowerCase() == country.toLowerCase(),
            orElse: () => null,
          );

          if (countryData != null && countryData['states'] != null) {
            setState(() {
              states = (countryData['states'] as List)
                  .map((state) => state['name'] as String)
                  .toList();
              states.sort();
              isLoadingStates = false;
            });
          } else {
            setState(() => isLoadingStates = false);
            showSimpleDialog('No states found for $country', Colors.red);
          }
        } else {
          setState(() => isLoadingStates = false);
          showSimpleDialog('API returned an error', Colors.red);
        }
      }
    } catch (e) {
      setState(() => isLoadingStates = false);
      showSimpleDialog('Failed to load states: $e', Colors.red);
    }
  }

  void _listenForBvnMatch() {
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
          final match = metadata?['match'];
          if (!mounted) return;
          setState(() {
            _bvnMatch = match == true;
          });
        });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        dobController.text = _forceHyphenFormat(picked);
      });
    }
  }

  bool get _identityStepCompleted =>
      widget.tier == "2" || widget.tier == "3";

  bool get _profileStepCompleted => widget.tier == "3";

  String get _verificationStatusLabel {
    if (_profileStepCompleted) return 'Verification complete';
    if (_identityStepCompleted) return 'Wallet active';
    return 'Verification pending';
  }

  String get _verificationStatusDescription {
    if (_profileStepCompleted) {
      return 'Your identity and profile details are complete.';
    }
    if (_identityStepCompleted) {
      return 'Your wallet is active. You can add more identity details next.';
    }
    return 'Start identity verification to activate your wallet.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 15),
                Row(
                  children: [
                    SizedBox(width: 5),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black54,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "Complete Verification",
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Follow the next required step to activate your wallet\nand complete your identity details",
                      style: GoogleFonts.inter(
                        color: Colors.black.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Color(0xFF45556C).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Color(0xFF45556C).withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Color(0xFF45556C).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.shield_outlined,
                              color: Color(0xFF45556C),
                              size: 30,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _verificationStatusLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _verificationStatusDescription,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "Step 1",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(width: 15),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                          color: primaryColor.withValues(
                                            alpha: 0.1,
                                          ),
                                        ),
                                        child: Text(
                                          "Popular",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: primaryColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Ideal for regular transactions",
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Spacer(),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.credit_card_outlined,
                                  color: primaryColor,
                                  size: 30,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 30),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Limit per transaction",
                                    style: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "₦5,000,000",
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 15),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Daily Limit",
                                    style: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    "₦10,000,000",
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 15),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Maximum Account Balance",
                                    style: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    "₦100,000,000",
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          SizedBox(height: 20),
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  color: primaryColor,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Required for verification",
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Name, date of birth, gender, BVN, address and OTP",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 25),
                          InkWell(
                            onTap: () {
                              if (_identityStepCompleted) {
                                return;
                              }
                              navigateTo(context, UpgradeTier(tier: 2));
                            },
                            child: Container(
                              alignment: Alignment.center,
                              width: MediaQuery.of(context).size.width * 0.9,
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: _identityStepCompleted
                                    ? Colors.grey
                                    : primaryColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _identityStepCompleted
                                    ? "Completed"
                                    : "Start Verification",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFAF5FF), Color(0xFFEEF2FF)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Color(0xFFE9D4FF)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "Step 2",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              Color(0xFF9810FA),
                                              Color(0xFF4F39F6),
                                            ],
                                          ),
                                        ),
                                        child: Text(
                                          "Optional",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Add more identity details",
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Spacer(),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Color(0xFFF3E8FF),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.shield_outlined,
                                  color: Color(0xFF9810FA),
                                  size: 25,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 30),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Purpose",
                                    style: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    "Store additional KYC details",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9810FA),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "What you will add",
                                    style: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    "NIN and a valid government ID",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9810FA),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.newspaper, color: Color(0xFF9810FA)),
                                SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Additional profile details",
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.black,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      "You can save any of the following:",
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(height: 15),
                                    Row(
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF9810FA),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          "International Passport",
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF9810FA),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          "Driver's License",
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF9810FA),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          "NIN",
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 25),
                          InkWell(
                            onTap: () {
                              if (!_identityStepCompleted) {
                                showSnackBar(
                                  context,
                                  "Complete Step 1 first",
                                  primaryColor,
                                );
                                return;
                              }
                              if (_profileStepCompleted) {
                                return;
                              }
                              navigateTo(context, UpgradeTier(tier: 3));
                            },
                            child: Container(
                              alignment: Alignment.center,
                              width: MediaQuery.of(context).size.width * 0.9,
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: _identityStepCompleted && !_profileStepCompleted
                                    ? Color(0xFF9810FA)
                                    : Colors.grey,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _identityStepCompleted && !_profileStepCompleted
                                    ? "Add Profile Details"
                                    : _profileStepCompleted
                                    ? "Completed"
                                    : "Complete Step 1 First",
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 50),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
