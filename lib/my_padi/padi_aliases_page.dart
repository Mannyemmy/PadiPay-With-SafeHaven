import 'dart:async';

import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// A saved contact alias (nickname â†’ account or PadiTag).
class PadiAlias {
  final String id;
  final String alias;        // Display form: "Mum", "Big Sis"
  final String aliasKey;     // Lowercase for uniqueness: "mum", "big sis"
  final String type;         // "account" or "tag"
  final String? displayName; // Optional real name
  final String? accountNumber;
  final String? bankName;
  final String? padiTag;

  PadiAlias({
    required this.id,
    required this.alias,
    required this.aliasKey,
    required this.type,
    this.displayName,
    this.accountNumber,
    this.bankName,
    this.padiTag,
  });

  factory PadiAlias.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PadiAlias(
      id: doc.id,
      alias: d['alias'] ?? '',
      aliasKey: d['aliasKey'] ?? (d['alias'] ?? '').toString().toLowerCase(),
      type: d['type'] ?? 'account',
      displayName: d['displayName'],
      accountNumber: d['accountNumber'],
      bankName: d['bankName'],
      padiTag: d['padiTag'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'alias': alias,
        'aliasKey': aliasKey,
        'type': type,
        if (displayName != null && displayName!.isNotEmpty) 'displayName': displayName,
        if (accountNumber != null) 'accountNumber': accountNumber,
        if (bankName != null) 'bankName': bankName,
        if (padiTag != null) 'padiTag': padiTag,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  String get subtitle {
    if (type == 'tag') return '@${padiTag ?? ''}';
    final parts = <String>[];
    if (displayName != null && displayName!.isNotEmpty) parts.add(displayName!);
    if (accountNumber != null && accountNumber!.isNotEmpty) parts.add(accountNumber!);
    if (bankName != null && bankName!.isNotEmpty) parts.add(bankName!);
    return parts.join(' Â· ');
  }
}

class PadiAliasesPage extends StatefulWidget {
  const PadiAliasesPage({super.key});

  @override
  State<PadiAliasesPage> createState() => _PadiAliasesPageState();
}

class _PadiAliasesPageState extends State<PadiAliasesPage> {
  List<PadiAlias> _aliases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAliases();
  }

  Future<void> _loadAliases() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('padi_aliases')
        .orderBy('alias')
        .get();

    if (mounted) {
      setState(() {
        _aliases = snap.docs.map(PadiAlias.fromDoc).toList();
        _loading = false;
      });
    }
  }

  Future<void> _deleteAlias(PadiAlias alias) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('padi_aliases')
        .doc(alias.id)
        .delete();

    setState(() => _aliases.removeWhere((a) => a.id == alias.id));
  }

  bool _aliasExists(String name, {String? excludeId}) {
    final key = name.trim().toLowerCase();
    return _aliases.any((a) => a.aliasKey == key && a.id != (excludeId ?? ''));
  }

  Future<void> _showAddSheet({PadiAlias? editing}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AliasFormSheet(
        editing: editing,
        aliasExists: (name) => _aliasExists(name, excludeId: editing?.id),
      ),
    );
    if (ok == true) await _loadAliases();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: primaryColor))
                  : _aliases.isEmpty
                      ? _buildEmpty()
                      : _buildList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        backgroundColor: primaryColor,
        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
        label: Text('Add Contact',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.contacts, color: primaryColor, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MyPadi Contacts',
                    style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                Text('Nicknames for quick AI lookups',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.contacts_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No contacts yet',
              style: GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(
            'Save nicknames like "Mum" or "Big Sis"\nso MyPadi knows who you mean.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400], height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _aliases.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final alias = _aliases[i];
        return Dismissible(
          key: Key(alias.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red[50],
            child: const Icon(Icons.delete, color: Colors.red),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Remove "${alias.alias}"?',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                content: Text('This contact will be removed from MyPadi.',
                    style: GoogleFonts.inter()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancel', style: GoogleFonts.inter()),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Remove',
                        style: GoogleFonts.inter(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) => _deleteAlias(alias),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: _AliasAvatar(alias: alias),
            title: Text(alias.alias,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: Text(alias.subtitle,
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: alias.type == 'tag'
                        ? Colors.purple[50]
                        : Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    alias.type == 'tag' ? 'PadiTag' : 'Account',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: alias.type == 'tag' ? Colors.purple : primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
            onTap: () => _showAddSheet(editing: alias),
          ),
        );
      },
    );
  }
}

//  Avatar widget 

class _AliasAvatar extends StatelessWidget {
  final PadiAlias alias;
  const _AliasAvatar({required this.alias});

  @override
  Widget build(BuildContext context) {
    final initial = alias.alias.isNotEmpty ? alias.alias[0].toUpperCase() : '?';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: alias.type == 'tag'
            ? Colors.purple.withValues(alpha: 0.12)
            : primaryColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(initial,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: alias.type == 'tag' ? Colors.purple : primaryColor,
            )),
      ),
    );
  }
}

