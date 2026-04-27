import 'dart:async';
import 'package:card_app/my_padi/my_padi_service.dart';
import 'package:card_app/my_padi/padi_aliases_page.dart';
import 'package:card_app/utils.dart';
import 'package:card_app/airtimes/buy_airtime.dart';
import 'package:card_app/transfer/bank_transfer_page.dart';
import 'package:card_app/bills/pay_bills.dart';
import 'package:card_app/ghost_mode/ghost_mode.dart';
import 'package:card_app/account_statement/account_statement.dart';
import 'package:card_app/home_pages/card_page.dart';
import 'package:card_app/loans/loan_page.dart';
import 'package:card_app/giveaway/targeted_giveaway_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class MyPadiPage extends StatefulWidget {
  const MyPadiPage({super.key});

  @override
  State<MyPadiPage> createState() => _MyPadiPageState();
}

class _MyPadiPageState extends State<MyPadiPage> {
  final MyPadiService _padiService = MyPadiService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isInitializing = true;
  String _currentSessionId = const Uuid().v4();
  String _selectedLangCode = 'en';

  // Quick actions built from current language
  List<_QuickAction> get _quickActions {
    final lang = _currentLang;
    return [
      _QuickAction(lang.sendMoney, Icons.send_rounded),
      _QuickAction(lang.buyAirtime, Icons.phone_android),
      _QuickAction(lang.payBills, Icons.receipt_long),
      _QuickAction(lang.myBalance, Icons.account_balance_wallet),
      _QuickAction(lang.transactions, Icons.history),
      _QuickAction(lang.ghostMode, Icons.visibility_off),
    ];
  }

  PadiLanguage get _currentLang => padiLanguages.firstWhere(
        (l) => l.code == _selectedLangCode,
        orElse: () => padiLanguages.first,
      );

  String get _greetingText {
    final name = _padiService.userFirstName;
    final base = _currentLang.greeting;
    if (name.isEmpty) return base;
    // Insert name naturally: "Hey! I'm MyPadi 👋" → "Hey [Name]! I'm MyPadi 👋"
    // For non-English greetings that don't start with "Hey", append name after first word
    return base.replaceFirstMapped(
      RegExp(r'^(Hey|Sannu|Nnọọ|Ẹ|Mbok|Azahan|Jaraama|Boro|Wúsalam|Kpecin|How)'),
      (m) => '${m[0]} $name',
    );
  }

  @override
  void initState() {
    super.initState();
    _initPadi();
  }

