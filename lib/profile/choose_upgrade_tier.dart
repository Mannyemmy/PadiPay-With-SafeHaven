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

// Tier levels: 1 = Tier 1, 2 = Tier 2, 3 = Tier 3
  bool get _tier1Completed => widget.tier == "1" || widget.tier == "2" || widget.tier == "3";
  bool get _tier2Completed => widget.tier == "2" || widget.tier == "3";
  bool get _tier3Completed => widget.tier == "3";

  String get _verificationStatusLabel {
    if (_tier3Completed) return 'Tier 3 Verified';
    if (_tier2Completed) return 'Tier 2 Active';
    if (_tier1Completed) return 'Tier 1 Active';
    return 'Verification pending';
  }

  String get _verificationStatusDescription {
    if (_tier3Completed) {
      return 'You have full access with Tier 3 limits.';
    }
    if (_tier2Completed) {
      return 'Upgrade to Tier 3 for higher limits.';
    }
    if (_tier1Completed) {
      return 'Upgrade to Tier 2 for higher limits.';
    }
    return 'Complete Tier 1 verification to activate your wallet.';
  }

  // Tier limits
  String get _tier1Limit => '₦10,000';
  String get _tier1Daily => '₦50,000';
  String get _tier1Max => '₦50,000';
  
  String get _tier2Limit => '₦100,000';
  String get _tier2Daily => '₦500,000';
  String get _tier2Max => '₦500,000';
  
  String get _tier3Limit => '₦5,000,000';
  String get _tier3Daily => '₦10,000,000';
  String get _tier3Max => '₦100,000,000';

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
                    // Tier 1 Card
                    _buildTierCard(
                      tierNumber: 1,
                      title: "Tier 1",
                      subtitle: "Basic transactions",
                      limit: _tier1Limit,
                      daily: _tier1Daily,
                      maxBalance: _tier1Max,
                      requirements: "Name, date of birth, gender, BVN, address",
                      isCompleted: _tier1Completed,
                      canStart: true,
                      previousTierCompleted: true,
                      primaryColor: primaryColor,
                    ),
                    SizedBox(height: 20),
                    // Tier 2 Card
                    _buildTierCard(
                      tierNumber: 2,
                      title: "Tier 2",
                      subtitle: "Higher transaction limits",
                      limit: _tier2Limit,
                      daily: _tier2Daily,
                      maxBalance: _tier2Max,
                      requirements: "Government-issued ID (International Passport, Driver's License, or NIN)",
                      isCompleted: _tier2Completed,
                      canStart: _tier1Completed && !_tier2Completed,
                      previousTierCompleted: _tier1Completed,
                      primaryColor: Color(0xFF9810FA),
                    ),
                    SizedBox(height: 20),
                    // Tier 3 Card
                    _buildTierCard(
                      tierNumber: 3,
                      title: "Tier 3",
                      subtitle: "Full access with highest limits",
                      limit: _tier3Limit,
                      daily: _tier3Daily,
                      maxBalance: _tier3Max,
                      requirements: "Additional KYC details completed",
                      isCompleted: _tier3Completed,
                      canStart: _tier2Completed && !_tier3Completed,
                      previousTierCompleted: _tier2Completed,
                      primaryColor: Color(0xFF4F39F6),
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

  Widget _buildTierCard({
    required int tierNumber,
    required String title,
    required String subtitle,
    required String limit,
    required String daily,
    required String maxBalance,
    required String requirements,
    required bool isCompleted,
    required bool canStart,
    required bool previousTierCompleted,
    required Color primaryColor,
  }) {
    return Container(
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
                        title,
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
                          borderRadius: BorderRadius.circular(25),
                          color: primaryColor.withValues(alpha: 0.1),
                        ),
                        child: Text(
                          tierNumber == 1 ? "Popular" : "Tier $tierNumber",
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
                    subtitle,
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
                  tierNumber == 1 ? Icons.credit_card_outlined : Icons.shield_outlined,
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
                      color: Colors.black.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    limit,
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
                      color: Colors.black.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    daily,
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
                      color: Colors.black.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    maxBalance,
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
                        requirements,
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
              if (isCompleted) {
                return;
              }
              if (!previousTierCompleted) {
                showSnackBar(
                  context,
                  "Complete Tier ${tierNumber - 1} first",
                  primaryColor,
                );
                return;
              }
              navigateTo(context, UpgradeTier(tier: tierNumber));
            },
            child: Container(
              alignment: Alignment.center,
              width: MediaQuery.of(context).size.width * 0.9,
              padding: EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                color: isCompleted
                    ? Colors.grey
                    : canStart
                        ? primaryColor
                        : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isCompleted
                    ? "Completed"
                    : canStart
                        ? "Start $title"
                        : "Complete Tier ${tierNumber - 1} First",
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
    );
  }
}
