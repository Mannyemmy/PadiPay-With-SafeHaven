import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  late Future<Map<String, dynamic>> _referralDataFuture;

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  void _loadReferralData() {
    final String uid = FirebaseAuth.instance.currentUser!.uid;
    _referralDataFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .then((doc) async {
      if (!doc.exists) {
        return {
          'referralCode': 'unknown',
          'referralCount': 0,
          'referrals': <DocumentSnapshot>[],
          'bonusPerReferral': 500.0,
          'minTransactionAmount': 0.0,
          'totalEarned': 0.0,
        };
      }
      final data = doc.data()!;
      final String username =
          (data['userName'] ?? 'unknown').toString().toUpperCase();
      final List<dynamic> referralUids = data['referrals'] ?? [];

      List<DocumentSnapshot> referralDocs = [];
      if (referralUids.isNotEmpty) {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: referralUids)
            .get();
        referralDocs = query.docs;
      }

      // Fetch referral settings from Firestore
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('referrals')
          .get();
      final settingsData = settingsDoc.data() ?? {};
      final double bonusPerReferral =
          ((settingsData['bonusPerReferral'] ?? 500) as num).toDouble();
      final double minTransactionAmount =
          ((settingsData['minTransactionAmount'] ?? 0) as num).toDouble();

      // Use stored custom earnings if set by admin, otherwise calculate
      final customEarnings = data['customReferralEarnings'];
      final double totalEarned = customEarnings != null
          ? (customEarnings as num).toDouble()
          : referralUids.length * bonusPerReferral;

      return {
        'referralCode': username,
        'referralCount': referralUids.length,
        'referrals': referralDocs,
        'bonusPerReferral': bonusPerReferral,
        'minTransactionAmount': minTransactionAmount,
        'totalEarned': totalEarned,
      };
    });
  }

  void _copyReferralCode(String code) {
    Clipboard.setData(ClipboardData(text: code.toLowerCase()));
    showSimpleDialog("Referral code copied!", Colors.green);
  }

  Future<void> _shareReferralLink(String code) async {
    final String lowerCode = code.toLowerCase();
    final String message =
         "Hey! Join me on PadiPay app using my referral code: $lowerCode.\n Download the app here https://play.google.com/store/apps/details?id=com.allgoodtech.padi_pay";
    await Share.share(message);
  }

  Future<void> _showPermissionExplanation(String code) async {
    final bool? shouldProceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PermissionExplanationBottomSheet(),
    );

    if (shouldProceed != true) {
      return; // User declined
    }

    // User agreed, now request permission
    final PermissionStatus status = await Permission.contacts.request();

    if (!status.isGranted) {
      showSimpleDialog("Contacts permission denied", Colors.red);
      return;
    }

    await _proceedWithContactInvitation(code);
  }

  Future<void> _proceedWithContactInvitation(String code) async {
    final String lowerCode = code.toLowerCase();

    try {
      final List<Contact> contacts =
          await FlutterContacts.getContacts(withProperties: true);

      if (contacts.isEmpty) {
        showSimpleDialog("No contacts found", Colors.orange);
        return;
      }

      final List<Contact>? selected = await showDialog<List<Contact>>(
        context: context,
        builder: (context) => ContactSelectionDialog(contacts: contacts),
      );

      if (selected == null || selected.isEmpty) {
        return;
      }

      final String message =
          "Hey! Join me on PadiPay app using my referral code: $lowerCode.\n Download the app here https://play.google.com/store/apps/details?id=com.allgoodtech.padi_pay";

      await Share.share(
        message,
        subject: "Invitation to join the app",
      );
    } catch (e) {
      showSimpleDialog("Error accessing contacts", Colors.red);
    }
  }

  Future<void> _inviteContacts(String code) async {
    final String lowerCode = code.toLowerCase();

    // First check current permission status
    final PermissionStatus status = await Permission.contacts.status;

    if (status.isGranted) {
      await _proceedWithContactInvitation(lowerCode);
    } else if (status.isDenied || status.isRestricted) {
      // Show explanation bottom sheet before requesting
      await _showPermissionExplanation(lowerCode);
    } else if (status.isPermanentlyDenied) {
      // Permanently denied - guide to settings
      showSimpleDialog("Please enable contacts permission in Settings", Colors.orange);
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black45,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Text(
                    "Referrals",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              FutureBuilder<Map<String, dynamic>>(
                future: _referralDataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  final data = snapshot.data ??
                      {
                        'referralCount': 0,
                        'referralCode': 'LOADING',
                        'referrals': [],
                        'bonusPerReferral': 500.0,
                        'minTransactionAmount': 0.0,
                        'totalEarned': 0.0,
                      };
                  final int totalReferrals = data['referralCount'] ?? 0;
                  final int activeReferrals = totalReferrals;
                  final double bonusPerReferral =
                      (data['bonusPerReferral'] ?? 500.0) as double;
                  final double minTransactionAmount =
                      (data['minTransactionAmount'] ?? 0.0) as double;
                  final double totalEarned =
                      (data['totalEarned'] ?? 0.0) as double;

                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: primaryColor.withValues(alpha: 0.07),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    Text(
                                      '$totalReferrals',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: primaryColor,
                                      ),
                                    ),
                                    Text(
                                      'Total Referrals',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Color(0xFFDD00FF).withValues(alpha: 0.07),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    Text(
                                      '$activeReferrals',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDD00FF),
                                      ),
                                    ),
                                    Text(
                                      'Active Users',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFDD00FF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: 16, horizontal: 10.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.share_outlined,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Your Referral Code',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        border: Border.all(
                                            color: Colors.grey.shade50),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        data['referralCode'] ?? 'LOADING',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      border: Border.all(
                                          color: Colors.grey.shade50),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        FontAwesomeIcons.copy,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () => _copyReferralCode(
                                          data['referralCode'] ?? ''),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _shareReferralLink(
                                          data['referralCode'] ?? ''),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColor,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.share_outlined,
                                              size: 17,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              "Share Link",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _inviteContacts(
                                          data['referralCode'] ?? ''),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColor,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              FontAwesomeIcons.gift,
                                              size: 17,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              "Invite Contacts",
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              // Referral requirements info
                              Container(
                                padding: EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        size: 16, color: primaryColor),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        minTransactionAmount > 0
                                            ? 'Earn ₦${bonusPerReferral.toStringAsFixed(0)} per referral who transacts at least ₦${minTransactionAmount.toStringAsFixed(0)}'
                                            : 'Earn ₦${bonusPerReferral.toStringAsFixed(0)} per referral',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                             
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 30),
                      Text(
                        "Your Referrals ($totalReferrals)",
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 10),
                      if (data['referrals'] != null &&
                          (data['referrals'] as List).isEmpty)
                        Center(
                          child: Text(
                            "No referrals yet",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          itemCount:
                              (data['referrals'] as List<DocumentSnapshot>)
                                  .length,
                          itemBuilder: (context, index) {
                            final refDoc = (data['referrals']
                                as List<DocumentSnapshot>)[index];
                            final refData =
                                refDoc.data() as Map<String, dynamic>;
                            final String name =
                                "${refData['firstName'] ?? ''} ${refData['lastName'] ?? ''}"
                                    .trim();
                            final String username =
                                refData['userName'] ?? 'unknown';

                            return ListTile(
                              leading: CircleAvatar(
                                child:
                                    Text(username[0].toUpperCase()),
                              ),
                              title: Text(name.isEmpty ? username : name),
                              subtitle: Text('@$username'),
                              trailing:
                                  Icon(Icons.check_circle, color: Colors.green),
                            );
                          },
                        ),
                      SizedBox(height: 16),
                      _buildEarningsSummary(bonusPerReferral, minTransactionAmount, totalEarned),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEarningsSummary(
    double bonusPerReferral,
    double minTransactionAmount,
    double totalEarned,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade100),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 15),
                Text(
                  'Earnings Summary',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                Transform.translate(
                  offset: Offset(2, -2),
                  child: Image.asset(
                    "assets/arrow.png",
                    width: MediaQuery.of(context).size.width * 0.2,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Total Earned',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Text(
                      '₦${totalEarned.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Per Referral',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Text(
                      '₦${bonusPerReferral.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            if (minTransactionAmount > 0)
              Container(
                margin: EdgeInsets.all(16),
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Text(
                      'Min. Transaction Required',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryColor.withValues(alpha: 0.6),
                      ),
                    ),
                    Spacer(),
                    Text(
                      '₦${minTransactionAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PermissionExplanationBottomSheet extends StatelessWidget {
  const PermissionExplanationBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(24),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 60,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          SizedBox(height: 30),
          Text(
            "Access to Contacts",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          Text(
            "We need access to your contacts so you can easily invite your friends to join the app using your referral code.",
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "• Select multiple contacts at once\n• Send invitation via SMS, WhatsApp, or any messaging app\n• No contact information is stored or shared",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    "Continue",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
        ],
        ),
      ),
    );
  }
}

class ContactSelectionDialog extends StatefulWidget {
  final List<Contact> contacts;

  const ContactSelectionDialog({super.key, required this.contacts});

  @override
  State<ContactSelectionDialog> createState() => _ContactSelectionDialogState();
}

class _ContactSelectionDialogState extends State<ContactSelectionDialog> {
  final Set<Contact> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select Contacts to Invite"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: widget.contacts.length,
          itemBuilder: (context, index) {
            final contact = widget.contacts[index];
            final bool hasPhone = contact.phones.isNotEmpty;
            final String displayName = contact.displayName ?? 'No Name';

            return CheckboxListTile(
              title: Text(displayName),
              subtitle: hasPhone
                  ? Text(contact.phones.first.number)
                  : Text("No phone number"),
              value: _selected.contains(contact),
              onChanged: hasPhone
                  ? (val) {
                      setState(() {
                        if (val == true) {
                          _selected.add(contact);
                        } else {
                          _selected.remove(contact);
                        }
                      });
                    }
                  : null,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: Text("Invite (${_selected.length})"),
        ),
      ],
    );
  }
}