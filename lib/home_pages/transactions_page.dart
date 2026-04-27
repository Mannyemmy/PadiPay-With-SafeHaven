import 'dart:async';
import 'dart:io';
import 'package:card_app/home_pages/card_page.dart';
import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/profile/profile_page.dart';
import 'package:card_app/ui/bottom_nav_bar.dart';
import 'package:card_app/ui/receipt_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  int _selectedIndex = 2;
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  String _selectedCategory = 'All Categories';
  String _selectedStatus = 'All';
  String _searchQuery = '';
  DateTime? _selectedMonth;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _showCustomDateRange = false;
  final TextEditingController _searchController = TextEditingController();
  bool _filtersExpanded = false;
  List<String> _searchSuggestions = [];
  bool _showSuggestions = false;
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _allTransactionData = [];

  final Map<String, List<String>> _categoryTypes = {
    'All Categories': [],
    'Mobile Data': ['data', 'mobile_data'],
    'Add Money': ['deposit'],
    'Giveaway': ['giveaway_claim', 'giveaway_create'],
    'Ghost Mode Transfers': ['ghost_transfer'],
    'Bill Payments': ['bill_payment', 'cable'],
    'Airtime': ['airtime'],
    'Data Bundle': ['data', 'mobile_data'],
    'Electricity': ['electricity'],
    'Cable': ['cable'],
    'Cashback': ['cashback_earned', 'cashback_spent'],
    'Transfer': ['transfer', 'wifi', 'nfc'],
    'Card Payment': [
      'atm_payment',
      'card_debit',
      'card_declined',
      'card_refund',
    ],
  };

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

  IconData _getIcon(String type, bool isOutgoing) {
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
        return Icons.add;
      case 'giveaway_claim':
        return FontAwesomeIcons.gift;
      case 'giveaway_create':
        return FontAwesomeIcons.gift;
      case 'ghost_transfer':
        return FontAwesomeIcons.ghost;
      case 'atm_payment':
        return FontAwesomeIcons.creditCard;
      case 'card_debit':
        return Icons.credit_card;
      case 'card_declined':
        return Icons.credit_card;
      case 'card_refund':
        return Icons.undo;
      case 'cashback_earned':
        return Icons.savings;
      case 'cashback_spent':
        return Icons.local_offer_outlined;
      default:
        return FontAwesomeIcons.exchangeAlt;
    }
  }

  void _showFilterPopup(
    BuildContext context,
    String type,
    List<String> items,
    String selectedValue,
    Function(String) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
      builder: (context) => SafeArea(
        bottom: true,
        child: Container(
          width: MediaQuery.of(context).size.width,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items
                    .map(
                      (item) => GestureDetector(
                        onTap: () {
                          onSelect(item);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: item == selectedValue
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.grey[200],
                            border: item == selectedValue
                                ? Border.all(color: Colors.blue, width: 1)
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item == selectedValue)
                                const Icon(
                                  Icons.check,
                                  color: Colors.blue,
                                  size: 16,
                                ),
                              if (item == selectedValue)
                                const SizedBox(width: 4),
                              Text(
                                item,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: item == selectedValue
                                      ? Colors.blue
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _getDocDate(Map<String, dynamic> data) {
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

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
        _customStartDate = null;
        _customEndDate = null;
        _showCustomDateRange = false;
      });
    }
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _customStartDate = picked;
        if (_customEndDate != null && _customEndDate!.isBefore(picked)) {
          _customEndDate = null;
        }
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customEndDate ?? (_customStartDate ?? DateTime.now()),
      firstDate: _customStartDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _customEndDate = picked;
      });
    }
  }

  void _clearDateFilters() {
    setState(() {
      _selectedMonth = null;
      _customStartDate = null;
      _customEndDate = null;
      _showCustomDateRange = false;
    });
  }

  void _toggleCustomDateRange() {
    setState(() {
      _showCustomDateRange = !_showCustomDateRange;
      if (_showCustomDateRange) {
        _selectedMonth = null;
      } else {
        _customStartDate = null;
        _customEndDate = null;
      }
    });
  }

  // Method to update search suggestions
  void _updateSearchSuggestions(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    Set<String> suggestions = <String>{};

    for (var doc in _allTransactionData) {
      // Search in recipient names
      if (doc['recipientName'] != null &&
          doc['recipientName'].toString().toLowerCase().contains(
            query.toLowerCase(),
          )) {
        suggestions.add(doc['recipientName'].toString());
      }

      // Search in phone numbers
      if (doc['phoneNumber'] != null &&
          doc['phoneNumber'].toString().contains(query)) {
        suggestions.add(doc['phoneNumber'].toString());
      }

      // Search in meter numbers
      if (doc['meterNumber'] != null &&
          doc['meterNumber'].toString().contains(query)) {
        suggestions.add(doc['meterNumber'].toString());
      }

      // Search in account numbers
      if (doc['account_number'] != null &&
          doc['account_number'].toString().contains(query)) {
        suggestions.add(doc['account_number'].toString());
      }

      // Search in smartcard numbers
      if (doc['smartcard_number'] != null &&
          doc['smartcard_number'].toString().contains(query)) {
        suggestions.add(doc['smartcard_number'].toString());
      }
    }

    setState(() {
      _searchSuggestions = suggestions
          .take(10)
          .toList(); // Limit to 10 suggestions
      _showSuggestions = _searchSuggestions.isNotEmpty;
    });
  }

  // Method to select a suggestion
  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    setState(() {
      _searchQuery = suggestion.toLowerCase();
      _showSuggestions = false;
    });
    _searchFocusNode.unfocus();
  }

  // Method to clear search
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchSuggestions = [];
      _showSuggestions = false;
    });
  }

  StreamSubscription<QuerySnapshot>? _sentSub;
  StreamSubscription<QuerySnapshot>? _receivedSub;
  StreamSubscription<QuerySnapshot>? _cpSub;
  StreamSubscription<QuerySnapshot>? _receivedCpSub;
  StreamSubscription<QuerySnapshot>? _cardTxSub;

  List<QueryDocumentSnapshot> sentDocs = [];
  List<QueryDocumentSnapshot> receivedDocs = [];
  List<QueryDocumentSnapshot> receivedCpDocs = [];
  List<QueryDocumentSnapshot> cardTxDocs = [];
  List<String> cpIds = [];

  @override
  void initState() {
    super.initState();

    // Initialize focus node listeners
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        setState(() {
          _showSuggestions = false;
        });
      }
    });

    // Initialize streams
    _sentSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          Filter.or(
            Filter('userId', isEqualTo: uid),
            Filter('actualSender', isEqualTo: uid),
          ),
        )
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) {
              setState(() {
                sentDocs = snap.docs;
                _updateAllTransactionData();
              });
            }
          },
          onError: (e) {
            print('Sent transactions stream error: $e');
          },
        );
    _receivedSub = FirebaseFirestore.instance
        .collection('transactions')
        .where('receiverId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) {
              setState(() {
                receivedDocs = snap.docs;
                _updateAllTransactionData();
              });
            }
          },
          onError: (e) {
            print('Received transactions stream error: $e');
          },
        );
    _cpSub = FirebaseFirestore.instance
        .collection('counterparties')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
          setState(() {
            cpIds = snap.docs.map((doc) => doc.id).toList();
            _updateCpStream();
          });
        });
    _cardTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) {
              setState(() {
                cardTxDocs = snap.docs;
                _updateAllTransactionData();
              });
            }
          },
          onError: (e) {
            print('Card transactions stream error: $e');
          },
        );
  }

  Future<Map<String, dynamic>> _getUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return {}; // or throw an exception
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        return {};
      }

      return doc.data() as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      return {};
    }
  }

  Future<void> _generateAndDownloadPDF(
    List<QueryDocumentSnapshot> filteredDocs,
  ) async {
    try {
      final pdf = pw.Document();

      // Fetch user data
      final userData = await _getUserData();
      final String fullName =
          '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
      final String phone = userData['phone']?.toString() ?? 'N/A';
      final addressMap = userData['address'] as Map<String, dynamic>? ?? {};
      final String street = addressMap['street']?.toString() ?? '';
      final String city = addressMap['city']?.toString() ?? '';
      final String state = addressMap['state']?.toString() ?? '';
      final String postalCode = addressMap['postalCode']?.toString() ?? '';
      final String country = addressMap['country']?.toString() ?? '';
      final String fullAddress = [
        if (street.isNotEmpty) street,
        if (city.isNotEmpty) city,
        if (state.isNotEmpty) state,
        if (postalCode.isNotEmpty) postalCode,
        if (country.isNotEmpty) country,
      ].where((part) => part.isNotEmpty).join(', ');

      // Build PDF content
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) => [
            // Title: Statement
            pw.Center(
              child: pw.Text(
                'Statement',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'Generated on ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 24),

            // User Details Section
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Account Holder',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Name: $fullName',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Phone: $phone',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  if (fullAddress.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Address: $fullAddress',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Transactions Table - ALL fields safely converted to String
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Description', 'Category', 'Status', 'Amount'],
              data: filteredDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;

                // Safe date
                final transactionDate = _getDocDate(data);
                final formattedDate = DateFormat(
                  'dd/MM/yyyy',
                ).format(transactionDate);

                // Safe amount
                final amountValue =
                    (data['amount'] ?? data['debitAmount'] ?? 0) as num;

                // Safe sign logic
                final type = data['type']?.toString().toLowerCase() ?? '';
                final sign =
                    (type == 'credit' ||
                        type == 'deposit' ||
                        type == 'giveaway_claim' ||
                        type == 'add_money' ||
                        type == 'fund')
                    ? '+'
                    : '-';

                // ALL fields forced to String safely
                return [
                  formattedDate,
                  data['description']?.toString() ?? '-',
                  data['category']?.toString() ?? '-',
                  data['status']?.toString() ?? '-',
                  '$sign ${NumberFormat.currency(symbol: '₦', decimalDigits: 2).format(amountValue)}',
                ];
              }).toList(),
              border: null,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.center,
                4: pw.Alignment.centerRight,
              },
              cellStyle: const pw.TextStyle(fontSize: 11),
            ),
          ],
        ),
      );

      // Save PDF to temporary directory
      final output = await getTemporaryDirectory();
      final file = File(
        "${output.path}/statement_${DateTime.now().millisecondsSinceEpoch}.pdf",
      );
      await file.writeAsBytes(await pdf.save());

      // Automatically open the PDF
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        debugPrint('Error opening PDF: ${result.message}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF saved, but could not open: ${result.message}'),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Statement PDF generated and opened')),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error generating PDF: $e');
      debugPrint('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
      }
    }
  }

  void _updateAllTransactionData() {
    List<QueryDocumentSnapshot> allDocs = [
      ...sentDocs,
      ...receivedDocs,
      ...receivedCpDocs,
      ...cardTxDocs,
    ];
    _allTransactionData = allDocs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'recipientName': data['recipientName'],
        'phoneNumber': data['phoneNumber'],
        'meterNumber': data['meterNumber'],
        'smartcard_number': data['smartcard_number'],
        'account_number': data['account_number'],
      };
    }).toList();
  }

  void _updateCpStream() {
    _receivedCpSub?.cancel();
    if (cpIds.isEmpty) {
      setState(() {
        receivedCpDocs = [];
        _updateAllTransactionData();
      });
      return;
    }
    _receivedCpSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          'api_response.data.relationships.counterParty.data.id',
          whereIn: cpIds,
        )
        .snapshots()
        .listen((snap) {
          setState(() {
            receivedCpDocs = snap.docs;
            _updateAllTransactionData();
          });
        });
  }

  @override
  void dispose() {
    _sentSub?.cancel();
    _receivedSub?.cancel();
    _cpSub?.cancel();
    _receivedCpSub?.cancel();
    _cardTxSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Helper method to toggle filters
  void _toggleFilters() {
    setState(() {
      _filtersExpanded = !_filtersExpanded;
    });
  }

  // Method to clear all filters
  void _clearAllFilters() {
    setState(() {
      _selectedCategory = 'All Categories';
      _selectedStatus = 'All';
      _selectedMonth = null;
      _customStartDate = null;
      _customEndDate = null;
      _showCustomDateRange = false;
      _searchController.clear();
      _searchQuery = '';
      _searchSuggestions = [];
      _showSuggestions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox.expand(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Transaction History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Filter Toggle Button
                    GestureDetector(
                      onTap: _toggleFilters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.filter_list,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Filters',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                // Show active filter count badge
                                if (_hasActiveFilters())
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _countActiveFilters().toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (_hasActiveFilters())
                                  const SizedBox(width: 8),
                                Icon(
                                  _filtersExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: Colors.blue,
                                  size: 24,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Expandable Filters Section
                    AnimatedCrossFade(
                      firstChild: Container(),
                      secondChild: Column(
                        children: [
                          const SizedBox(height: 16),

                          // Clear All Filters Button
                          if (_hasActiveFilters())
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                GestureDetector(
                                  onTap: _clearAllFilters,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.red.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.clear_all,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Clear All',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                          if (_hasActiveFilters()) const SizedBox(height: 12),

                          // Search Bar with Suggestions
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Search by name, number...',
                                    hintStyle: TextStyle(
                                      color: Colors.blueGrey.withOpacity(0.5),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: Colors.blue,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    border: InputBorder.none,
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.cancel,
                                              color: Colors.grey,
                                            ),
                                            onPressed: _clearSearch,
                                          )
                                        : null,
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _searchQuery = value.toLowerCase();
                                    });
                                    _updateSearchSuggestions(value);
                                  },
                                  onTap: () {
                                    if (_searchQuery.isNotEmpty) {
                                      _updateSearchSuggestions(_searchQuery);
                                    }
                                  },
                                ),
                              ),

                              // Search Suggestions Dropdown
                              if (_showSuggestions && _searchFocusNode.hasFocus)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  constraints: const BoxConstraints(
                                    maxHeight: 200,
                                  ),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    physics: const ClampingScrollPhysics(),
                                    itemCount: _searchSuggestions.length,
                                    itemBuilder: (context, index) {
                                      final suggestion =
                                          _searchSuggestions[index];
                                      return GestureDetector(
                                        onTap: () =>
                                            _selectSuggestion(suggestion),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            border:
                                                index <
                                                    _searchSuggestions.length -
                                                        1
                                                ? Border(
                                                    bottom: BorderSide(
                                                      color:
                                                          Colors.grey.shade200,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.search,
                                                size: 16,
                                                color: Colors.grey.shade600,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  suggestion,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey.shade800,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                          ),

                          const SizedBox(height: 16),

                          // Date Filter Section
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _selectMonth(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _selectedMonth != null
                                                ? DateFormat(
                                                    'MMM yyyy',
                                                  ).format(_selectedMonth!)
                                                : 'All Time',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 20,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _toggleCustomDateRange,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.date_range,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              if (_selectedMonth != null ||
                                  _customStartDate != null ||
                                  _customEndDate != null)
                                GestureDetector(
                                  onTap: _clearDateFilters,
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.red.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.clear,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          // Custom Date Range Picker
                          if (_showCustomDateRange)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _selectStartDate(context),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _customStartDate != null
                                                    ? DateFormat(
                                                        'dd MMM yyyy',
                                                      ).format(
                                                        _customStartDate!,
                                                      )
                                                    : 'Start Date',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.black54,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.calendar_today,
                                              size: 20,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _selectEndDate(context),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _customEndDate != null
                                                    ? DateFormat(
                                                        'dd MMM yyyy',
                                                      ).format(_customEndDate!)
                                                    : 'End Date',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.black54,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.calendar_today,
                                              size: 20,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 16),

                          // Category and Status Filters
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showFilterPopup(
                                    context,
                                    'category',
                                    _categoryTypes.keys.toList(),
                                    _selectedCategory,
                                    (value) => setState(
                                      () => _selectedCategory = value,
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _selectedCategory,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.filter_list,
                                          size: 20,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showFilterPopup(
                                    context,
                                    'status',
                                    [
                                      'All',
                                      'Successful',
                                      'To be paid',
                                      'Reversed',
                                      'Pending',
                                      'Failed',
                                    ],
                                    _selectedStatus,
                                    (value) =>
                                        setState(() => _selectedStatus = value),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _selectedStatus,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.filter_list,
                                          size: 20,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          // DOWNLOAD BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final (filteredDocs, _) = _getFilteredData();
                                if (filteredDocs.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No transactions to download',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                _generateAndDownloadPDF(filteredDocs);
                              },
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 20,
                              ),
                              label: const Text(
                                'Download as PDF',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      crossFadeState: _filtersExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 300),
                    ),

                    const SizedBox(height: 16),

                    // Total Amount Display
                    Builder(
                      builder: (context) {
                        final (filteredDocs, totalAmount) = _getFilteredData();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Total Transactions',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${filteredDocs.length} transactions',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'Total Amount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₦${NumberFormat('#,##0.00').format(totalAmount)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 5),

                    // Transactions List
                    Expanded(
                      child: RefreshIndicator(
                        color: primaryColor,
                        backgroundColor: Colors.white,
                        onRefresh: () async {},
                        child: Builder(
                          builder: (context) {
                            final (filteredDocs, _) = _getFilteredData();

                            if (filteredDocs.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.receipt_long,
                                      size: 80,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No transactions found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try changing your filters or search query',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: EdgeInsets.only(top: 20),
                              itemCount: filteredDocs.length + 1,
                              itemBuilder: (context, index) {
                                if (index == filteredDocs.length) {
                                  return const SizedBox(height: 100);
                                }
                                final doc = filteredDocs[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final type =
                                    data['type']?.toString().toLowerCase() ??
                                    '';
                                bool isOutgoing = true;
                                String otherId = '';
                                if (type == 'transfer' ||
                                    type == "ghost_transfer") {
                                  if (data['userId'] == uid ||
                                      data['actualSender'] == uid) {
                                    isOutgoing = true;
                                    otherId = data['receiverId'] ?? '';
                                  } else {
                                    isOutgoing = false;
                                    otherId = data['userId'] ?? '';
                                  }
                                } else if (type == 'atm_payment') {
                                  // Customer paid you via ATM — money coming IN
                                  isOutgoing = false;
                                  otherId = '';
                                } else if (type == 'card_debit') {
                                  isOutgoing = true;
                                  otherId = '';
                                } else if (type == 'card_declined') {
                                  isOutgoing = true;
                                  otherId = '';
                                } else if (type == 'card_refund') {
                                  isOutgoing = false;
                                  otherId = '';
                                } else {
                                  isOutgoing = true;
                                  otherId = '';
                                }
                                final icon = _getIcon(type, isOutgoing);
                                final amountSign = type == 'card_refund'
                                    ? '+'
                                    : type == 'card_declined'
                                    ? '' // declined = no debit occurred
                                    : type == 'cashback_earned'
                                    ? '+'
                                    : type == 'cashback_spent'
                                    ? '-'
                                    : (!isOutgoing ||
                                          type == "deposit" ||
                                          type == "giveaway_claim")
                                    ? '+'
                                    : '-';
                                final status = _getStatus(data);

                                Color statusColor = Colors.grey;
                                if ([
                                  'success',
                                  'completed',
                                  'successful',
                                  'approved',
                                ].contains(status)) {
                                  statusColor = Colors.green;
                                } else if ([
                                  'pending',
                                  'to be paid',
                                ].contains(status)) {
                                  statusColor = Colors.orange;
                                } else if ([
                                  'failed',
                                  'unsuccessful',
                                  'declined',
                                ].contains(status)) {
                                  statusColor = Colors.red;
                                } else if (status == 'reversed') {
                                  statusColor = Colors.grey;
                                }

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
                                  if (isOutgoing) {
                                    offset = const Offset(-2, 2);
                                  }
                                }
                                if (type.contains("ghost")) {
                                  bgColor = const Color(0xFFECEFF1);
                                  iconColor = const Color(0xFF37474F);
                                }
                                if (type.contains("giveaway")) {
                                  bgColor = const Color(0xFFFFF8E1);
                                  iconColor = const Color(0xFFFF6F00);
                                }
                                if (type == 'deposit' ||
                                    type == 'fund' ||
                                    type == 'add_money') {
                                  bgColor = const Color(0xFFE8F5E9);
                                  iconColor = const Color(0xFF2E7D32);
                                }
                                if (type == 'card_debit') {
                                  bgColor = const Color(0xFFFFF3E0);
                                  iconColor = const Color(0xFFE65100);
                                  statusColor = Colors.green;
                                }
                                if (type == 'card_declined') {
                                  bgColor = const Color(0xFFFFEBEE);
                                  iconColor = const Color(0xFFC62828);
                                  statusColor = Colors.red;
                                }
                                if (type == 'card_refund') {
                                  bgColor = const Color(0xFFE8F5E9);
                                  iconColor = const Color(0xFF2E7D32);
                                  statusColor = Colors.green;
                                }
                                if (type == 'cashback_earned') {
                                  bgColor = const Color(0xFFE8F5E9);
                                  iconColor = const Color(0xFF2E7D32);
                                  statusColor = Colors.green;
                                }
                                if (type == 'cashback_spent') {
                                  bgColor = const Color(0xFFFFF8E1);
                                  iconColor = const Color(0xFFFF8F00);
                                  statusColor = Colors.orange;
                                }

                                final date = _getDocDate(data);
                                final formattedTime = DateFormat(
                                  'HH:mm',
                                ).format(date);
                                final formattedDate = DateFormat(
                                  'MMMM d, yyyy',
                                ).format(date);
                                final isCardTx =
                                    type == 'card_debit' ||
                                    type == 'card_declined' ||
                                    type == 'card_refund';
                                final initialName = isCardTx
                                    ? (data['merchant'] ?? 'Card Transaction')
                                    : data['recipientName'] ??
                                          data['phoneNumber'] ??
                                          data['meterNumber'] ??
                                          data['smartcard_number'] ??
                                          data['account_number'] ??
                                          'Unknown';
                                final amountInNaira =
                                    ((data['amount'] as num?) ??
                                    (data['debitAmount'] as num? ?? 0));
                                final formattedAmount = NumberFormat(
                                  '#,##0.00',
                                ).format(amountInNaira);
                                final reference =
                                    data['reference'] ??
                                    (data['api_response']?['data']?['attributes']?['reference']
                                        as String?) ??
                                    (data['transactionId'] as String?) ??
                                    '';

                                return TransactionItem(
                                  docId: doc.id,
                                  icon: icon,
                                  otherId: otherId,
                                  amount: '$amountSign₦$formattedAmount',
                                  amountColor: isCardTx
                                      ? (type == 'card_refund'
                                            ? Colors.green
                                            : type == 'card_declined'
                                            ? Colors.grey.shade600
                                            : Colors.red)
                                      : statusColor,
                                  formattedTime: formattedTime,
                                  formattedDate: formattedDate,
                                  status: isCardTx
                                      ? (type == 'card_declined'
                                            ? 'Declined'
                                            : type == 'card_refund'
                                            ? 'Refunded'
                                            : 'Successful')
                                      : status == 'approved'
                                      ? 'Successful'
                                      : status == 'declined'
                                      ? 'Declined'
                                      : status.replaceAll('_', ' ').isNotEmpty
                                      ? status
                                                .replaceAll('_', ' ')[0]
                                                .toUpperCase() +
                                            status
                                                .replaceAll('_', ' ')
                                                .substring(1)
                                      : status,
                                  statusColor: statusColor,
                                  isOutgoing: isOutgoing,
                                  otherName: initialName,
                                  type: type,
                                  reference: reference,
                                  bgColor: bgColor,
                                  iconColor: iconColor,
                                  offset: offset,
                                  cardData: isCardTx ? data : null,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
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
                        if (index == 1) {
                          navigateTo(
                            context,
                            CardsPage(),
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

  // Helper method to check if any filter is active
  bool _hasActiveFilters() {
    return _selectedCategory != 'All Categories' ||
        _selectedStatus != 'All' ||
        _selectedMonth != null ||
        _customStartDate != null ||
        _customEndDate != null ||
        _searchQuery.isNotEmpty;
  }

  // Helper method to count active filters
  int _countActiveFilters() {
    int count = 0;
    if (_selectedCategory != 'All Categories') count++;
    if (_selectedStatus != 'All') count++;
    if (_selectedMonth != null) count++;
    if (_customStartDate != null) count++;
    if (_customEndDate != null) count++;
    if (_searchQuery.isNotEmpty) count++;
    return count;
  }

  (List<QueryDocumentSnapshot>, double) _getFilteredData() {
    List<QueryDocumentSnapshot> docs = [
      ...sentDocs,
      ...receivedDocs,
      ...receivedCpDocs,
      ...cardTxDocs,
    ];

    // Remove duplicates by document ID
    Map<String, QueryDocumentSnapshot> uniqueDocs = {};
    for (var doc in docs) {
      uniqueDocs[doc.id] = doc;
    }
    List<QueryDocumentSnapshot> uniqueList = uniqueDocs.values.toList();

    // Sort by date (newest first)
    final sortedDocs = uniqueList
      ..sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aTimestamp = _getDocDate(aData);
        final bTimestamp = _getDocDate(bData);
        return bTimestamp.compareTo(aTimestamp);
      });

    double totalAmount = 0.0;

    final filteredDocs = sortedDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString().toLowerCase() ?? '';
      final status = _getStatus(data);
      final date = _getDocDate(data);

      // 1. Search filter
      bool matchesSearch = _searchQuery.isEmpty;
      if (!matchesSearch) {
        final searchFields = [
          data['recipientName']?.toString().toLowerCase() ?? '',
          data['phoneNumber']?.toString().toLowerCase() ?? '',
          data['meterNumber']?.toString().toLowerCase() ?? '',
          data['smartcard_number']?.toString().toLowerCase() ?? '',
          data['account_number']?.toString().toLowerCase() ?? '',
          data['reference']?.toString().toLowerCase() ?? '',
          data['transactionId']?.toString().toLowerCase() ?? '',
          data['merchant']?.toString().toLowerCase() ?? '',
          type,
        ];
        matchesSearch = searchFields.any(
          (field) => field.contains(_searchQuery),
        );
      }

      // 2. Category filter
      bool matchesCategory = _selectedCategory == 'All Categories'
          ? true
          : _categoryTypes[_selectedCategory]?.contains(type) ?? false;

      // 3. Status filter
      bool matchesStatus = _selectedStatus == 'All'
          ? true
          : _selectedStatus.toLowerCase() == status ||
                (_selectedStatus.toLowerCase() == 'successful' &&
                    (status == 'success' || status == 'completed')) ||
                (_selectedStatus.toLowerCase() == 'to be paid' &&
                    status == 'to be paid') ||
                (_selectedStatus.toLowerCase() == 'reversed' &&
                    status == 'reversed') ||
                (_selectedStatus.toLowerCase() == 'pending' &&
                    status == 'pending') ||
                (_selectedStatus.toLowerCase() == 'failed' &&
                    (status == 'failed' || status == 'unsuccessful'));

      // 4. Date filter
      bool matchesDate = true;
      if (_selectedMonth != null) {
        matchesDate =
            date.year == _selectedMonth!.year &&
            date.month == _selectedMonth!.month;
      } else if (_customStartDate != null || _customEndDate != null) {
        if (_customStartDate != null) {
          final startDate = DateTime(
            _customStartDate!.year,
            _customStartDate!.month,
            _customStartDate!.day,
          );
          matchesDate = date.isAfter(
            startDate.subtract(const Duration(days: 1)),
          );
        }
        if (_customEndDate != null && matchesDate) {
          final endDate = DateTime(
            _customEndDate!.year,
            _customEndDate!.month,
            _customEndDate!.day,
          );
          matchesDate = date.isBefore(endDate.add(const Duration(days: 1)));
        }
      }

      final shouldInclude =
          matchesSearch && matchesCategory && matchesStatus && matchesDate;

      // Add the positive amount for every included transaction
      if (shouldInclude) {
        final amount = (data['amount'] ?? data['debitAmount'] ?? 0) as num;
        totalAmount += amount.toDouble(); // Always positive, no minuses
      }

      return shouldInclude;
    }).toList();

    return (filteredDocs, totalAmount);
  }
}

class TransactionItem extends StatefulWidget {
  final String docId;
  final IconData icon;
  final String otherId;
  final String amount;
  final Color amountColor;
  final String formattedTime;
  final String formattedDate;
  final String status;
  final Color statusColor;
  final bool isOutgoing;
  final String otherName;
  final String type;
  final String reference;
  final Color bgColor;
  final Color iconColor;
  final Offset offset;
  final Map<String, dynamic>? cardData;

  const TransactionItem({
    super.key,
    required this.docId,
    required this.icon,
    required this.otherId,
    required this.amount,
    required this.amountColor,
    required this.formattedTime,
    required this.formattedDate,
    required this.status,
    required this.statusColor,
    required this.isOutgoing,
    required this.otherName,
    required this.type,
    required this.reference,
    required this.bgColor,
    required this.iconColor,
    required this.offset,
    this.cardData,
  });

  @override
  State<TransactionItem> createState() => _TransactionItemState();
}

class _TransactionItemState extends State<TransactionItem> {
  String? _fetchedName;

  @override
  void initState() {
    super.initState();
    if (widget.type.toLowerCase() == 'transfer' &&
        !widget.isOutgoing &&
        widget.otherId.isNotEmpty) {
      _fetchName();
    }
  }

  Future<void> _fetchName() async {
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherId)
          .get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
            .trim();
        if (name.isNotEmpty) {
          setState(() {
            _fetchedName = name;
          });
        }
      }
    } catch (e) {
      // ignore
    }
  }

  String _getTitle(String type, String otherName, bool isOutgoing) {
    switch (type) {
      case 'transfer':
        return isOutgoing
            ? 'Transfer to $otherName'
            : 'Transfer from $otherName';
      case 'airtime':
        return otherName != 'Unknown'
            ? 'Airtime for $otherName'
            : 'Airtime Purchase';
      case 'data':
      case 'mobile_data':
        return otherName != 'Unknown'
            ? 'Data Bundle for $otherName'
            : 'Data Purchase';
      case 'electricity':
        return 'Electricity Bill';
      case 'cable':
        return 'Cable Subscription';
      case 'add_money':
      case 'fund':
        return 'Add Money';
      case 'giveaway_claim':
        return 'Giveaway Claim';
      case 'giveaway_create':
        return 'Giveaway Created';
      case 'deposit':
        return 'Transfer from $otherName';
      case 'loans':
        return isOutgoing ? 'Loan Disbursed' : 'Loan Received';
      case 'ghost_transfer':
        return "Ghost Transfer";
      case 'anonymous_transfer':
        return 'Anonymous Transfer';
      case 'bill_payment':
        return 'Bill Payment for $otherName';
      case 'atm_payment':
        return 'Card Payment';
      case 'card_debit':
        return 'Virtual Card Payment at $otherName';
      case 'card_declined':
        return 'Virtual Card Payment at $otherName';
      case 'card_refund':
        return 'Card Refund from $otherName';
      case 'cashback_earned':
        return 'Cashback Earned';
      case 'cashback_spent':
        return 'Cashback Spent';
      default:
        return otherName != 'Unknown'
            ? '$type for $otherName'
            : type.toUpperCase();
    }
  }

  void _showCardDetail(BuildContext context) {
    final data = widget.cardData!;
    final type = data['type']?.toString() ?? '';
    final currency = data['currency']?.toString() ?? 'NGN';
    final merchant = data['merchant']?.toString() ?? 'Unknown';
    final channel = data['channel']?.toString() ?? '';
    final reference = data['reference']?.toString() ?? '';
    final status =
        data['status']?.toString() ??
        (type == 'card_declined' ? 'declined' : 'approved');
    final ts = data['timestamp'] as Timestamp?;
    final date = ts != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
        : '';
    final isDeclined = type == 'card_declined' || status == 'declined';
    final isRefund = type == 'card_refund';
    final statusLabel = isDeclined
        ? 'Declined'
        : isRefund
        ? 'Refunded'
        : 'Successful';
    final statusColor = isDeclined
        ? Colors.red
        : isRefund
        ? Colors.blue
        : Colors.green;

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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.amount,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _detailRow('Merchant', merchant),
            if (channel.isNotEmpty)
              _detailRow('Channel', channel.toUpperCase()),
            _detailRow('Currency', currency),
            if (date.isNotEmpty) _detailRow('Date', date),
            if (reference.isNotEmpty) _detailRow('Reference', reference),
            if (data['reason'] != null)
              _detailRow('Reason', data['reason'].toString()),
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
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _fetchedName ?? widget.otherName;
    final title = _getTitle(widget.type, displayName, widget.isOutgoing);

    return GestureDetector(
      onTap: () {
        navigateTo(
          context,
          ReceiptPage(reference: widget.reference, cardData: widget.cardData),
          type: NavigationType.push,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 0, right: 0),
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
              backgroundColor: widget.bgColor,
              child: Transform.translate(
                offset: widget.offset,
                child: Icon(widget.icon, color: widget.iconColor, size: 20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.grey.shade500,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.formattedTime,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        ' • ',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        widget.formattedDate,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
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
                  widget.amount,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: widget.amountColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.status,
                  style: TextStyle(
                    color: widget.statusColor,
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
  }
}