//  Add / Edit bottom sheet 

class _AliasFormSheet extends StatefulWidget {
  final PadiAlias? editing;
  final bool Function(String) aliasExists;

  const _AliasFormSheet({this.editing, required this.aliasExists});

  @override
  State<_AliasFormSheet> createState() => _AliasFormSheetState();
}

class _AliasFormSheetState extends State<_AliasFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _aliasCtrl;
  late final TextEditingController _accountNumberCtrl;
  late final TextEditingController _padiTagCtrl;
  String _type = 'account';

  // Banks
  List<Map<String, dynamic>> _banks = [];
  bool _loadingBanks = true;
  String? _selectedBankId;
  String? _selectedBankName;

  // Account verification
  String? _verifiedName;
  bool _verifyingAccount = false;
  String? _verifyError;

  // Save state
  bool _saving = false;

  // PadiTag validation
  bool _checkingTag = false;
  bool? _tagValid;
  String? _tagFoundName;
  Timer? _tagDebounce;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _type = e?.type ?? 'account';
    _aliasCtrl = TextEditingController(text: e?.alias ?? '');
    _accountNumberCtrl = TextEditingController(text: e?.accountNumber ?? '');
    _padiTagCtrl = TextEditingController(text: e?.padiTag ?? '');

    // When editing, treat existing data as pre-verified
    if (e != null) {
      _verifiedName = e.displayName;
      _selectedBankName = e.bankName;
      if (e.type == 'tag' && (e.padiTag ?? '').isNotEmpty) {
        _tagValid = true;
      }
    }

    _loadBanks();
    _accountNumberCtrl.addListener(_onAccountNumberChanged);
    _padiTagCtrl.addListener(_onTagChanged);
  }

  @override
  void dispose() {
    _tagDebounce?.cancel();
    _aliasCtrl.dispose();
    _accountNumberCtrl.dispose();
    _padiTagCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBanks() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('banks').get();
      final bankList = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                'name': doc.data()['name']?.toString() ?? '',
              })
          .where((b) => (b['name'] as String).isNotEmpty)
          .toList()
        ..sort((a, b) =>
            (a['name'] as String).compareTo(b['name'] as String));
      if (mounted) {
        setState(() {
          _banks = bankList;
          _loadingBanks = false;
          // Resolve bank ID from stored name when editing
          if (_selectedBankName != null && _selectedBankId == null) {
            final matched = _banks.cast<Map<String, dynamic>?>().firstWhere(
                  (b) =>
                      b!['name'].toString().toLowerCase() ==
                      _selectedBankName!.toLowerCase(),
                  orElse: () => null,
                );
            if (matched != null) _selectedBankId = matched['id']?.toString();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBanks = false);
    }
  }

  void _onAccountNumberChanged() {
    setState(() {
      _verifiedName = null;
      _verifyError = null;
    });
    if (_accountNumberCtrl.text.length == 10) {
      _autoLookupAndVerify(_accountNumberCtrl.text);
    }
  }

  /// First tries the counterparties cache (fast, auto-fills bank + name).
  /// Falls back to _verifyAccount() if bank is already selected.
  Future<void> _autoLookupAndVerify(String accountNumber) async {
    if (accountNumber.length != 10) return;
    setState(() {
      _verifyingAccount = true;
      _verifyError = null;
      _verifiedName = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('recipientAccountNumber', isEqualTo: accountNumber)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final String? bankId = data['recipientBankCode'] as String?;
        final String? accountName =
            data['data']?['attributes']?['accountName'] as String? ??
                data['attributes']?['accountName'] as String? ??
                data['accountName'] as String?;
        final String? bankName =
            data['bankName'] as String? ??
                data['data']?['attributes']?['bank']?['name'] as String?;

        // Try to match bank against loaded list
        Map<String, dynamic>? bankMatch;
        if (bankId != null) {
          bankMatch = _banks.cast<Map<String, dynamic>?>().firstWhere(
                (b) => b!['id'] == bankId,
                orElse: () => null,
              );
        }
        if (bankMatch == null && bankName != null) {
          bankMatch = _banks.cast<Map<String, dynamic>?>().firstWhere(
                (b) =>
                    b!['name'].toString().toLowerCase() ==
                    bankName.toLowerCase(),
                orElse: () => null,
              );
        }
        if (bankMatch != null && mounted) {
          setState(() {
            _selectedBankId = bankMatch!['id']?.toString();
            _selectedBankName = bankMatch['name']?.toString();
            if (accountName != null) _verifiedName = accountName;
            _verifyingAccount = false;
          });
          return;
        }
      }
    } catch (_) {}
    // Counterparty not found  fall back to direct verify if bank already set
    if (!mounted) return;
    if (_selectedBankId != null) {
      await _verifyAccount();
    } else {
      setState(() => _verifyingAccount = false);
    }
  }

  void _onTagChanged() {
    _tagDebounce?.cancel();
    final cleaned = _padiTagCtrl.text.trim().replaceAll('@', '');
    setState(() {
      _tagValid = null;
      _tagFoundName = null;
    });
    if (cleaned.length < 3 ||
        !RegExp(r'^[a-zA-Z0-9_]{1,20}$').hasMatch(cleaned)) return;
    _tagDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkPadiTag(cleaned),
    );
  }

  Future<void> _verifyAccount() async {
    if (_accountNumberCtrl.text.length != 10 || _selectedBankId == null) return;
    setState(() {
      _verifyingAccount = true;
      _verifyError = null;
      _verifiedName = null;
    });
    try {
      final docId = '${_selectedBankId}_${_accountNumberCtrl.text}';
      final cached = await FirebaseFirestore.instance
          .collection('verified_accounts')
          .doc(docId)
          .get();
      if (cached.exists && mounted) {
        setState(() {
          _verifiedName = cached.data()!['accountName']?.toString();
          _verifyingAccount = false;
        });
        return;
      }
      final result = await FirebaseFunctions.instance
          .httpsCallable('safehavenNameEnquiry')
          .call({
        'accountNumber': _accountNumberCtrl.text,
        'bankIdOrBankCode': _selectedBankId,
      });
      final name =
          result.data['data']['attributes']['accountName']?.toString();
      await FirebaseFirestore.instance
          .collection('verified_accounts')
          .doc(docId)
          .set({
        'accountName': name,
        'verifiedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _verifiedName = name;
          _verifyingAccount = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _verifyError = 'Could not verify account. Check number and bank.';
          _verifyingAccount = false;
        });
      }
    }
  }

  Future<void> _saveToFirestore(PadiAlias alias) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('padi_aliases');
    if (widget.editing != null) {
      await col
          .doc(widget.editing!.id)
          .set(alias.toFirestore(), SetOptions(merge: true));
    } else {
      await col.add({
        ...alias.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _checkPadiTag(String tag) async {
    setState(() => _checkingTag = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(tag.toLowerCase())
          .get();
      if (!mounted) return;
      if (!doc.exists) {
        setState(() {
          _tagValid = false;
          _tagFoundName = null;
          _checkingTag = false;
        });
        return;
      }
      final uid = doc.data()?['uid'] as String?;
      if (uid == null) {
        setState(() {
          _tagValid = false;
          _checkingTag = false;
        });
        return;
      }
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final firstName = userDoc.data()?['firstName']?.toString() ?? '';
      final lastName = userDoc.data()?['lastName']?.toString() ?? '';
      if (mounted) {
        setState(() {
          _tagValid = true;
          _tagFoundName =
              '$firstName $lastName'.trim().isEmpty ? null : '$firstName $lastName'.trim();
          _checkingTag = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tagValid = false;
          _checkingTag = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == 'account') {
      if (_selectedBankId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a bank')));
        return;
      }
      if (_verifyingAccount) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Still verifying account, please wait...')));
        return;
      }
      if (_verifiedName == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please verify the account number first')));
        return;
      }
    }
    if (_type == 'tag') {
      if (_checkingTag) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Still checking PadiTag, please wait...')));
        return;
      }
      if (_tagValid != true) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a valid PadiTag')));
        return;
      }
    }

    final alias = PadiAlias(
      id: widget.editing?.id ?? '',
      alias: _aliasCtrl.text.trim(),
      aliasKey: _aliasCtrl.text.trim().toLowerCase(),
      type: _type,
      displayName: _type == 'account' ? _verifiedName : _tagFoundName,
      accountNumber:
          _type == 'account' ? _accountNumberCtrl.text.trim() : null,
      bankName: _type == 'account' ? _selectedBankName : null,
      padiTag: _type == 'tag'
          ? _padiTagCtrl.text.trim().toLowerCase().replaceAll('@', '')
          : null,
    );

    setState(() => _saving = true);
    try {
      await _saveToFirestore(alias);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPad),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(isEditing ? 'Edit Contact' : 'Add Contact',
                  style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),

              // Alias name
              _label('Nickname / Alias *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _aliasCtrl,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _inputDecor('e.g. Mum, Big Sis, Office'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a nickname';
                  if (v.trim().length < 2) return 'At least 2 characters';
                  if (widget.aliasExists(v.trim()))
                    return 'A contact with this name already exists';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Type selector
              _label('Contact Type'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _typeChip('Account Number', 'account'),
                  const SizedBox(width: 10),
                  _typeChip('PadiTag', 'tag'),
                ],
              ),
              const SizedBox(height: 16),

              //  Account fields 
              if (_type == 'account') ...[
                _label('Account Number *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _accountNumberCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 10,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration:
                      _inputDecor('10-digit account number').copyWith(counterText: ''),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter account number';
                    if (v.trim().length != 10) return 'Must be exactly 10 digits';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _label('Bank *'),
                const SizedBox(height: 6),
                _loadingBanks
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: primaryColor, strokeWidth: 2)),
                      )
                    : DropdownSearch<String>(
                        popupProps: PopupProps.menu(
                          menuProps: const MenuProps(
                              backgroundColor: Colors.white),
                          searchFieldProps: TextFieldProps(
                            decoration: InputDecoration(
                              hintText: 'Search bank...',
                              hintStyle: const TextStyle(fontSize: 14),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          showSearchBox: true,
                          fit: FlexFit.loose,
                          constraints: const BoxConstraints(maxHeight: 280),
                          itemBuilder: (ctx, item, isDisabled, isSelected) =>
                              ListTile(
                            title: Text(item,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                        items: (filter, _) async => _banks
                            .where((b) => (b['name'] as String)
                                .toLowerCase()
                                .contains(filter.toLowerCase()))
                            .map((b) => b['name'] as String)
                            .toList(),
                        decoratorProps: DropDownDecoratorProps(
                          decoration: _inputDecor('Select bank'),
                        ),
                        selectedItem: _selectedBankName,
                        onChanged: (value) {
                          if (value == null) return;
                          final bank = _banks.firstWhere(
                              (b) => b['name'] == value,
                              orElse: () => {});
                          setState(() {
                            _selectedBankName = value;
                            _selectedBankId = bank['id']?.toString();
                            _verifiedName = null;
                            _verifyError = null;
                          });
                          if (_accountNumberCtrl.text.length == 10) {
                            _verifyAccount();
                          }
                        },
                      ),
                const SizedBox(height: 12),
                // Account verification status
                if (_verifyingAccount)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: primaryColor),
                        ),
                        const SizedBox(width: 10),
                        Text('Verifying account...',
                            style: GoogleFonts.inter(
                                fontSize: 13, color: Colors.grey[500])),
                      ],
                    ),
                  )
                else if (_verifiedName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green[600], size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_verifiedName!,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[800])),
                        ),
                      ],
                    ),
                  )
                else if (_verifyError != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red[600], size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_verifyError!,
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.red[700])),
                        ),
                      ],
                    ),
                  ),

              //  PadiTag fields 
              ] else ...[
                _label('PadiTag / Username *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _padiTagCtrl,
                  style: GoogleFonts.inter(fontSize: 14),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_]')),
                  ],
                  decoration: _inputDecor('username (without @)').copyWith(
                    prefixText: '@',
                    prefixStyle: GoogleFonts.inter(
                        fontSize: 14, color: Colors.grey[600]),
                    suffixIcon: _checkingTag
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: primaryColor),
                            ),
                          )
                        : _tagValid == true
                            ? Icon(Icons.check_circle,
                                color: Colors.green[600], size: 20)
                            : _tagValid == false
                                ? Icon(Icons.cancel,
                                    color: Colors.red[600], size: 20)
                                : null,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter a PadiTag';
                    final cleaned = v.trim().replaceAll('@', '');
                    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(cleaned)) {
                      return '3-20 characters: letters, numbers, underscores only';
                    }
                    return null;
                  },
                ),
                if (_tagValid == true && _tagFoundName != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green[600], size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_tagFoundName!,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[800])),
                        ),
                      ],
                    ),
                  ),
                ] else if (_tagValid == false) ...[
                  const SizedBox(height: 6),
                  Text('No PadiPay user found with this tag',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.red[600])),
                ],
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        primaryColor.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(isEditing ? 'Save Changes' : 'Add Contact',
                          style: GoogleFonts.inter(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey[600]));

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryColor),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
      );

  Widget _typeChip(String label, String value) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primaryColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: selected ? primaryColor : Colors.grey[300]!),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : Colors.black54,
            )),
      ),
    );
  }
}

