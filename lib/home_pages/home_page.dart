import 'package:card_app/airtimes/buy_airtime.dart';
import 'package:card_app/profile/choose_upgrade_tier.dart';
import 'package:card_app/bills/pay_bills.dart';
import 'package:card_app/cards/card_utils.dart';
import 'package:card_app/ghost_mode/ghost_mode.dart';
import 'package:card_app/giveaway/giveaway_page.dart';
import 'package:card_app/home_pages/card_page.dart';
import 'package:card_app/home_pages/required_documents_page.dart';
import 'package:card_app/home_pages/cashback_history_page.dart';
import 'package:card_app/home_pages/choose_payment_type.dart';
import 'package:card_app/home_pages/transactions_page.dart';
import 'package:card_app/loans/loan_page.dart';
import 'package:card_app/my_padi/my_padi_page.dart';
import 'package:card_app/notifications/notifications_page.dart';
import 'package:card_app/profile/profile_page.dart';
import 'package:card_app/top_up/top_up_wallet.dart';
import 'package:card_app/ui/bottom_nav_bar.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String? _userName;
  String? _accountName;
  String? _accountNumber;
  String? _tier;
  String _balance = "0.00";
  double _cashbackBalance = 0.0;
  bool _showBalance = true;
  bool _isLoadingBalance = false;
  String tag = "";
  List<Map<String, dynamic>> _requiredDocuments = [];
  bool _hasPendingDocuments = false;
  bool _hasRequiredDocuments = false;
  String? _kycStatus;
  String? _kycReason;
  bool _showKycBanner = false;
  bool _kycBannerIsDocs = false;
  bool _kycBannerButtonEnabled = false;
  String _kycBannerButtonText = "Submit Documents";
  String _kycBannerTitle = "";
  String _kycBannerBody = "";

  // Unread notifications
  int _unreadNotifCount = 0;
  StreamSubscription<QuerySnapshot>? _notifSub;

  // Recent transactions
  List<DocumentSnapshot> _recentTxSentDocs = [];
  List<DocumentSnapshot> _recentTxReceivedDocs = [];
  List<DocumentSnapshot> _recentCardTxDocs = [];
  StreamSubscription<QuerySnapshot>? _txSentSub;
  StreamSubscription<QuerySnapshot>? _txReceivedSub;
  StreamSubscription<QuerySnapshot>? _cardTxSub;
  bool _isLoadingTransactions = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _loadCachedBalance();
    _setupTransactionStreams();

    if (FirebaseAuth.instance.currentUser == null) {
      print(
        'HomePage init: user is not signed in yet; skipping auth-only setup',
      );
      _isLoadingTransactions = false;
      return;
    }

    saveToken();
    fetchAccount();
    createCardHolder();
    fundBridgeCardWallet();
    _setupNotifStream();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      createStroWalletUser();
      createSudoCustomer();
    });
  }

  @override
  void dispose() {
    _txSentSub?.cancel();
    _txReceivedSub?.cancel();
    _cardTxSub?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  void _setupNotifStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _notifSub?.cancel();
    _notifSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) setState(() => _unreadNotifCount = snap.docs.length);
          },
          onError: (e) {
            print('Notification stream error: $e');
            if (mounted) setState(() => _unreadNotifCount = 0);
          },
        );
  }

  void _setupTransactionStreams() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _txSentSub?.cancel();
    _txReceivedSub?.cancel();
    _cardTxSub?.cancel();
    _txSentSub = FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) {
              setState(() {
                _recentTxSentDocs = snap.docs;
                _isLoadingTransactions = false;
              });
            }
          },
          onError: (e) {
            print('Sent transactions stream error: $e');
            if (mounted) setState(() => _isLoadingTransactions = false);
          },
        );
    _txReceivedSub = FirebaseFirestore.instance
        .collection('transactions')
        .where('receiverId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) setState(() => _recentTxReceivedDocs = snap.docs);
          },
          onError: (e) {
            print('Received transactions stream error: $e');
          },
        );
    _cardTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) setState(() => _recentCardTxDocs = snap.docs);
          },
          onError: (e) {
            print('Card transactions stream error: $e');
          },
        );
  }

  List<DocumentSnapshot> _getMergedRecentTransactions({int limit = 5}) {
    final Map<String, DocumentSnapshot> seen = {};
    for (final doc in [
      ..._recentTxSentDocs,
      ..._recentTxReceivedDocs,
      ..._recentCardTxDocs,
    ]) {
      seen[doc.id] = doc;
    }
    const excludedTypes = {'card_created', 'card_failed'};
    final sorted =
        seen.values.where((doc) {
          final type =
              (doc.data() as Map<String, dynamic>)['type']?.toString() ?? '';
          return !excludedTypes.contains(type);
        }).toList()..sort((a, b) {
          final aDate = _txDocDate(a.data() as Map<String, dynamic>);
          final bDate = _txDocDate(b.data() as Map<String, dynamic>);
          return bDate.compareTo(aDate);
        });
    return sorted.take(limit).toList();
  }

  DateTime _txDocDate(Map<String, dynamic> data) {
    final dynamic ts =
        data['timestamp'] ??
        data['createdAtFirestore'] ??
        data['createdAt'] ??
        data['createdAtUtc'];
    if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  IconData _txIcon(String type, bool isOutgoing) {
    switch (type.toLowerCase()) {
      case 'transfer':
        return isOutgoing ? FontAwesomeIcons.paperPlane : Icons.arrow_downward;
      case 'airtime':
        return FontAwesomeIcons.phone;
      case 'data':
      case 'mobile_data':
        return FontAwesomeIcons.wifi;
      case 'electricity':
        return FontAwesomeIcons.bolt;
      case 'cable':
        return Icons.tv;
      case 'add_money':
      case 'fund':
      case 'deposit':
        return Icons.arrow_downward;
      case 'giveaway_claim':
      case 'giveaway_create':
        return FontAwesomeIcons.gift;
      case 'ghost_transfer':
        return FontAwesomeIcons.ghost;
      case 'card_debit':
        return Icons.credit_card;
      case 'card_declined':
        return Icons.credit_card;
      case 'card_refund':
        return Icons.undo;
      default:
        return FontAwesomeIcons.exchangeAlt;
    }
  }

  String _getStatus(Map<String, dynamic> data) {
    if (data['status'] != null) {
      return data['status'].toString().toLowerCase();
    }
    if (data['api_response']?['data']?['attributes']?['status'] != null) {
      return data['api_response']['data']['attributes']['status']
          .toString()
          .toLowerCase();
    }
    if (data['fullData']?['attributes']?['status'] != null) {
      return data['fullData']['attributes']['status'].toString().toLowerCase();
    }
    return 'unknown';
  }

  Color _getStatusColor(String status) {
    if (['success', 'completed', 'successful', 'approved'].contains(status)) {
      return Colors.green;
    } else if (['pending', 'to be paid'].contains(status)) {
      return Colors.orange;
    } else if (['failed', 'unsuccessful', 'declined'].contains(status)) {
      return Colors.red;
    } else if (status == 'reversed') {
      return Colors.grey;
    }
    return Colors.grey;
  }

  Future<void> createStroWalletUser() async {
    if (FirebaseAuth.instance.currentUser == null) {
      print('Skipping StroWallet user creation: no authenticated user');
      return;
    }
    try {
      await createStroWalletUserIfNeeded(context);
    } catch (e) {
      print('Error creating StroWallet user: $e');
    }
  }

  Future<void> createSudoCustomer() async {
    await createSudoCustomerIfNeeded();
  }

  Future<void> _loadCachedBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedBalance = prefs.getDouble('cached_balance') ?? 0.0;
    setState(() {
      _balance = '₦ ${NumberFormat('#,##0.00').format(cachedBalance)}';
    });
  }

  Future<void> fundBridgeCardWallet() async {
    await fundIssuingWallet();
  }

  Future<void> createCardHolder() async {
    try {
      await createBridgecardCardHolder();
    } catch (e) {
      print("Bridge cardholder creation error $e");
    }
  }

  Future<void> fetchAccount() async {
    await fetchCustomerAccount();
  }

  Future<void> saveToken() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      print('Skipping device token save: user not authenticated');
      return;
    }
    await saveUserDeviceToken(userId);
  }

  Future<void> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String? fetchedFirstName;
      String? fetchedLastName;
      String? fetchedTier;
      String? fetchedAccountName;
      String? fetchedAccountNumber;

      if (userSnap.exists) {
        var data = userSnap.data() as Map<String, dynamic>;
        fetchedFirstName = data['firstName'];
        fetchedLastName = data['lastName'];
        tag = data['userName'];
        final cashbackBalance =
            (data['cashback']?['balance'] as num?)?.toDouble() ?? 0.0;
        fetchedTier = (data['getAnchorData']?['tier'] ?? "0").toString();
        fetchedAccountName =
            data['getAnchorData']?['virtualAccount']?['data']?['attributes']?['accountName'];
        fetchedAccountNumber =
            data['getAnchorData']?['virtualAccount']?['data']?['attributes']?['accountNumber'];

        // Check for required documents
        final requiredDocs =
            (data['requiredDocuments'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
        final hasRequiredDocs = requiredDocs.isNotEmpty;
        final hasPending = requiredDocs.any(
          (doc) => (doc['status'] ?? '').toString().toLowerCase() == 'pending',
        );

        final kycStatusRaw = data['kycStatus']?.toString();
        final kycStatus = kycStatusRaw?.toUpperCase();
        final rejectionReason = data['kycRejectionReason']?.toString();
        final errorReason = data['kycErrorReason']?.toString();

        bool showBanner = false;
        bool bannerIsDocs = false;
        bool bannerButtonEnabled = false;
        String bannerButtonText = "Submit Documents";
        String bannerTitle = "Document Verification";
        String bannerBody = "Please submit the required documents to continue.";
        String? bannerReason;

        switch (kycStatus) {
          case 'APPROVED':
            showBanner = false;
            break;
          case 'AWAITING_DOCUMENT':
            showBanner = true;
            bannerIsDocs = true;
            bannerTitle = "Document Verification Required";
            bannerBody =
                "Please submit the required documents to complete verification.";
            bannerButtonEnabled = hasPending;
            bannerButtonText = "Submit Documents";
            break;
          case 'REENTER_INFORMATION':
            showBanner = true;
            bannerIsDocs = true;
            bannerTitle = "Re-upload Documents Required";
            bannerBody =
                "Your previous submission needs corrections. Please re-upload the required documents.";
            bannerButtonEnabled = hasPending;
            bannerButtonText = "Resubmit Documents";
            break;
          case 'REJECTED':
            showBanner = true;
            bannerIsDocs = false;
            bannerTitle = "KYC Rejected";
            bannerReason = rejectionReason;
            bannerBody = bannerReason?.isNotEmpty == true
                ? bannerReason!
                : "Your verification was rejected. Please contact support.";
            bannerButtonEnabled = false;
            break;
          case 'FAILED':
            showBanner = true;
            bannerIsDocs = false;
            bannerTitle = "KYC Failed";
            bannerReason = errorReason;
            bannerBody = bannerReason?.isNotEmpty == true
                ? bannerReason!
                : "Verification failed. Please try again or contact support.";
            bannerButtonEnabled = false;
            break;
          default:
            showBanner =
                hasRequiredDocs; // fallback to docs banner when present
            bannerIsDocs = hasRequiredDocs;
            bannerButtonEnabled = hasPending;
            bannerTitle = "Document Verification";
            bannerBody =
                "Please submit the required documents to complete verification.";
            break;
        }

        fetchAccountBalance();
        setState(() {
          _userName =
              fetchedAccountName ?? '$fetchedFirstName $fetchedLastName';
          _cashbackBalance = cashbackBalance;
          _accountName = fetchedAccountName;
          _accountNumber = fetchedAccountNumber;
          _tier = fetchedTier;
          _requiredDocuments = requiredDocs;
          _hasPendingDocuments = hasPending;
          _hasRequiredDocuments = hasRequiredDocs;
          _kycStatus = kycStatus;
          _kycReason = bannerReason;
          _showKycBanner = showBanner;
          _kycBannerIsDocs = bannerIsDocs;
          _kycBannerButtonEnabled = bannerButtonEnabled;
          _kycBannerButtonText = bannerButtonText;
          _kycBannerTitle = bannerTitle;
          _kycBannerBody = bannerBody;
        });

        // If a virtual account exists but bankId is missing, fetch it from fetchDepositAccount
        final accountId =
            data['getAnchorData']?['virtualAccount']?['data']?['id']
                ?.toString();
        final existingBankId =
            data['getAnchorData']?['virtualAccount']?['data']?['attributes']?['bank']?['id']
                ?.toString();
        final existingAccountNumber =
            data['getAnchorData']?['virtualAccount']?['data']?['attributes']?['accountNumber']
                ?.toString();
        final hasMaskedAccountNumber =
            existingAccountNumber != null &&
            existingAccountNumber.contains('*');
        if (accountId != null &&
            accountId.isNotEmpty &&
            ((existingBankId == null || existingBankId.isEmpty) ||
                hasMaskedAccountNumber)) {
          print(
            'Virtual account refresh required for accountId $accountId '
            '(bankIdMissing: ${existingBankId == null || existingBankId.isEmpty}, '
            'maskedAccountNumber: $hasMaskedAccountNumber)',
          );
          final userDocRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);
          _fetchAndUpdateVirtualAccount(accountId, userDocRef);
        }
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }
  }

  Future<double> fetchAccountBalance() async {
    setState(() {
      _isLoadingBalance = true;
    });

    try {
      // Get the current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No authenticated user');
      }

      // Fetch user document from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      // Extract accountId from getAnchorData.virtualAccount.data.id
      final data = userDoc.data()!;
      final anchorData = data['getAnchorData'] as Map<String, dynamic>?;
      if (anchorData == null) {
        throw Exception('Anchor data not found');
      }

      final virtualAccount =
          anchorData['virtualAccount'] as Map<String, dynamic>?;
      if (virtualAccount == null) {
        // Try to fetch customer info if we have a customer id
        final customerId = anchorData['customerCreation']?['data']?['id']
            ?.toString();
        if (customerId != null && customerId.isNotEmpty) {
          try {
            print(
              'Virtual account missing; calling fetchCustomer for customerId: $customerId',
            );
            final callable = FirebaseFunctions.instance.httpsCallable(
              'fetchCustomerVirtualAccount',
            );
            final resp = await callable.call({'customerId': customerId});
            final pretty = const JsonEncoder.withIndent(
              '  ',
            ).convert(resp.data);
            print('fetchCustomer response for $customerId:');
            print(pretty);
          } catch (e) {
            print('fetchCustomer call failed for $customerId: $e');
          }
        } else {
          print(
            'Virtual account missing and no customerId available in getAnchorData',
          );
        }

        throw Exception('Virtual account data not found');
      }

      final accountData = virtualAccount['data'] as Map<String, dynamic>?;
      if (accountData == null) {
        throw Exception('Account data not found');
      }

      final accountId = accountData['id']?.toString();
      if (accountId == null || accountId.isEmpty) {
        throw Exception('Account ID not found');
      }

      // Call the Cloud Function with the accountId
      final callable = FirebaseFunctions.instance.httpsCallable(
        'fetchAccountBalance',
      );
      final result = await callable.call({'accountId': accountId});

      var balance = result.data['data']['availableBalance']?.toDouble() ?? 0.0;
      balance /= 100;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_balance', balance);
      setState(() {
        _balance = '₦ ${NumberFormat('#,##0.00').format(balance)}';
        _isLoadingBalance = false;
      });

      return balance;
    } catch (e) {
      // Handle errors appropriately
      print('Error fetching account balance: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_balance', 0.0);
      setState(() {
        _isLoadingBalance = false;
        _balance = "0.00";
      });
      return 0.0;
    }
  }

  // Fetch authoritative bank.id via fetchDepositAccount (only field we need from it),
  // and real unmasked accountNumber + bankName via fetchAccountNumber { accountNumber, bank: string }.
  Future<void> _fetchAndUpdateVirtualAccount(
    String accountId,
    DocumentReference userDocRef,
  ) async {
    try {
      // ── Step 1: fetchDepositAccount → bank.id only ──────────────────────────
      print('Calling fetchDepositAccount for accountId: $accountId');
      final depositResult = await FirebaseFunctions.instance
          .httpsCallable('fetchDepositAccount')
          .call({'accountId': accountId});
      print('fetchDepositAccount response: ${depositResult.data}');

      final depositResp = depositResult.data;
      final depositData = (depositResp is Map)
          ? depositResp['data'] as Map?
          : null;
      final depositAttrs = depositData?['attributes'] as Map?;
      final depositBank = depositAttrs?['bank'] as Map?;
      final String? bankId = depositBank?['id']?.toString();

      print('fetchDepositAccount parsed — bankId: $bankId');

      if (bankId == null) {
        print(
          'fetchDepositAccount: bank.id is null — continuing to try fetchAccountNumber',
        );
      }

      // ── Step 2: fetchAccountNumber → real accountNumber + bankName ────────
      String? accountNumber;
      String? bankName;
      try {
        print('Calling fetchAccountNumber for accountId: $accountId');
        final numResult = await FirebaseFunctions.instance
            .httpsCallable('fetchAccountNumber')
            .call({'accountId': accountId});
        print('fetchAccountNumber response: ${numResult.data}');

        final numResp = numResult.data;
        if (numResp is Map) {
          accountNumber = numResp['accountNumber']?.toString();
          // bank is returned as a plain string (bankName)
          final rawBank = numResp['bank'];
          bankName = rawBank is String ? rawBank : rawBank?.toString();
        }
        print(
          'fetchAccountNumber parsed — accountNumber: $accountNumber, bankName: $bankName',
        );
      } catch (e) {
        print('fetchAccountNumber failed (non-fatal): $e');
      }

      // ── Step 3: Persist to Firestore ────────────────────────────────────────
      final updates = <String, dynamic>{};
      if (bankId != null) {
        updates['getAnchorData.virtualAccount.data.attributes.bank'] = {
          'id': bankId,
          if (bankName != null) 'name': bankName,
        };
      }
      if (accountNumber != null) {
        updates['getAnchorData.virtualAccount.data.attributes.accountNumber'] =
            accountNumber;
      }

      if (updates.isEmpty) {
        print('No bank/accountNumber updates available to persist');
        return;
      }

      await userDocRef.update(updates);
      print('Persisted to Firestore: $updates');
      if (mounted) {
        setState(() {
          if (accountNumber != null) _accountNumber = accountNumber;
        });
      }
    } catch (e) {
      print('Error in _fetchAndUpdateVirtualAccount: $e');
    }
  }

  String get _displayAccountNumber {
    return _accountNumber ?? "****";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 0.0),
          child: SizedBox.expand(
            child: Stack(
              children: [
                _buildBody(),
                Positioned(
                  top: 15,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white30,
                            radius: 25,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white30,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            padding: EdgeInsets.all(2),
                            child: Badge(
                              isLabelVisible: _unreadNotifCount > 0,
                              label: Text(
                                _unreadNotifCount > 99
                                    ? '99+'
                                    : '$_unreadNotifCount',
                                style: TextStyle(fontSize: 10),
                              ),
                              child: IconButton(
                                color: Colors.white30,
                                onPressed: () {
                                  navigateTo(context, NotificationsPage());
                                },
                                icon: Icon(
                                  Icons.notifications_outlined,
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
                Positioned(
                  bottom: 25,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: BottomNavBar(
                      currentIndex: _selectedIndex,
                      onTap: (index) {
                        if (index == 0) {
                          setState(() => _selectedIndex = index);
                          return;
                        }
                        // if (_tier == "0" && index != 3) {
                        //   showToast(
                        //     "Please upgrade your account to access this feature.",
                        //     Colors.red,
                        //   );
                        //   return;
                        // }
                        if (index == 1) {
                          navigateTo(
                            context,
                            CardsPage(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 2) {
                          navigateTo(
                            context,
                            TransactionsPage(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 3) {
                          navigateTo(
                            context,
                            ProfilePage(),
                            type: NavigationType.push,
                          );
                        } else {
                          setState(() => _selectedIndex = index);
                        }
                      },
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

  Widget _buildBody() {
    return RefreshIndicator(
      displacement: 100,
      color: primaryColor,
      onRefresh: _fetchUserData,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 90),
            Text(
              "Welcome, ${_accountName ?? ''}! 😃",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 0.0, top: 10),
              child: Text(
                "Ready to manage\nyour finances?",
                style: TextStyle(
                  fontSize: 21,
                  color: Colors.black.withAlpha(220),
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 0.1),
                      blurRadius: 1,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 22),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: "Account Number    ",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              TextSpan(
                                text: "|    $_displayAccountNumber",
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 15),
                      GestureDetector(
                        onTap: () {
                          // if (_tier == "0" || _accountNumber == null) {
                          //   showToast(
                          //     "Please upgrade your account to access this feature.",
                          //     Colors.red,
                          //   );
                          //   return;
                          // }
                          Clipboard.setData(
                            ClipboardData(text: _accountNumber!),
                          );
                        },
                        child: Icon(Icons.copy, color: Colors.white, size: 18),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: "Padi-Tag  |  ",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              TextSpan(
                                text: "@$tag",
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 15),
                      GestureDetector(
                        onTap: () {
                          // if (_tier == "0" || _accountNumber == null) {
                          //   showToast(
                          //     "Please upgrade your account to access this feature.",
                          //     Colors.red,
                          //   );
                          //   return;
                          // }
                          Clipboard.setData(ClipboardData(text: tag));
                        },
                        child: Icon(Icons.copy, color: Colors.white, size: 18),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  Text(
                    "Account Balance",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _isLoadingBalance
                          ? SizedBox(
                              height: 25,
                              width: 25,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _showBalance ? _balance : "****",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: _isLoadingBalance ? 15 : 24,
                                color: Colors.white,
                              ),
                            ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _showBalance = !_showBalance),
                        child: Container(
                          padding: EdgeInsets.all(10),
                          margin: EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _showBalance
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      navigateTo(
                        context,
                        CashbackHistoryPage(initialBalance: _cashbackBalance),
                        type: NavigationType.push,
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.savings_outlined,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _showBalance
                                  ? 'Cashback Balance: ₦ ${NumberFormat('#,##0.00').format(_cashbackBalance)}'
                                  : 'Cashback Balance: ****',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      if (_tier == "0") {
                        showSimpleDialog(
                          "Please upgrade your account to access this feature.",
                          Colors.red,
                        );
                        return;
                      }
                      navigateTo(context, TopUpWallet());
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "Add Money",
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: 13,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(50),
                      bottomRight: Radius.circular(50),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: MediaQuery.of(context).size.width * 0.7,
                  height: 11,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.075),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(50),
                      bottomRight: Radius.circular(50),
                    ),
                  ),
                ),
              ],
            ),
            if (_showKycBanner)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      width: 1,
                      color: _kycBannerIsDocs
                          ? Colors.orange.shade200
                          : Colors.red.shade200,
                    ),
                    color: _kycBannerIsDocs
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _kycBannerIsDocs
                              ? Colors.orange.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                        ),
                        child: Icon(
                          _kycBannerIsDocs
                              ? Icons.assignment_outlined
                              : Icons.error_outline,
                          color: _kycBannerIsDocs ? Colors.orange : Colors.red,
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _kycBannerTitle,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              _kycBannerBody,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                            if (_kycBannerIsDocs) ...[
                              SizedBox(height: 15),
                              InkWell(
                                onTap: !_kycBannerButtonEnabled
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                RequiredDocumentsPage(
                                                  requiredDocuments:
                                                      _requiredDocuments,
                                                ),
                                          ),
                                        );
                                        _fetchUserData();
                                      },
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_kycBannerButtonEnabled
                                        ? Colors.orange.shade200
                                        : Colors.orange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _kycBannerButtonText,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_tier == "0")
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(width: 1, color: Colors.grey.shade200),
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: primaryColor.withValues(alpha: 0.1),
                        ),
                        child: Icon(
                          Icons.trending_up,
                          color: primaryColor,
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Upgrade Your Account",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 5),
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.6,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "Increase your transaction limits and unlock premium features.",
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 15),
                          InkWell(
                            onTap: () => navigateTo(
                              context,
                              ChooseUpgradeTier(tier: _tier ?? "0"),
                            ),
                            child: Container(
                              alignment: AlignmentGeometry.center,
                              width: MediaQuery.of(context).size.width * 0.6,
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "Upgrade Now",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(height: 30),
            ActionGrid(tier: _tier),
            const SizedBox(height: 20),
            _buildRecentTransactionsSection(),
            const SizedBox(height: 150),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactionsSection() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final recentDocs = _getMergedRecentTransactions(limit: 5);

    // Build 5 most recent unique recipients for the "Recents" row
    final List<Map<String, dynamic>> recentRecipients = [];
    final Set<String> seenRecipientKeys = {};
    for (final doc in _getMergedRecentTransactions(limit: 50)) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString().toLowerCase() ?? '';
      if (type != 'transfer' && type != 'ghost_transfer') continue;
      final isOutgoing = data['userId'] == uid || data['actualSender'] == uid;
      if (!isOutgoing) continue;
      final recipientName =
          data['recipientName']?.toString() ??
          data['account_number']?.toString() ??
          'Unknown';
      final key =
          data['account_number']?.toString() ??
          data['receiverId']?.toString() ??
          recipientName;
      if (seenRecipientKeys.contains(key)) continue;
      seenRecipientKeys.add(key);
      recentRecipients.add(data);
      if (recentRecipients.length >= 5) break;
    }

    final bool hasData = recentDocs.isNotEmpty || recentRecipients.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Transaction History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            GestureDetector(
              onTap: () => navigateTo(
                context,
                TransactionsPage(),
                type: NavigationType.push,
              ),
              child: Text(
                'See All',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ),
          ],
        ),

        // Recents row (horizontal avatars of recent transfer recipients)
        if (recentRecipients.isNotEmpty) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: recentRecipients.length,
              itemBuilder: (context, index) {
                final r = recentRecipients[index];
                final name = r['recipientName']?.toString() ?? 'Unknown';
                final initials = name.trim().isEmpty
                    ? '?'
                    : name
                          .trim()
                          .split(' ')
                          .where((s) => s.isNotEmpty)
                          .take(2)
                          .map((s) => s[0].toUpperCase())
                          .join();
                return GestureDetector(
                  onTap: () => navigateTo(
                    context,
                    TransactionsPage(),
                    type: NavigationType.push,
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: primaryColor.withValues(alpha: 0.15),
                          child: Text(
                            initials,
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 52,
                          child: Text(
                            name.split(' ').first,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
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
        ],

        const SizedBox(height: 14),

        // Last 5 transactions list
        if (_isLoadingTransactions)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: CircularProgressIndicator(
              color: primaryColor,
              strokeWidth: 2,
            ),
          )
        else if (recentDocs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(
                  'No transactions yet',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentDocs.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (context, index) {
              final doc = recentDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final type = data['type']?.toString().toLowerCase() ?? '';
              final bool isOutgoing =
                  type != 'transfer' && type != 'ghost_transfer'
                  ? true
                  : (data['userId'] == uid || data['actualSender'] == uid);
              final otherId = isOutgoing
                  ? (data['receiverId'] ?? '')
                  : (data['userId'] ?? '');

              Color bgColor = const Color(0xFFE3F2FD);
              Color iconColor = const Color(0xFF1565C0);
              Offset offset = Offset.zero;
              if (type == 'transfer') {
                bgColor = isOutgoing
                    ? const Color(0xFFF3E5F5)
                    : const Color(0xFFE8F5E9);
                iconColor = isOutgoing
                    ? const Color(0xFF7B1FA2)
                    : const Color(0xFF2E7D32);
                if (isOutgoing) offset = const Offset(-2, 2);
              } else if (type.contains('ghost')) {
                bgColor = const Color(0xFFECEFF1);
                iconColor = const Color(0xFF37474F);
              } else if (type.contains('giveaway')) {
                bgColor = const Color(0xFFFFF8E1);
                iconColor = const Color(0xFFFF6F00);
              } else if (type == 'deposit' ||
                  type == 'fund' ||
                  type == 'add_money') {
                bgColor = const Color(0xFFE8F5E9);
                iconColor = const Color(0xFF2E7D32);
              } else if (type == 'card_debit') {
                bgColor = const Color(0xFFFFF3E0);
                iconColor = const Color(0xFFE65100);
              } else if (type == 'card_declined') {
                bgColor = const Color(0xFFFFEBEE);
                iconColor = const Color(0xFFC62828);
              } else if (type == 'card_refund') {
                bgColor = const Color(0xFFE8F5E9);
                iconColor = const Color(0xFF2E7D32);
              }

              final isCardTx =
                  type == 'card_debit' ||
                  type == 'card_declined' ||
                  type == 'card_refund';
              final amountSign = type == 'card_refund'
                  ? '+'
                  : type == 'card_declined'
                  ? '' // declined = no debit occurred
                  : (!isOutgoing ||
                        type == 'deposit' ||
                        type == 'giveaway_claim' ||
                        type == 'add_money' ||
                        type == 'fund')
                  ? '+'
                  : '-';
              final amountValue =
                  ((data['amount'] as num?) ??
                  (data['debitAmount'] as num?) ??
                  0);
              final formattedAmount = NumberFormat(
                '#,##0.00',
              ).format(amountValue);

              final date = _txDocDate(data);
              final formattedTime = DateFormat('HH:mm').format(date);
              final formattedDate = DateFormat('MMM d, yyyy').format(date);

              final name = isCardTx
                  ? (data['merchant'] ?? 'Card Transaction')
                  : data['recipientName'] ??
                        data['phoneNumber'] ??
                        data['meterNumber'] ??
                        data['smartcard_number'] ??
                        data['account_number'] ??
                        'Unknown';

              final reference =
                  data['reference']?.toString() ??
                  (data['api_response']?['data']?['attributes']?['reference']
                      as String?) ??
                  (data['transactionId'] as String?) ??
                  '';

              final status = _getStatus(data);
              final Color statusColor;
              if (type == 'card_debit' || type == 'card_refund') {
                statusColor = Colors.green;
              } else if (type == 'card_declined') {
                statusColor = Colors.red;
              } else {
                statusColor = _getStatusColor(status);
              }
              final Color amountColor = isCardTx
                  ? (type == 'card_refund'
                        ? Colors.green
                        : type == 'card_declined'
                        ? Colors.grey.shade600
                        : Colors.red)
                  : statusColor;
              final statusDisplay = isCardTx
                  ? (type == 'card_debit'
                        ? 'Successful'
                        : type == 'card_declined'
                        ? 'Declined'
                        : 'Refunded')
                  : status.replaceAll('_', ' ').isNotEmpty
                  ? status.replaceAll('_', ' ')[0].toUpperCase() +
                        status.replaceAll('_', ' ').substring(1)
                  : status;

              return Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: TransactionItem(
                  docId: doc.id,
                  icon: _txIcon(type, isOutgoing),
                  otherId: otherId.toString(),
                  amount: '$amountSign₦$formattedAmount',
                  amountColor: amountColor,
                  formattedTime: formattedTime,
                  formattedDate: formattedDate,
                  status: statusDisplay,
                  statusColor: statusColor,
                  isOutgoing: isOutgoing,
                  otherName: name.toString(),
                  type: type,
                  reference: reference,
                  bgColor: bgColor,
                  iconColor: iconColor,
                  offset: offset,
                  cardData: isCardTx ? data : null,
                ),
              );
            },
          ),
      ],
    );
  }
}

void _showChooseTransferTypeBottomSheet(BuildContext context) {
  showModalBottomSheet<String?>(
    context: context,
    builder: (context) => ChooseTransferTypeBottomSheet(),
    isScrollControlled: true,
  );
}

class ActionGrid extends StatelessWidget {
  final String? tier;

  const ActionGrid({super.key, this.tier});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> actions = [
      {
        'title': 'Transfer',
        'subtitle': 'Send money to any Nigerian bank',
        'icon': "assets/icon-park-outline_send.png",
        'color': const Color(0xFF5B9EFF),
        'circle': const Color(0xFF1558E0),
        'borderColor': const Color(0xFF2979FF),
      },
      {
        'title': 'Give-Away',
        'subtitle': 'Send or receive cash gifts instantly',
        'icon': "assets/streamline-plump_give-gift.png",
        'color': const Color(0xFFFF6B6B),
        'circle': const Color(0xFFD32F2F),
        'borderColor': const Color(0xFFE53935),
      },
      {
        'title': 'Ghost Mode',
        'subtitle': 'Send money anonymously',
        'icon': "assets/hugeicons_anonymous.png",
        'color': const Color(0xFF90A4AE),
        'circle': const Color(0xFF37474F),
        'borderColor': const Color(0xFF546E7A),
      },
      {
        'title': 'Pay your Bills',
        'subtitle': 'Pay for your TV Bills, electricity, e.t.c',
        'icon': "assets/mi_document.png",
        'color': const Color(0xFF7C83FF),
        'circle': const Color(0xFF283593),
        'borderColor': const Color(0xFF3D5AFE),
      },
      {
        'title': 'Buy Airtime',
        'subtitle': 'Buy airtime with just a few steps',
        'icon': "assets/gridicons_phone.png",
        'color': const Color(0xFFFF6DD4),
        'circle': const Color(0xFF880E4F),
        'borderColor': const Color(0xFFAD1457),
      },
      {
        'title': 'MyPadi',
        'subtitle': 'Perform financial tasks easily',
        'icon': "assets/padi_ai.png",
        'color': const Color(0xFFB56EFF),
        'circle': const Color(0xFF4A148C),
        'borderColor': const Color(0xFF6A1ED6),
      },
      // {
      //   'title': 'Loan',
      //   'subtitle': 'Get quick cash loans',
      //   'icon': "assets/streamline-cyber_cash-bag-give.png",
      //   'color': const Color(0xFFACFFD5),
      //   'circle': const Color(0xFF00A300),
      //   'borderColor': const Color(0xFF64CDAC),
      // },
    ];

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 0.9,
      physics: const NeverScrollableScrollPhysics(),
      children: actions.map((item) {
        return InkWell(
          onTap: () {
            if (tier == "0") {
              showSimpleDialog(
                "Please upgrade your account to access this feature.",
                Colors.red,
              );
              return;
            }
            switch (item['title']) {
              case 'Transfer':
                _showChooseTransferTypeBottomSheet(context);
                break;
              case 'Ghost Mode':
                navigateTo(context, GhostModeTransfer());
                break;
              case "Buy Airtime":
                navigateTo(context, BuyAirtimePage());
                break;
              case "Pay your Bills":
                navigateTo(context, PayBillsPage());
                break;
              case "Loan":
                navigateTo(context, LoanPage());
                break;
              case "Give-Away":
                navigateTo(context, GiveAwayPage());
                break;
              case "MyPadi":
                navigateTo(context, const MyPadiPage());
                break;
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: item['color'],
                border: Border.all(color: item['borderColor'], width: 1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        alignment: Alignment.center,
                        margin: const EdgeInsets.only(left: 11),
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Image.asset(item['icon'], width: 20, height: 20),
                      ),
                      Transform.translate(
                        offset: const Offset(25, -25),
                        child: Container(
                          height: 95,
                          width: 95,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (item['circle'] as Color).withValues(
                              alpha: .6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Padding(
                    padding: const EdgeInsets.only(left: 11.0, bottom: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'],
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          item['subtitle'],
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black38,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