  Future<void> _initPadi() async {
    await _padiService.initialize(langCode: _selectedLangCode);
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  // ── Language switching ──────────────────────────────────────────────────

  Future<void> _onLanguageChanged(String langCode) async {
    if (langCode == _selectedLangCode) return;
    setState(() => _selectedLangCode = langCode);
    await _padiService.switchLanguage(langCode);
  }

  // ── Aliases / Contacts ────────────────────────────────────────────────

  void _openAliases() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PadiAliasesPage()),
    );
    // Reload aliases into the service after user may have edited contacts
    if (mounted) await _padiService.reloadAliases();
  }

  // ── Chat history ──────────────────────────────────────────────────────

  void _showChatHistory() async {
    final sessions = await MyPadiService.loadChatHistory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, controller) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('Chat History',
                      style: GoogleFonts.inter(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startNewChat();
                    },
                    child: Text('New Chat',
                        style: GoogleFonts.inter(
                            color: primaryColor, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (sessions.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('No previous chats',
                          style: GoogleFonts.inter(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final session = sessions[i];
                    return Dismissible(
                      key: Key(session.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red[50],
                        child: const Icon(Icons.delete, color: Colors.red),
                      ),
                      onDismissed: (_) {
                        MyPadiService.deleteChat(session.id);
                      },
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Text(session.title,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w500, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${session.messages.length} messages · ${_formatDate(session.lastMessageAt)}',
                          style: GoogleFonts.inter(
                              color: Colors.grey[600], fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          Navigator.pop(ctx);
                          _loadSession(session);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  void _loadSession(PadiChatSession session) {
    setState(() {
      _currentSessionId = session.id;
      _messages.clear();
      _messages.addAll(session.messages);
    });
    _scrollToBottom();
  }

  void _startNewChat() {
    // Save current chat first
    _saveCurrentChat();
    setState(() {
      _currentSessionId = const Uuid().v4();
      _messages.clear();
    });
    _padiService.switchLanguage(_selectedLangCode);
  }

  Future<void> _saveCurrentChat() async {
    if (_messages.isEmpty) return;
    final title = _messages.first.text.length > 50
        ? '${_messages.first.text.substring(0, 50)}...'
        : _messages.first.text;
    await MyPadiService.saveChat(_currentSessionId, title, _messages);
  }

  // ── Send message ──────────────────────────────────────────────────────

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    _messageController.clear();

    setState(() {
      _messages.add(ChatMessage(text: text.trim(), isUser: true));
      _isTyping = true;
    });
    _scrollToBottom();

    _padiService.lastAction = null;
    String lastText = '';

    _padiService.sendMessageStream(text.trim()).listen(
      (partial) {
        lastText = partial;
        setState(() {
          // Update last AI message or add new one
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last = ChatMessage(text: partial, isUser: false);
          } else {
            _messages.add(ChatMessage(text: partial, isUser: false));
          }
        });
        _scrollToBottom();
      },
      onDone: () {
        setState(() => _isTyping = false);

        // Attach action result if present
        if (_padiService.lastAction != null &&
            _padiService.lastAction!.action != PadiAction.none) {
          final action = _padiService.lastAction!;
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last = ChatMessage(
              text: lastText,
              isUser: false,
              actionResult: action,
            );
          }
        }

        _saveCurrentChat();
        _scrollToBottom();
      },
      onError: (err) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
              text: 'Sorry, something went wrong. Please try again.',
              isUser: false));
        });
      },
    );
  }

  void _handleQuickAction(_QuickAction action) {
    // Always send in English so the AI understands the intent
    final lang = _currentLang;
    final englishLabel = _toEnglishIntent(action.label, lang);
    _sendMessage(englishLabel);
  }

  String _toEnglishIntent(String label, PadiLanguage lang) {
    if (label == lang.sendMoney) return 'Send Money';
    if (label == lang.buyAirtime) return 'Buy Airtime';
    if (label == lang.payBills) return 'Pay Bills';
    if (label == lang.myBalance) return 'My Balance';
    if (label == lang.transactions) return 'My recent transactions';
    if (label == lang.ghostMode) return 'Open Ghost Mode';
    return label;
  }

  // ── Action navigation ─────────────────────────────────────────────────

  void _executeAction(PadiActionResult result) {
    final params = result.params;
    switch (result.action) {
      case PadiAction.transfer:
        navigateTo(
          context,
          BankTransferPage(
            initialAccountNumber: params['account_number']?.toString(),
            initialAmount: params['amount']?.toString(),
            initialBankName: params['bank_name']?.toString(),
          ),
        );
        break;
      case PadiAction.buyAirtime:
        navigateTo(
          context,
          BuyAirtimePage(
            initialPhone: params['phone_number']?.toString(),
            initialAmount: params['amount']?.toString(),
            initialNetwork: params['network']?.toString(),
          ),
        );
        break;
      case PadiAction.payBill:
        navigateTo(context, PayBillsPage(
          initialBillType: params['bill_type']?.toString(),
        ));
        break;
      case PadiAction.openGhostMode:
        navigateTo(context, const GhostModeTransfer());
        break;
      // case PadiAction.generateStatement:
      //   navigateTo(context, const AccountStatementPage());
      //   break;
      case PadiAction.openCards:
        navigateTo(context, const CardsPage());
        break;
      case PadiAction.openLoans:
        navigateTo(context, const LoanPage());
        break;
      case PadiAction.openGiveaway:
        final rawTags = params['tags'];
        final tags = rawTags is List
            ? rawTags.map((t) => t.toString()).toList()
            : <String>[];
        navigateTo(context, TargetedGiveawayPage(
          initialTags: tags.isNotEmpty ? tags : null,
          initialAmountPerPerson: params['amount_per_person']?.toString(),
        ));
        break;
      default:
        break;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isInitializing
                  ? const Center(
                      child: CircularProgressIndicator(color: primaryColor))
                  : _messages.isEmpty
                      ? _buildWelcome()
                      : _buildMessageList(),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Header with back button, title, language selector, history ────────

  Widget _buildHeader() {
    final langLabel = padiLanguages
        .firstWhere((l) => l.code == _selectedLangCode,
            orElse: () => padiLanguages.first)
        .label;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
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
            child: const Icon(Icons.auto_awesome, color: primaryColor, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('MyPadi',
                style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ),
          // Language selector — compact chip/dropdown
          _buildLanguageSelector(langLabel),
          const SizedBox(width: 4),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined, color: primaryColor, size: 22),
              tooltip: 'New Chat',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _startNewChat,
            ),
          IconButton(
            icon: const Icon(Icons.contacts, color: Colors.black54, size: 22),
            tooltip: 'My Contacts',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _openAliases,
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black54, size: 22),
            tooltip: 'Chat History',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _showChatHistory,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector(String currentLabel) {
    return PopupMenuButton<String>(
      onSelected: _onLanguageChanged,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      itemBuilder: (_) => padiLanguages.map((lang) {
        final selected = lang.code == _selectedLangCode;
        return PopupMenuItem<String>(
          value: lang.code,
          child: Row(
            children: [
              if (selected)
                const Icon(Icons.check, size: 16, color: primaryColor)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text(lang.label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? primaryColor : Colors.black87,
                  )),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentLabel,
                style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  // ── Welcome screen ────────────────────────────────────────────────────

  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_awesome, color: primaryColor, size: 32),
          ),
          const SizedBox(height: 16),
          Text(_greetingText,
          textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(
            _currentLang.subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: _quickActions
                .map((a) => _buildQuickActionChip(a))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip(_QuickAction action) {
    return InkWell(
      onTap: () => _handleQuickAction(action),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 16, color: primaryColor),
            const SizedBox(width: 6),
            Text(action.label,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  // ── Messages list ─────────────────────────────────────────────────────

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) return _buildTypingIndicator();
        return _buildMessageBubble(_messages[i]);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? primaryColor : Colors.grey[100],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                msg.text,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isUser ? Colors.white : Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
            // Action button
            if (!isUser && msg.actionResult != null && msg.actionResult!.action != PadiAction.none)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  onTap: () => _executeAction(msg.actionResult!),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getActionIcon(msg.actionResult!.action),
                            size: 16, color: primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          _getActionLabel(msg.actionResult!.action),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios,
                            size: 12, color: primaryColor),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getActionIcon(PadiAction action) {
    switch (action) {
      case PadiAction.transfer: return Icons.send_rounded;
      case PadiAction.buyAirtime: return Icons.phone_android;
      case PadiAction.payBill: return Icons.receipt_long;
      case PadiAction.checkBalance: return Icons.account_balance_wallet;
      case PadiAction.viewTransactions: return Icons.history;
      case PadiAction.generateStatement: return Icons.description;
      case PadiAction.openGhostMode: return Icons.visibility_off;
      case PadiAction.openGiveaway: return Icons.card_giftcard;
      case PadiAction.openCards: return Icons.credit_card;
      case PadiAction.openLoans: return Icons.savings;
      default: return Icons.open_in_new;
    }
  }

  String _getActionLabel(PadiAction action) {
    switch (action) {
      case PadiAction.transfer: return 'Open Transfer';
      case PadiAction.buyAirtime: return 'Buy Airtime';
      case PadiAction.payBill: return 'Pay Bill';
      case PadiAction.checkBalance: return 'View Balance';
      case PadiAction.viewTransactions: return 'View Transactions';
      case PadiAction.generateStatement: return 'View Statement';
      case PadiAction.openGhostMode: return 'Open Ghost Mode';
      case PadiAction.openGiveaway: return 'Open Giveaway';
      case PadiAction.openCards: return 'Open Cards';
      case PadiAction.openLoans: return 'Open Loans';
      default: return 'Open';
    }
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4, right: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 600 + i * 200),
              builder: (_, value, child) => Opacity(
                opacity: 0.3 + 0.7 * value,
                child: child,
              ),
              child: Container(
                margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(fontSize: 14),
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: _currentLang.inputHint,
                  hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: () => _sendMessage(_messageController.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  const _QuickAction(this.label, this.icon);
}
