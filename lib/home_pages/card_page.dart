// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import, unused_local_variable

import 'dart:math' as math;

import 'package:card_app/cards/card_design.dart';
import 'package:card_app/cards/sudo_card_service.dart';
import 'package:card_app/home_pages/choose_payment_type.dart';
import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/home_pages/transactions_page.dart';
import 'package:card_app/profile/profile_page.dart';
import 'package:card_app/ui/bottom_nav_bar.dart';
import 'package:card_app/ui/bottom_sheets.dart';
import 'package:card_app/ui/keypad.dart';
import 'package:card_app/ui/receipt_page.dart';
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({super.key});
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  List<Map<String, dynamic>> _cards = [];
  String _currentCategory = 'NGN';
  final PageController _pageController = PageController();
  bool _isLoading = true;
  double _balance = 0.0;
  double _usdFundingRequiredNGN = 0.0;
  int _currentCardPage = 0;
  String? _currentCardId;

  void _logCardCreate(String step, [Object? data]) {
    if (data == null) {
      print('[CARD_CREATE] $step');
      return;
    }
    print('[CARD_CREATE] $step: $data');
  }

  Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return null;
  }

  String? _extractCardId(dynamic responseData) {
    final payload = _asStringKeyedMap(responseData);
    final data = _asStringKeyedMap(payload?['data']);
    final nestedCard = _asStringKeyedMap(data?['card']);
    final rootCard = _asStringKeyedMap(payload?['card']);

    return data?['card_id']?.toString() ??
        nestedCard?['card_id']?.toString() ??
        rootCard?['card_id']?.toString() ??
        payload?['card_id']?.toString() ??
        data?['_id']?.toString() ??
        nestedCard?['_id']?.toString() ??
        rootCard?['_id']?.toString() ??
        payload?['_id']?.toString() ??
        data?['id']?.toString() ??
        nestedCard?['id']?.toString() ??
        rootCard?['id']?.toString() ??
        payload?['id']?.toString();
  }

  String _extractCallableError(dynamic responseData) {
    final payload = _asStringKeyedMap(responseData);
    final data = _asStringKeyedMap(payload?['data']);
    final error = _asStringKeyedMap(payload?['error']);

    final message = payload?['message']?.toString();
    final errorMessage = error?['message']?.toString();
    final dataMessage = data?['message']?.toString();
    final details = payload?['details']?.toString();

    return message ??
        errorMessage ??
        dataMessage ??
        details ??
        'Unexpected create card response: $responseData';
  }

  String _normalizePhysicalBrand(String? rawBrand) {
    final normalized = (rawBrand ?? '').trim().toLowerCase();
    if (normalized.contains('afrigo')) return 'AfriGo';
    if (normalized.contains('verve')) return 'Verve';
    return 'Verve';
  }

  Future<Map<String, dynamic>> _reservePhysicalInventoryCard({
    required String userId,
    required String brand,
  }) async {
    final normalizedBrand = _normalizePhysicalBrand(brand);
    _logCardCreate('physical inventory reserve start', {
      'userId': userId,
      'brand': normalizedBrand,
    });
    final inventoryQuery = await FirebaseFirestore.instance
        .collection('physical_card_inventory')
        .where('brand', isEqualTo: normalizedBrand)
        .where('status', isEqualTo: 'unassigned')
        .limit(1)
        .get();

    if (inventoryQuery.docs.isEmpty) {
      _logCardCreate('physical inventory reserve none available', {
        'brand': normalizedBrand,
      });
      throw Exception('No unassigned $normalizedBrand physical card is available right now.');
    }

    final selectedDoc = inventoryQuery.docs.first;
    final selectedData = selectedDoc.data();
    final cardNumber = selectedData['cardNumber']?.toString() ?? '';
    if (cardNumber.isEmpty) {
      _logCardCreate('physical inventory missing card number', {
        'inventoryCardDocId': selectedDoc.id,
      });
      throw Exception('Selected physical card inventory record has no card number.');
    }

    final now = DateTime.now();
    final etaDate = now.add(const Duration(days: 14)).toIso8601String();

    final tracking = <String, dynamic>{
      'status': 'pending',
      'note': 'Order confirmed. Card is being prepared.',
      'etaDate': etaDate,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await selectedDoc.reference.update({
      'status': 'assigned',
      'assignedUserId': userId,
      'assignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'tracking': tracking,
    });

    _logCardCreate('physical inventory reserved', {
      'inventoryCardDocId': selectedDoc.id,
      'brand': normalizedBrand,
      'last4': cardNumber.length >= 4 ? cardNumber.substring(cardNumber.length - 4) : cardNumber,
      'etaDate': etaDate,
    });

    return {
      'inventoryCardDocId': selectedDoc.id,
      'assignedPhysicalCardNumber': cardNumber,
      'physicalCardTracking': {
        'status': 'pending',
        'note': 'Order confirmed. Card is being prepared.',
        'etaDate': etaDate,
      },
      'physicalCardDelivered': false,
    };
  }

  Future<Map<String, dynamic>> getCurrentAccountIdAndType() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return {
        'accountId': null,
        'accountType': null,
        'bankId': null,
        'accountNumber': null,
        'bankName': null,
        'accountName': null,
      };
    }
    final DocumentSnapshot<Map<String, dynamic>> userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (userSnap.exists && userSnap.data() != null) {
      final data = userSnap.data()!;
      final Map<String, dynamic>? virtualAccData =
          data['safehavenData']?['virtualAccount']?['data']
              as Map<String, dynamic>?;

      if (virtualAccData != null && virtualAccData['id'] != null) {
        final bankMap =
            virtualAccData['attributes']?['bank'] as Map<String, dynamic>?;
        final String? bankId = bankMap?['id']?.toString();
        final String? accountNumber =
            virtualAccData['attributes']?['accountNumber']?.toString();
        final String? bankName = bankMap?['name']?.toString();
        final String? accountName = data['fullName'] ?? '';

        return {
          'accountId': virtualAccData['id'] as String,
          'accountType': virtualAccData['type'] as String?,
          'bankId': bankId,
          'accountNumber': accountNumber,
          'bankName': bankName,
          'accountName': accountName,
        };
      }
    }

    return {
      'accountId': null,
      'accountType': null,
      'bankId': null,
      'accountNumber': null,
      'bankName': null,
      'accountName': null,
    };
  }

  Widget _shimmerPlaceholder({required double width, double height = 16.0}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
      );

  @override
  void initState() {
    super.initState();
    _fetchCards();
    _fetchBalanceAndFx();
  }

  Future<void> _fetchBalanceAndFx() async {
    try {
      double balance = await _fetchBalance();
      double? rate;
      final companySnap = await FirebaseFirestore.instance
          .collection('company')
          .doc('sudoAccountDetails')
          .get();
      final companyData = companySnap.data();
      final rawRate = companyData?['usdNgnRate'];
      if (rawRate is num && rawRate > 0) {
        rate = rawRate.toDouble();
      } else if (rawRate is String) {
        final parsed = double.tryParse(rawRate);
        if (parsed != null && parsed > 0) {
          rate = parsed;
        }
      }
      if (rate == null) {
        rate = 0;
      }
      double required = 3 * rate;
      setState(() {
        _balance = balance;
        _usdFundingRequiredNGN = required;
      });
    } catch (e) {
      print('Error fetching balance and FX: $e');
    }
  }

  Future<double> _fetchBalance() async {
    try {
      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];

      if (accountId == null) throw Exception('Account ID not found');

      final callable = FirebaseFunctions.instance.httpsCallable(
        'safehavenFetchAccountBalance',
      );
      final result = await callable.call({'accountId': accountId});

      var balance = result.data['data']['availableBalance']?.toDouble() ?? 0.0;
      balance /= 100;

      return balance;
    } catch (e) {
      print('Error fetching account balance: $e');
      throw Exception('Failed to fetch account balance: $e');
    }
  }

  Future<Map<String, dynamic>> _fetchCardDetails(String cardId, String currency, {String? provider, String? sudoAccountId}) async {
    // Detect Sudo cards: 24-char hex Mongo ObjectID, or explicit provider field
    final isSudo = provider == 'sudo' ||
        RegExp(r'^[0-9a-f]{24}$', caseSensitive: false).hasMatch(cardId);
    print('[_fetchCardDetails] cardId=$cardId currency=$currency isSudo=$isSudo sudoAccountId=$sudoAccountId');
    print('[_fetchCardDetails] cardId=$cardId currency=$currency isSudo=$isSudo sudoAccountId=$sudoAccountId');

    if (isSudo || currency == 'USD') {
      // Sudo path â€” both NGN and new USD Sudo cards
      final callable = FirebaseFunctions.instance.httpsCallable('sudoGetCard');
      final response = await callable.call({'cardId': cardId});
      print('Sudo card details response for $cardId: ${response.data}');

      final rawData = _asStringKeyedMap(response.data);
      final data = _asStringKeyedMap(rawData?['data']) ?? <String, dynamic>{};

      // maskedPan format: "506321*********0824" â€” extract last 4
      final String maskedPan = data['maskedPan']?.toString() ?? '';
      final String last4 = maskedPan.length >= 4
          ? maskedPan.substring(maskedPan.length - 4)
          : '';

      final String displayNumber = maskedPan.isNotEmpty
          ? maskedPan.replaceAll('*', '0')
          : '0000000000000000';

      // Card holder name from customer object
      final customerRaw = data['customer'];
      String cardName = '';
      if (customerRaw is Map) {
        final customer = Map<String, dynamic>.from(customerRaw);
        cardName = customer['name']?.toString() ?? '';
        if (cardName.isEmpty) {
          final individual = customer['individual'] as Map?;
          final first = individual?['firstName']?.toString() ?? '';
          final last = individual?['lastName']?.toString() ?? '';
          cardName = '$first $last'.trim();
        }
      }

      // Fetch real-time balance from Sudo account balance endpoint
      double availableBalance = 0.0;
      try {
        // Try sudoAccountId passed from Firestore card doc first,
        // then fall back to the account field on the card response (String ID or embedded Map)
        final accountRaw = data['account'];
        final String? accountIdFromCard = (accountRaw is Map)
            ? accountRaw['_id']?.toString()
            : (accountRaw is String && accountRaw.isNotEmpty ? accountRaw : null);
        final String? resolvedAccountId = sudoAccountId ?? accountIdFromCard;
        print('[_fetchCardDetails] resolvedAccountId=$resolvedAccountId (fromFirestore=$sudoAccountId, fromCard=$accountIdFromCard)');
        if (resolvedAccountId != null && resolvedAccountId.isNotEmpty) {
          final balCallable = FirebaseFunctions.instance
              .httpsCallable('sudoGetAccountBalance');
          final balResult = await balCallable.call({'accountId': resolvedAccountId});
          print('[_fetchCardDetails] balance raw response: ${balResult.data}');
          final balData = _asStringKeyedMap(
              _asStringKeyedMap(balResult.data)?['data']);
          final rawBal = (balData?['availableBalance'] as num?)?.toDouble() ?? 0.0;
          // Sudo returns balance in minor units (kobo for NGN, cents for USD)
          availableBalance = rawBal / 100;
          print('[_fetchCardDetails] resolved balance=$availableBalance $currency');
        } else {
          print('[_fetchCardDetails] WARNING: no accountId found for $cardId, balance will be 0');
        }
      } catch (e) {
        print('[_fetchCardDetails] Error fetching Sudo account balance for card $cardId: $e');
      }

      return {
        'card_number': displayNumber,
        'last_4': last4,
        'masked_pan': maskedPan,
        'card_name': cardName,
        'expiry_month': data['expiryMonth']?.toString() ?? 'MM',
        'expiry_year': data['expiryYear']?.toString() ?? 'YY',
        'available_balance': availableBalance,
        'brand': data['brand']?.toString() ?? 'Verve',
        'cvv': data['cvv']?.toString() ?? data['cvv2']?.toString() ?? '',
        'status': data['status']?.toString() ?? '',
      };
    }

    throw Exception('Unsupported card provider');
  }

 Future<void> _fetchCards() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    if (mounted) setState(() => _isLoading = false);
    return;
  }

  // Prioritize business cards

  QuerySnapshot<Map<String, dynamic>> cardsSnap;

  // Fallback to personal
  cardsSnap = await FirebaseFirestore.instance
      .collection('users/${user.uid}/cards')
      .get();

  List<Map<String, dynamic>> cards = [];
  for (QueryDocumentSnapshot doc in cardsSnap.docs) {
    final Map<String, dynamic> docData = doc.data() as Map<String, dynamic>;
   
    
    // Skip docs with null type or selectedCurrency
    if (docData['type'] == null || docData['selectedCurrency'] == null) {
      continue;
    }

    // Skip terminated/deleted cards
    if (docData['deleted'] == true) continue;

    final Map<String, dynamic> card = {
      ...docData,
      'id': doc.id,
      'details': null,
    };
    cards.add(card);
  }

  // Deduplicate cards by card_id; keep only pending cards (no card_id); discard failed cards from UI
  Map<String, Map<String, dynamic>> uniqueCardsMap = {};
  List<Map<String, dynamic>> pendingCards = [];
  for (var card in cards) {
    final String? cardId = card['card_id']?.toString();
    if (cardId == null) {
      final status = card['status']?.toString();
      if (status == 'pending') pendingCards.add(card);
      // failed cards are silently dropped from UI (user already notified via push)
    } else if (!uniqueCardsMap.containsKey(cardId)) {
      uniqueCardsMap[cardId] = card;
    }
  }
  cards = [...uniqueCardsMap.values, ...pendingCards];

  // Sort most recent first
  cards.sort((a, b) {
    final aTime = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
    final bTime = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });

  // Initialize showNumber to true for all cards
  for (var card in cards) {
    card['showNumber'] = true;
  }
   

  if (mounted) {
    setState(() {
      _cards = cards;
      _isLoading = false;
      // Set current card ID for the transaction stream (first card in current category)
      final filtered = cards.where((c) => _getCardCurrency(c) == _currentCategory).toList();
      if (filtered.isNotEmpty) {
        _currentCardPage = 0;
        _currentCardId = filtered[0]['card_id']?.toString();
      }
    });
  }

  // DEBUG: fetch and print the full Sudo customer object on page load
  try {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final sudoRaw = userDoc.data()?['sudoCustomer'];
    final safehavenData = (sudoRaw is Map) ? sudoRaw['data'] : null;
    final debugCustomerId = (safehavenData is Map) ? safehavenData['_id']?.toString() : null;
    if (debugCustomerId != null) {
      final debugResult = await FirebaseFunctions.instance
          .httpsCallable('sudoGetCustomer')
          .call({'customerId': debugCustomerId});
      print('[DEBUG] Sudo customer full data: ${debugResult.data}');
    } else {
      print('[DEBUG] No sudoCustomerId found in Firestore user doc');
    }
  } catch (e) {
    print('[DEBUG] sudoGetCustomer error in _fetchCards: $e');
  }

  for (var card in cards) {
    final cardId = card['card_id'] as String?;
    final cardCurrency = _getCardCurrency(card);
    if (cardId == null) continue;

    _fetchCardDetails(
      cardId,
      cardCurrency,
      provider: card['provider']?.toString(),
      sudoAccountId: card['sudoAccountId']?.toString(),
    ).then((details) {
          print(
            'Fetched details for $cardId: success (keys: ${details.keys.toList()}), balance: ${details["available_balance"]}',
          );
          if (mounted) {
            setState(() {
              card['details'] = details;
            });
          }
        })
        .catchError((e) {
          print('Error fetching details for card $cardId: $e');
          if (mounted) {
            setState(() {
              card['details'] = {};
            });
          }
        });
  }
}
  String _getCardCurrency(Map<String, dynamic> card) {
    final dynamic selectedCurrencyRaw = card['selectedCurrency'];
    String selectedCurrency = 'NGN';
    if (selectedCurrencyRaw != null) {
      selectedCurrency = selectedCurrencyRaw.toString();
    }
  
    // Extract currency code from parentheses if present, or check for USD/NGN keywords
    RegExp codeRegex = RegExp(r'\(([A-Z]{3})\)');
    Match? match = codeRegex.firstMatch(selectedCurrency.toUpperCase());
    if (match != null) {
      final code = match.group(1)!;
      return code;
    } else if (selectedCurrency.toUpperCase().contains('USD')) {
      return 'USD';
    } else if (selectedCurrency.toUpperCase().contains('NGN')) {
      return 'NGN';
    } else {
      return 'NGN'; // Default fallback
    }
  }

  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: InkWell(
        onTap: _startCardCreation,
        child: Container(
          margin: EdgeInsets.only(bottom: 120),
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor,
          ),
          child: Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: SizedBox.expand(
          child: Stack(
            children: [
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: primaryColor),
                )
              else
                RefreshIndicator(
                  color: primaryColor,
                  onRefresh: _fetchCards,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 20),
                        Row(
                          children: [
                            SizedBox(width: 15),
                            Text(
                              "My Cards",
                              style: TextStyle(
                                fontSize: 22,
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildCategoryChip('NGN', primaryColor),
                                  _buildCategoryChip('USD', Colors.green),
                                ],
                              ),
                            ),
                          ],
                        ),

                        _buildCardsView(),
                        _buildCardTransactions(),
                        const SizedBox(height: 80),
                      ],
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
                        navigateTo(
                          context,
                          HomePage(),
                          type: NavigationType.push,
                        );
                      }

                      if (index == 2) {
                        navigateTo(
                          context,
                          TransactionsPage(),
                          type: NavigationType.clearStack,
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
    );
  }

  Widget _buildCategoryChip(String category, Color color) {
    bool isSelected = _currentCategory == category;
    int count = _cards
        .where((card) => _getCardCurrency(card) == category)
        .length;
    return GestureDetector(
      onTap: () {
        final filtered = _cards.where((c) => _getCardCurrency(c) == category).toList();
        setState(() {
          _currentCategory = category;
          _currentCardPage = 0;
          _currentCardId = filtered.isNotEmpty ? filtered[0]['card_id']?.toString() : null;
        });
        _pageController.jumpToPage(0);
      },
      child: Container(
        margin: EdgeInsets.only(left: 10),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            Text(
              category,
              style: TextStyle(color: isSelected ? Colors.white : Colors.black),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCardTransactionDetail(BuildContext context, Map<String, dynamic> data, String displayAmount, String prefix) {
    final type = data['type']?.toString() ?? '';
    final merchant = data['merchant']?.toString() ?? 'Unknown';
    final channel = data['channel']?.toString() ?? '';
    final reference = data['reference']?.toString() ?? '';
    final currency = data['currency']?.toString() ?? 'NGN';
    final status = data['status']?.toString() ?? (type == 'card_declined' ? 'declined' : 'approved');
    final ts = data['timestamp'] as Timestamp?;
    final date = ts != null ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()) : '';

    final isDeclined = type == 'card_declined' || status == 'declined';
    final isRefund = type == 'card_refund';
    final statusLabel = isDeclined ? 'Declined' : isRefund ? 'Refunded' : 'Successful';
    final statusColor = isDeclined ? Colors.red : isRefund ? Colors.blue : Colors.green;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Text('$prefix$displayAmount',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
            const SizedBox(height: 20),
            _detailRow('Merchant', merchant),
            if (channel.isNotEmpty) _detailRow('Channel', channel.toUpperCase()),
            _detailRow('Currency', currency),
            if (date.isNotEmpty) _detailRow('Date', date),
            if (reference.isNotEmpty) _detailRow('Reference', reference),
            if (data['reason'] != null) _detailRow('Reason', data['reason'].toString()),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildCardTransactions() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentCardId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('transactions')
          .where('cardId', isEqualTo: _currentCardId)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Card Transactions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final type = data['type']?.toString() ?? '';
                final currency = data['currency']?.toString() ?? 'NGN';
                final amount = (data['amount'] as num?)?.toDouble() ?? 0;
                final merchant = data['merchant']?.toString() ?? 'Unknown';
                final ts = data['timestamp'] as Timestamp?;
                final date = ts != null
                    ? DateFormat('dd MMM, HH:mm').format(ts.toDate())
                    : '';

                final isDebit = type == 'card_debit';
                final isRefund = type == 'card_refund';
                final isDeclined = type == 'card_declined';

                final displayAmount = currency == 'NGN'
                    ? '₦${NumberFormat('#,##0.00').format(amount)}'
                    : '\$${amount.toStringAsFixed(2)}';

                final icon = isRefund
                    ? Icons.undo
                    : Icons.credit_card;
                final iconColor = isDeclined
                    ? Colors.red
                    : isRefund
                        ? Colors.green
                        : Colors.orange;
                final amountColor = isDeclined
                    ? Colors.red
                    : isRefund
                        ? Colors.green
                        : Colors.black87;
                final prefix = isRefund ? '+' : isDeclined ? '' : '-';

                return GestureDetector(
                  onTap: () => navigateTo(
                    context,
                    ReceiptPage(
                      reference: data['reference']?.toString() ?? '',
                      cardData: data,
                    ),
                    type: NavigationType.push,
                  ),
                  child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade100, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: iconColor.withOpacity(0.15),
                        child: Icon(icon, color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              merchant,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            if (date.isNotEmpty)
                              Row(
                                children: [
                                  Icon(Icons.access_time, color: Colors.grey.shade500, size: 13),
                                  const SizedBox(width: 4),
                                  Text(date, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$prefix$displayAmount',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: amountColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isDeclined ? 'Declined' : isRefund ? 'Refunded' : 'Successful',
                            style: TextStyle(
                              color: iconColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardsView() {
    List<Map<String, dynamic>> filtered = _cards
        .where((card) => _getCardCurrency(card) == _currentCategory)
        .toList();

    if (filtered.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              Text(
                "No Cards Yet.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text("Create your first card to get started."),
              const SizedBox(height: 50),
              GestureDetector(
                onTap: _startCardCreation,
                child: DottedBorder(
                  options: CircularDottedBorderOptions(
                    color: Colors.grey,
                    strokeWidth: 2,
                    dashPattern: const [15, 3],
                    padding: EdgeInsets.zero,
                  ),
                  child: Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                    child: const Icon(Icons.add, size: 30, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 760,
          child: PageView.builder(
            controller: _pageController,
            itemCount: filtered.length,
            onPageChanged: (index) {
              setState(() {
                _currentCardPage = index;
                _currentCardId = filtered[index]['card_id']?.toString();
              });
            },
            itemBuilder: (context, index) {
              var card = filtered[index];
              var details = (card['details'] as Map?)?.cast<String, dynamic>();
              bool isLoadingDetails = details == null || details.isEmpty;

              final double cardWidth = MediaQuery.of(context).size.width * 0.85;

              String currencyCode = _getCardCurrency(card);

              String financialType = card['cardFinancialType'] ?? 'Debit';
              final String cardFormFactor = (card['type']?.toString() ?? 'Virtual');
              // Normalize to title-case for display
              final String formFactorLabel = cardFormFactor[0].toUpperCase() + cardFormFactor.substring(1).toLowerCase();

              final String brandStr =
                  (details?['brand'] ?? card['scheme'] ?? 'Visa')
                      .toString()
                      .toLowerCase();

              // Resolve card design template
              final String designId = card['design']?.toString() ?? '';
              CardTemplate? cardTemplate = getTemplateById(designId);
              // Backward compat: map legacy design names to first template for brand
              final String brandLabel = brandStr.contains('master') ? 'MasterCard'
                  : brandStr.contains('verve') ? 'Verve'
                  : brandStr.contains('afrigo') ? 'AfriGo'
                  : 'Visa';
              if (cardTemplate == null) {
                final templates = getTemplatesForCard(brandLabel, currencyCode);
                cardTemplate = templates.first;
              }
              final int? savedColorValue = card['colorOverride'] as int?;
              final Color? savedColorOverride = savedColorValue != null
                  ? Color(savedColorValue)
                  : null;

              // For NGN Sudo cards use maskedPan to derive last4 + display number
              final String maskedPan = details?['masked_pan']?.toString() ?? '';
              final String last4 = details?['last_4']?.toString() ??
                  (maskedPan.length >= 4
                      ? maskedPan.substring(maskedPan.length - 4)
                      : 'â€¢â€¢â€¢â€¢');
              String cardTypeStr = '$financialType | **** $last4';

              // Build display number: â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ XXXX from masked pan
              String displayedNumber;
              if (isLoadingDetails) {
                displayedNumber = 'â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢';
              } else if (!(card['showNumber'] ?? true)) {
                displayedNumber = 'â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢';
              } else if (maskedPan.isNotEmpty && currencyCode == 'NGN') {
                // Sudo maskedPan is like "506321*********0824"
                displayedNumber = 'â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ â€¢â€¢â€¢â€¢ $last4';
              } else {
                final String rawNumber =
                    (details['card_number'] ?? '0000000000000000').toString();
                displayedNumber = rawNumber
                    .replaceAllMapped(
                      RegExp(r'.{4}'),
                      (match) => '${match.group(0)} ',
                    )
                    .trim();
              }

              String cardName =
                  details?['card_name'] ?? card['nameOnCard'] ?? 'JOHN DOE';
              String displayedCardName = isLoadingDetails
                  ? 'CARD HOLDER'
                  : (cardFormFactor.toLowerCase() == 'anonymous' ? 'PadiPay' : cardName);

              String expiryMonth = (details?['expiry_month'] ?? 'MM')
                  .toString()
                  .padLeft(2, '0');
              String expiryYear = (details?['expiry_year'] ?? 'YY').toString();
              String expiry =
                  '$expiryMonth/${expiryYear.substring(expiryYear.length - 2)}';
              String displayedExpiry = isLoadingDetails ? 'MM/YY' : expiry;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      children: [
                        isLoadingDetails
                            ? _shimmerPlaceholder(width: 180, height: 18)
                            : Text(
                                cardTypeStr,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cardFormFactor.toLowerCase() == 'physical'
                                ? Colors.blue.shade50
                                : cardFormFactor.toLowerCase() == 'anonymous'
                                    ? Colors.purple.shade50
                                    : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: cardFormFactor.toLowerCase() == 'physical'
                                  ? Colors.blue.shade200
                                  : cardFormFactor.toLowerCase() == 'anonymous'
                                      ? Colors.purple.shade200
                                      : Colors.green.shade200,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                cardFormFactor.toLowerCase() == 'physical'
                                    ? Icons.credit_card
                                    : cardFormFactor.toLowerCase() == 'anonymous'
                                        ? Icons.visibility_off_outlined
                                        : Icons.cloud_outlined,
                                size: 12,
                                color: cardFormFactor.toLowerCase() == 'physical'
                                    ? Colors.blue.shade700
                                    : cardFormFactor.toLowerCase() == 'anonymous'
                                        ? Colors.purple.shade700
                                        : Colors.green.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                formFactorLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cardFormFactor.toLowerCase() == 'physical'
                                      ? Colors.blue.shade700
                                      : cardFormFactor.toLowerCase() == 'anonymous'
                                          ? Colors.purple.shade700
                                          : Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      final cardStatus = card['status']?.toString();
                      if (cardStatus == 'pending' || cardStatus == 'failed') return;
                      _showPinForCard(card);
                    },
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Stack(
                          children: [
                            Center(
                              child: PadiCardWidget(
                                template: cardTemplate,
                                brand: brandLabel,
                                currency: currencyCode,
                                cardHolder: displayedCardName,
                                cardNumber: displayedNumber,
                                expiry: displayedExpiry,
                                cardType: formFactorLabel,
                                isLoading: isLoadingDetails,
                                colorOverride: savedColorOverride,
                                width: cardWidth,
                              ),
                            ),
                            if (card['status']?.toString() == 'pending' ||
                                card['status']?.toString() == 'failed' ||
                                card['status']?.toString() == 'terminated')
                              Positioned.fill(
                                child: Center(
                                  child: Container(
                                    width: cardWidth,
                                    height: cardWidth * 0.63,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.65),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (card['status'] == 'pending') ...[
                                          const CircularProgressIndicator(color: Colors.white),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Creating your card...',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            "We'll notify you when it's ready",
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                        ] else if (card['status'] == 'terminated') ...[
                                          const Icon(Icons.block, color: Colors.orangeAccent, size: 40),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Card Terminated',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'This card has been terminated',
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                        ] else ...[
                                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Card creation failed',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Please try again',
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          height: 15,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(50),
                              bottomRight: Radius.circular(50),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              );
            },
          ),
        ),
      ],
    );
  }  void _showPinForCard(Map<String, dynamic> card) async {
    final cardPin = card['pin']?.toString();
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EnterPasscodeSheetForTransaction(),
    );
    if (result == null) return;
    if (result == 'BIOMETRIC_SUCCESS' || result == cardPin) {
      _showCardDetails(card);
    } else {
      showSimpleDialog("Incorrect PIN", Colors.red);
    }
  }

  void _showChoosePaymentTypeBottomSheet(Map<String, dynamic> card) {
    showModalBottomSheet<String?>(
      context: context,
      builder: (context) => ChoosePaymentTypeBottomSheet(card: card),
      isScrollControlled: true,
    );
  }

  void _showCardDetails(Map<String, dynamic> card) {
    List<Map<String, dynamic>> filtered = _cards
        .where((c) => _getCardCurrency(c) == _currentCategory)
        .toList();
    int index = filtered.indexWhere((c) => c['id'] == card['id']);
    showModalBottomSheet(
      context: context,
      builder: (context) => CardDetailsBottomSheet(
        cards: filtered,
        initialIndex: index,
        selectedCurrency: _getCardCurrency(card),
      ),
      isScrollControlled: true,
    );
  }

  void _startCardCreation() {
    showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const CardTypeBottomSheet(),
      isScrollControlled: true,
    ).then((type) {
      if (type == null) return;
      if (type == 'Map') {
        _mapPhysicalCard();
        return;
      }
      // if (type != "Virtual") {
      //   showSimpleDialog("$type card is unavailable at the moment", Colors.red);
      //   return;
      // }
      showModalBottomSheet<Map<String, dynamic>?>(
        context: context,
        builder: (context) => BasicDetailsBottomSheet(cardType: type),
        isScrollControlled: true,
      ).then((basicData) {
        if (basicData == null) return;
        showModalBottomSheet<Map<String, dynamic>?>(
          context: context,
          builder: (context) => CustomizeCardBottomSheet(
            scheme: basicData['selectedScheme'] ?? basicData['scheme'] ?? 'Visa',
            currency: (basicData['selectedCurrency'] ?? 'NGN').toString().toUpperCase().contains('USD') ? 'USD' : 'NGN',
            cardType: type,
            nameOnCard: basicData['nameOnCard'] ?? 'CARD HOLDER',
          ),
          isScrollControlled: true,
        ).then((designResult) {
          if (designResult == null) return;
          final String design = designResult['templateId'] as String? ?? '';
          final int? colorValue = designResult['colorOverride'] as int?;
          showModalBottomSheet<bool?>(
            context: context,
            builder: (context) => ReviewConfirmBottomSheet(
              cardType: type,
              basicData: basicData,
              selectedDesign: design,
              selectedCurrency: basicData["selectedCurrency"],
              selectedScheme: basicData["selectedScheme"],
              colorOverride: colorValue,
            ),
            isScrollControlled: true,
          ).then((confirm) {
            if (confirm == true) {
              _createCard(type, basicData, design, colorOverride: colorValue);
            }
          });
        });
      });
    });
  }

  Future<void> _mapPhysicalCard() async {
    final TextEditingController cardIdController = TextEditingController();

    final String? cardId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Map Physical Card',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your existing Sudo card ID to digitalize it.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cardIdController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Card ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, cardIdController.text.trim());
                },
                child: const Text('Map Card'),
              ),
            ),
          ],
        ),
      ),
    );

    if (cardId == null || cardId.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: primaryColor)),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sudoDigitalizeCard',
      );
      final response = await callable.call({'cardId': cardId});
      final responseData = _asStringKeyedMap(response.data) ??
          {'raw': response.data};
      print('Map physical card response: $responseData');

      if (!mounted) return;
      Navigator.pop(context);
      showSimpleDialog('Card mapped successfully', Colors.green);
      _fetchCards();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showSimpleDialog('Card mapping failed: $e', Colors.red);
      print('Error mapping physical card: $e');
    } finally {
      cardIdController.dispose();
    }
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('company').doc('account_details').get();
      if (!doc.exists) return null;
      final data = doc.data() ?? <String, dynamic>{};
      return {
        'uid': doc.id,
        'id': data['accountId']?.toString() ?? '',
        'type': data['accountType']?.toString() ?? '',
        'bankId': data['bankId']?.toString() ?? '',
        'bankName': data['bankName']?.toString() ?? '',
        'accountNumber': data['accountNumber']?.toString() ?? '',
        'accountName': data['accountName']?.toString() ?? '',
      };
    } catch (e) {
      print('getCompanyVirtualAccount error: $e');
      return null;
    }
  }

  Future<bool> _refundToUser(
    Map<String, dynamic> userDetails,
    Map<String, dynamic> companyVa,
    double amountNGN,
  ) async {
    try {
      final String? userAccountId = userDetails['accountId'];
      if (userAccountId == null || userAccountId.isEmpty) {
        print('Refund skipped: Missing user accountId');
        return false;
      }

      // Refund: company â†’ user (book transfer â€” both on Sudo)
      final refundResult = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
            'fromAccountId': companyVa['id'],
            'toAccountId': userAccountId,
            'amount': (amountNGN * 100).toInt(),
            'currency': 'NGN',
            'narration': 'Refund for failed card creation/funding',
            'idempotencyKey': const Uuid().v4(),
          });

      if (refundResult.data['data']['attributes']['status'] == 'FAILED') {
        print('Refund transfer failed: ${refundResult.data['message']}');
        return false;
      }
      return true;
    } catch (e) {
      print('Refund error: $e');
      return false;
    }
  }

  Future<void> _createCard(
    String type,
    Map<String, dynamic> basicData,
    String design, {
    int? colorOverride,
  }) async {
    _logCardCreate('start', {
      'type': type,
      'design': design,
      'basicDataKeys': basicData.keys.toList(),
      'selectedCurrency': basicData['selectedCurrency'],
      'scheme': basicData['scheme'],
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: primaryColor)),
    );
    bool funded = false;
    double amountNGN = 0.0;
    Map<String, dynamic>? userDetails;
    Map<String, dynamic>? companyVa;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'User not logged in';
      _logCardCreate('current user', user.uid);

      userDetails = await getCurrentAccountIdAndType();
      final String? accountId = userDetails['accountId'];
      final String? accountType = userDetails['accountType'];
      final String? bankId = userDetails['bankId'];
      _logCardCreate('resolved funding account', {
        'accountId': accountId,
        'accountType': accountType,
        'bankId': bankId,
        'accountNumber': userDetails['accountNumber'],
        'bankName': userDetails['bankName'],
      });

      if (accountId == null || accountType == null || bankId == null) {
        final missing = [
          if (accountId == null) 'accountId',
          if (accountType == null) 'accountType',
          if (bankId == null) 'bankId',
        ].join(', ');
        print('Card creation blocked â€” missing fields: $missing | userDetails: $userDetails');
        Navigator.pop(context);
        showSimpleDialog("Please create a bank account first", Colors.red);
        return;
      }

      Map<String, dynamic>? userData;

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      userData = userSnap.data();
      _logCardCreate('user document loaded', {
        'exists': userSnap.exists,
        'keys': userData?.keys.toList(),
      });

      String? pin = await showModalBottomSheet<String?>(
        context: context,
        builder: (context) => const EnterPinBottomSheet(
          title: 'Create Card PIN',
          description: 'Enter a 4-digit PIN to secure your card',
        ),
        isScrollControlled: true,
      );

      if (pin == null) {
        Navigator.pop(context);
        return;
      }

      String cardCurrency =
          basicData['selectedCurrency'].toString().toUpperCase().contains('USD')
          ? 'USD'
          : 'NGN';
      _logCardCreate('derived currency', cardCurrency);

      // Both NGN and USD cards now go through Sudo
      // Resolve Sudo customer
      String? sudoCustomerId;
      final sudoCustomerRaw = _asStringKeyedMap(userData?['sudoCustomer']);
      final sudoCustomerData = _asStringKeyedMap(sudoCustomerRaw?['data']);
      sudoCustomerId = sudoCustomerData?['_id']?.toString() ??
          sudoCustomerRaw?['_id']?.toString();
      _logCardCreate('sudo customer from profile', {'id': sudoCustomerId});

      // Fetch company settlement account id for this currency
      _logCardCreate('fetching company settlement account', cardCurrency);
      final String? sudoDebitAccountId = await sudoGetSettlementAccountId(cardCurrency);
      _logCardCreate('sudo settlement account', {'id': sudoDebitAccountId});
      if (sudoDebitAccountId == null) {
        throw Exception('Could not resolve company settlement account for $cardCurrency');
      }

      // Anonymous cards use company Sudo customer; skip individual customer setup entirely
      if (type != 'Anonymous' && sudoCustomerId == null) {
        final String firstName = userData?['firstName']?.toString() ?? '';
        final String lastName = userData?['lastName']?.toString() ?? '';
        final String phone = userData?['phone']?.toString() ?? '';
        final String email = userData?['email']?.toString() ?? '';
        final String bvn = userData?['bvn']?.toString() ?? '';
        final String dob = userData?['dateOfBirth']?.toString() ?? '';
        final addressRaw = _asStringKeyedMap(userData?['address']);

        _logCardCreate('creating sudo customer', user.uid);
        final createCustomerCallable = FirebaseFunctions.instance
            .httpsCallable('sudoCreateCustomer');
        final customerResponse = await createCustomerCallable.call({
          'type': 'individual',
          'name': '$firstName $lastName'.trim(),
          'phoneNumber': phone,
          'status': 'active',
          'emailAddress': email,
          'billingAddress': {
            'line1': addressRaw?['street']?.toString() ?? '',
            'city': addressRaw?['city']?.toString() ?? '',
            'state': addressRaw?['state']?.toString() ?? '',
            'country': addressRaw?['country']?.toString() ?? 'NG',
            'postalCode': addressRaw?['postalCode']?.toString() ?? '',
          },
          'individual': {
            'firstName': firstName,
            'lastName': lastName,
            if (bvn.isNotEmpty && dob.isNotEmpty)
              'identity': {
                'type': 'BVN',
                'number': bvn,
              },
            if (dob.isNotEmpty)
              'dob': dob,
          },
        });
        print('[SUDO] sudoCreateCustomer response: ${customerResponse.data}');
        _logCardCreate('sudo create customer response', customerResponse.data);

        final customerRaw = _asStringKeyedMap(customerResponse.data);
        final customerDataMap = _asStringKeyedMap(customerRaw?['data']);
        sudoCustomerId = customerDataMap?['_id']?.toString();

        if (sudoCustomerId == null) {
          throw Exception('Failed to create Sudo customer: no _id in response');
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'sudoCustomer': customerResponse.data});
        _logCardCreate('sudo customer saved to firestore', sudoCustomerId);
      }

      // DEBUG: fetch and print the full Sudo customer object so we can see what's missing
      try {
        final debugResult = await FirebaseFunctions.instance
            .httpsCallable('sudoGetCustomer')
            .call({'customerId': sudoCustomerId});
        print('[DEBUG] Sudo customer full data: ${debugResult.data}');
      } catch (e) {
        print('[DEBUG] sudoGetCustomer fetch error: $e');
      }


      // Save a pending card immediately so it shows in the UI
      final pendingCardData = <String, dynamic>{
        'type': type,
        'scheme': basicData['scheme'],
        'nameOnCard': type == 'Anonymous' ? 'PadiPay' : basicData['nameOnCard'],
        'selectedCurrency': basicData['selectedCurrency'],
        'design': design,
        if (colorOverride != null) 'colorOverride': colorOverride,
        'status': 'pending',
        'pin': pin,
        'createdAt': FieldValue.serverTimestamp(),
      };

      Map<String, dynamic>? reservedInventory;
      if (type == 'Physical') {
        reservedInventory = await _reservePhysicalInventoryCard(
          userId: user.uid,
          brand: (basicData['scheme'] ?? basicData['selectedScheme'] ?? 'Verve')
              .toString(),
        );
        pendingCardData.addAll(reservedInventory);
        pendingCardData['shippingAddress'] = basicData['shippingAddress'];
      }
      final pendingDocRef = await FirebaseFirestore.instance
          .collection('users/${user.uid}/cards')
          .add(pendingCardData);

      if (reservedInventory != null) {
        final String? inventoryDocId =
            reservedInventory['inventoryCardDocId']?.toString();
        if (inventoryDocId != null && inventoryDocId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('physical_card_inventory')
              .doc(inventoryDocId)
              .update({
                'assignedCardDocPath': 'users/${user.uid}/cards/${pendingDocRef.id}',
                'assignedCardDocId': pendingDocRef.id,
                'updatedAt': FieldValue.serverTimestamp(),
              });
          _logCardCreate('physical inventory linked to card doc', {
            'inventoryCardDocId': inventoryDocId,
            'cardDocId': pendingDocRef.id,
          });
        }
      }
      _logCardCreate('pending card saved to firestore', pendingDocRef.id);

      // Dismiss loading and show "being created" sheet immediately
      Navigator.pop(context);
      _fetchCards();
      showModalBottomSheet(
        context: context,
        builder: (context) => SuccessBottomSheet(
          actionText: 'Done',
          title: 'Card is being created!',
          description: type == 'Physical'
              ? "Your physical card request is in progress. Delivery can take up to 2 weeks, and tracking will appear in card details."
              : "Your card will be ready in a few minutes. We'll notify you when it's done.",
        ),
        isScrollControlled: true,
      );

      // Fire-and-forget: fund Sudo account and create card server-side
      FirebaseFunctions.instance
          .httpsCallable('sudoFundAndCreateCard')
          .call({
            'userId': user.uid,
            'cardDocId': pendingDocRef.id,
            'customerId': sudoCustomerId ?? '',
            'debitAccountId': sudoDebitAccountId,
            'type': type.toLowerCase(),
            'brand': basicData['scheme'],
            'currency': cardCurrency,
            'issuerCountry': cardCurrency == 'USD' ? 'USA' : 'NGA',
            if (basicData['fundAmount'] != null)
              'fundAmount': basicData['fundAmount'] as int,
            if (basicData['usdNgnRate'] != null)
              'usdNgnRate': (basicData['usdNgnRate'] as num).toDouble(),
            if (basicData['fundAmountNgnEquivalent'] != null)
              'fundAmountNgnEquivalent':
                  (basicData['fundAmountNgnEquivalent'] as num).toDouble(),
          })
          .then((_) {
            if (mounted) _fetchCards();
          })
          .catchError((e) {
            _logCardCreate('sudoFundAndCreateCard background error', e);
            if (mounted) _fetchCards();
          });
    } catch (e, st) {
      Navigator.pop(context);
      _logCardCreate('error', e);
      _logCardCreate('stacktrace', st);
      final errorText = e.toString().toLowerCase();
      String userMessage = 'Card creation failed. Please try again.';

      // Keep internal logs detailed, but avoid exposing inventory/provider internals.
      if (type == 'Physical' &&
          (errorText.contains('no unassigned') ||
              errorText.contains('physical card creation requires an assigned inventory card number') ||
              errorText.contains('already linked') ||
              errorText.contains('replacement physical card number'))) {
        userMessage = 'Physical cards are currently unavailable. Please try again later.';
      } else if (errorText.contains('settlement account')) {
        userMessage = 'Card service is temporarily unavailable. Please try again later.';
      }

      showSimpleDialog(userMessage, Colors.red);
    }
  }
}

class EnterPinBottomSheet extends StatefulWidget {
  final String title;
  final String description;

  const EnterPinBottomSheet({
    super.key,
    this.title = 'Create Card PIN',
    this.description = 'Enter a 4-digit PIN to secure your card',
  });

  @override
  State<EnterPinBottomSheet> createState() => _EnterPinBottomSheetState();
}

class _EnterPinBottomSheetState extends State<EnterPinBottomSheet> {
  String pin = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool isCurrent = index == pin.length;
                  bool isEntered = index < pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent ? Colors.blue : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isEntered
                          ? Text(
                              pin[index],
                              style: const TextStyle(fontSize: 20),
                            )
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Keypad(
                onPressed: (val) async {
                  if (val == null) {
                    setState(() {
                      if (pin.isNotEmpty) {
                        pin = pin.substring(0, pin.length - 1);
                      }
                    });
                  } else if (pin.length < 4) {
                    setState(() => pin += val);

                    if (pin.length == 4) {
                      Navigator.pop(context, pin);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

