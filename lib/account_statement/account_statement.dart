import 'package:card_app/utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AccountStatementPage extends StatefulWidget {
  final Map<String, dynamic> card;
  const AccountStatementPage({super.key, required this.card});

  @override
  State<AccountStatementPage> createState() => _AccountStatementPageState();
}

class _AccountStatementPageState extends State<AccountStatementPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  List<dynamic>? _transactions;
  String? _error;

  String? get _cardId => widget.card['card_id']?.toString();
  String get _currency => (widget.card['selectedCurrency'] ?? 'NGN').toString();

  Future<void> _selectDate(bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
        _transactions = null;
        _error = null;
      });
    }
  }

  Future<void> _generate() async {
    final cardId = _cardId;
    if (cardId == null) {
      setState(() => _error = 'Card ID not found.');
      return;
    }
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'Please select both a start and end date.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'End date must be after start date.');
      return;
    }

    setState(() {
      _loading = true;
      _transactions = null;
      _error = null;
    });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sudoGetCardTransactions')
          .call({
        'cardId': cardId,
        'fromDate': DateFormat('yyyy-MM-dd').format(_startDate!),
        'toDate': DateFormat('yyyy-MM-dd').format(_endDate!),
        'limit': 200,
      });
      final data = result.data;
      final txList = (data is Map && data['data'] is List) ? data['data'] as List : [];
      if (mounted) setState(() => _transactions = txList);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load transactions: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatAmount(dynamic amount, String currency) {
    final num val = (amount is num) ? amount : (num.tryParse(amount.toString()) ?? 0);
    final symbol = currency == 'NGN' ? '₦' : '\$';
    return '$symbol${val.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy');
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: navyBlue,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 60),
                const Text(
                  'Account Statement',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Start Date', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _selectDate(true),
                    child: _DatePickerField(
                      label: _startDate == null ? 'Select Start Date' : fmt.format(_startDate!),
                      hasValue: _startDate != null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('End Date', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _selectDate(false),
                    child: _DatePickerField(
                      label: _endDate == null ? 'Select End Date' : fmt.format(_endDate!),
                      hasValue: _endDate != null,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _generate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Generate Statement', style: TextStyle(color: Colors.white)),
                  ),
                  if (_transactions != null) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          '${_transactions!.length} transaction${_transactions!.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const Spacer(),
                        if (_startDate != null && _endDate != null)
                          Text(
                            '${fmt.format(_startDate!)} – ${fmt.format(_endDate!)}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_transactions!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No transactions found for this period.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _transactions!.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final tx = _transactions![i];
                          final Map<String, dynamic> txMap =
                              tx is Map<String, dynamic> ? tx : {};
                          final String merchantName =
                              txMap['merchant']?['name']?.toString() ?? 'Unknown Merchant';
                          final dynamic amount = txMap['amount'] ?? txMap['transactionAmount'] ?? 0;
                          final String txType = txMap['type']?.toString() ?? '';
                          final bool isCredit = txType.toLowerCase().contains('credit') ||
                              txType.toLowerCase().contains('reversal');
                          final String rawDate =
                              txMap['transactionDate']?.toString() ?? txMap['createdAt']?.toString() ?? '';
                          String dateLabel = rawDate;
                          try {
                            dateLabel = fmt.format(DateTime.parse(rawDate).toLocal());
                          } catch (_) {}

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: isCredit
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              child: Icon(
                                isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isCredit ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            title: Text(merchantName, style: const TextStyle(fontSize: 14)),
                            subtitle: Text(dateLabel,
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            trailing: Text(
                              '${isCredit ? '+' : '-'}${_formatAmount(amount, _currency)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCredit ? Colors.green : Colors.red,
                                fontSize: 14,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final bool hasValue;
  const _DatePickerField({required this.label, required this.hasValue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: hasValue ? Colors.black : Colors.grey)),
          const Icon(Icons.calendar_today, color: Colors.grey),
        ],
      ),
    );
  }
}
