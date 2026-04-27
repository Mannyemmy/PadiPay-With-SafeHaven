import 'dart:async';
import 'package:card_app/my_padi/padi_aliases_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kGeminiApiKey = 'AIzaSyAsQ8zSoIKzK89Qh8PwijvYOjp6486VRP8';

/// Actions that MyPadi can trigger — the UI layer handles navigation.
enum PadiAction {
  transfer,
  buyAirtime,
  payBill,
  viewTransactions,
  checkBalance,
  generateStatement,
  openGhostMode,
  openGiveaway,
  openCards,
  openLoans,
  none,
}

class PadiActionResult {
  final PadiAction action;
  final Map<String, dynamic> params;
  PadiActionResult(this.action, [this.params = const {}]);

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'params': params,
      };

  factory PadiActionResult.fromJson(Map<String, dynamic> json) {
    return PadiActionResult(
      PadiAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => PadiAction.none,
      ),
      Map<String, dynamic>.from(json['params'] ?? {}),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final PadiActionResult? actionResult;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.actionResult,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.millisecondsSinceEpoch,
        if (actionResult != null) 'actionResult': actionResult!.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] ?? '',
      isUser: json['isUser'] ?? false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] ?? 0),
      actionResult: json['actionResult'] != null
          ? PadiActionResult.fromJson(
              Map<String, dynamic>.from(json['actionResult']))
          : null,
    );
  }
}

/// A saved chat session summary.
class PadiChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final List<ChatMessage> messages;

  PadiChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastMessageAt,
    required this.messages,
  });
}

// ── Language definitions ───────────────────────────────────────────────────

class PadiLanguage {
  final String code;
  final String label;
  final String instruction;

  // UI strings
  final String greeting;       // "Hey! I'm MyPadi 👋"
  final String subtitle;       // "Your personal financial assistant…"
  final String inputHint;      // "Ask MyPadi anything…"
  final String sendMoney;
  final String buyAirtime;
  final String payBills;
  final String myBalance;
  final String transactions;
  final String ghostMode;

  const PadiLanguage({
    required this.code,
    required this.label,
    required this.instruction,
    required this.greeting,
    required this.subtitle,
    required this.inputHint,
    required this.sendMoney,
    required this.buyAirtime,
    required this.payBills,
    required this.myBalance,
    required this.transactions,
    required this.ghostMode,
  });
}

const List<PadiLanguage> padiLanguages = [
  PadiLanguage(
    code: 'en',
    label: 'English',
    instruction:
        'Respond in clear, concise English. You may sprinkle in light Nigerian expressions naturally.',
    greeting: "Hey! I'm MyPadi 👋",
    subtitle: "Your personal financial assistant.\nHow can I help you today?",
    inputHint: "Ask MyPadi anything...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'pcm',
    label: 'Pidgin',
    instruction:
        'Respond entirely in Nigerian Pidgin English. Use natural Pidgin grammar and expressions. E.g. "Wetin you wan do?", "E don work!", "No wahala, I go help you."',
    greeting: "How you dey! Na me be MyPadi 👋",
    subtitle: "Your personal money assistant.\nWetin you wan do today?",
    inputHint: "Ask MyPadi anything...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'yo',
    label: 'Yorùbá',
    instruction:
        'Respond in Yorùbá language. Use proper Yorùbá grammar with tone marks where possible. You may mix in English words for financial/technical terms that have no direct Yorùbá equivalent.',
    greeting: "Ẹ káàbọ̀! Èmi ni MyPadi 👋",
    subtitle: "Olùrànlọ́wọ́ ọrọ̀ajé rẹ.\nKí ni mo lè ṣe fún ọ lónìí?",
    inputHint: "Béèrè lọ́wọ́ MyPadi ohunkóhun...",
    sendMoney: "Fi Owó Ránṣẹ́",
    buyAirtime: "Rà Airtime",
    payBills: "San Ìwé Àjọ",
    myBalance: "Iye Owó Mi",
    transactions: "Àwọn Iṣòwò",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'ha',
    label: 'Hausa',
    instruction:
        'Respond in Hausa language. Use proper Hausa grammar. You may use English words for financial/technical terms that have no direct Hausa equivalent.',
    greeting: "Sannu! Ni ne MyPadi 👋",
    subtitle: "Mai taimaka maka wajen kudi.\nMe kake so a yau?",
    inputHint: "Tambaya MyPadi komai...",
    sendMoney: "Aika Kudi",
    buyAirtime: "Sayi Airtime",
    payBills: "Biya Lissafi",
    myBalance: "Kudin Nawa",
    transactions: "Ma'amaloli",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'ig',
    label: 'Igbo',
    instruction:
        'Respond in Igbo language. Use proper Igbo grammar. You may use English words for financial/technical terms that have no direct Igbo equivalent.',
    greeting: "Nnọọ! Abụ m MyPadi 👋",
    subtitle: "Onye enyemaka ego gị.\nGịnị ka m nwere ike ime ụbọchị a?",
    inputHint: "Jụọ MyPadi ihe ọ bụla...",
    sendMoney: "Ziga Ego",
    buyAirtime: "Zụọ Airtime",
    payBills: "Kwụọ Ụgwọ",
    myBalance: "Ego M",
    transactions: "Azụmahịa",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'efi',
    label: 'Efik',
    instruction:
        'Respond in Efik language. Use proper Efik grammar. You may use English words for financial/technical terms.',
    greeting: "Mbok! Ami enye MyPadi 👋",
    subtitle: "Mmọ ẹnye ukeme ke mkpọ.\nÀnyà ami ima ke nnyin?",
    inputHint: "Jụọ MyPadi ihe ọ bụla...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'tiv',
    label: 'Tiv',
    instruction:
        'Respond in Tiv language. Use proper Tiv grammar. You may use English words for financial/technical terms.',
    greeting: "Azahan! Nyi MyPadi 👋",
    subtitle: "Mba sha sha kwase u ngohol.\nNea u vivi?",
    inputHint: "Bisa MyPadi sha sha...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'ful',
    label: 'Fulfulde',
    instruction:
        'Respond in Fulfulde language. Use proper Fulfulde grammar. You may use English words for financial/technical terms.',
    greeting: "Jaraama! Min woni MyPadi 👋",
    subtitle: "Ballotooɗo maa e ngoluɗe.\nHol ko mbaawtotooɗo haɓɓude?",
    inputHint: "Laar MyPadi fewdo...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'ijn',
    label: 'Ijaw',
    instruction:
        'Respond in Ijaw (Izon) language. Use proper Ijaw grammar. You may use English words for financial/technical terms.',
    greeting: "Boro! Ayiba MyPadi 👋",
    subtitle: "Boro piri owo yenagoa.\nBenikiri mi kiri?",
    inputHint: "Kiri MyPadi boro...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'kan',
    label: 'Kanuri',
    instruction:
        'Respond in Kanuri language. Use proper Kanuri grammar. You may use English words for financial/technical terms.',
    greeting: "Wúsalam! Nyi MyPadi 👋",
    subtitle: "Kalangu dibe wúro.\nKa wú fəlgin?",
    inputHint: "Sa MyPadi fəlgin...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
  PadiLanguage(
    code: 'nup',
    label: 'Nupe',
    instruction:
        'Respond in Nupe language. Use proper Nupe grammar. You may use English words for financial/technical terms.',
    greeting: "Kpecin! Nyi MyPadi 👋",
    subtitle: "Wuya egi ezun.\nEgi nkoci?",
    inputHint: "Biza MyPadi egi...",
    sendMoney: "Send Money",
    buyAirtime: "Buy Airtime",
    payBills: "Pay Bills",
    myBalance: "My Balance",
    transactions: "Transactions",
    ghostMode: "Ghost Mode",
  ),
];

// ── Service ───────────────────────────────────────────────────────────────

class MyPadiService {
  GenerativeModel? _model;
  late ChatSession _chat;
  bool _initialized = false;
  String _currentLangCode = 'en';

  // Cached user context
  String _userName = '';
  String _userFirstName = '';
  String _userTag = '';
  String _accountNumber = '';
  String _cachedBalance = '';
  String _tier = '';
  List<Map<String, dynamic>> _recentTransactions = [];
  List<PadiAlias> _aliases = [];

  String get userName => _userName;
  String get userFirstName => _userFirstName;

  String get currentLangCode => _currentLangCode;

  // ── Function declarations for Gemini ──────────────────────────────────────

  static final _functionDeclarations = [
    FunctionDeclaration(
      'transfer_money',
      'Initiate a bank transfer. Returns pre-filled transfer details for the user to confirm.',
      Schema.object(properties: {
        'recipient_name': Schema.string(
            description: 'Name or PadiTag of the recipient', nullable: true),
        'amount':
            Schema.number(description: 'Amount in Naira', nullable: true),
        'bank_name':
            Schema.string(description: 'Recipient bank name', nullable: true),
        'account_number': Schema.string(
            description: 'Recipient account number', nullable: true),
      }),
    ),
    FunctionDeclaration(
      'buy_airtime',
      'Buy airtime/data for a phone number.',
      Schema.object(properties: {
        'phone_number': Schema.string(
            description: 'Phone number (Nigerian format)', nullable: true),
        'amount':
            Schema.number(description: 'Airtime amount in Naira', nullable: true),
        'network': Schema.string(
            description: 'Network: MTN, Airtel, Glo, or 9mobile',
            nullable: true),
      }),
    ),
    FunctionDeclaration(
      'pay_bill',
      'Pay a bill (electricity, cable TV, data, internet).',
      Schema.object(properties: {
        'bill_type': Schema.string(
            description: 'Type: electricity, cable, data, internet',
            nullable: true),
        'provider':
            Schema.string(description: 'Service provider', nullable: true),
        'amount':
            Schema.number(description: 'Bill amount in Naira', nullable: true),
      }),
    ),
    FunctionDeclaration(
      'check_balance',
      'Check the user\'s current account balance.',
      Schema.object(properties: {}),
    ),
    FunctionDeclaration(
      'search_transactions',
      'Search or list recent transactions by criteria.',
      Schema.object(properties: {
        'query': Schema.string(
            description: 'Search: name, type (airtime, transfer, bill), or date',
            nullable: true),
        'limit': Schema.integer(
            description: 'Max results (default 10)', nullable: true),
      }),
    ),
    FunctionDeclaration(
      'generate_statement',
      'Generate an account statement for a date range.',
      Schema.object(properties: {
        'start_date':
            Schema.string(description: 'Start date (YYYY-MM-DD)', nullable: true),
        'end_date':
            Schema.string(description: 'End date (YYYY-MM-DD)', nullable: true),
      }),
    ),
    FunctionDeclaration(
      'do_giveaway',
      'Create a giveaway — send money to multiple PadiTag recipients. Use this whenever the user mentions giveaway, sharing money to multiple people by their tags/usernames, or distributing money to a list of people.',
      Schema.object(properties: {
        'tags': Schema.array(
            items: Schema.string(),
            description: 'List of PadiTag usernames (without @) of recipients'),
        'amount_per_person': Schema.number(
            description: 'Amount in Naira each person receives', nullable: true),
      }),
    ),
    FunctionDeclaration(
      'open_feature',
      'Navigate to a specific app feature/page. Do NOT use this for giveaway when you have recipient tags — use do_giveaway instead.',
      Schema.object(properties: {
        'feature': Schema.string(
            description:
                'Feature: ghost_mode, cards, loans, transfer, airtime, bills, profile'),
      }),
    ),
    FunctionDeclaration(
      'get_spending_summary',
      'Analyze spending patterns from recent transactions.',
      Schema.object(properties: {
        'period': Schema.string(
            description: 'Period: today, this_week, this_month, last_month',
            nullable: true),
      }),
    ),
    FunctionDeclaration(
      'submit_support_ticket',
      'Submit a customer support ticket when the user has a complaint, issue, or request that cannot be resolved in chat (e.g. failed transaction not reversed, account frozen, KYC issues, disputes).',
      Schema.object(properties: {
        'subject': Schema.string(description: 'Short summary of the issue'),
        'description': Schema.string(description: 'Full description of the problem as reported by the user'),
        'category': Schema.string(
            description:
                'Category: failed_transaction, account_issue, kyc, fraud, billing, other',
            nullable: true),
      }),
    ),
  ];

  // ── Initialization ────────────────────────────────────────────────────────

  Future<void> initialize({String langCode = 'en'}) async {
    _currentLangCode = langCode;

    if (!_initialized) {
      await _loadUserContext();
    }

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _kGeminiApiKey,
      tools: [Tool(functionDeclarations: _functionDeclarations)],
      systemInstruction: Content.text(_buildSystemPrompt()),
    );

    _chat = _model!.startChat();
    _initialized = true;
  }

  /// Re-initializes with a new language (keeps cached user context).
  Future<void> switchLanguage(String langCode) async {
    _currentLangCode = langCode;
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _kGeminiApiKey,
      tools: [Tool(functionDeclarations: _functionDeclarations)],
      systemInstruction: Content.text(_buildSystemPrompt()),
    );
    _chat = _model!.startChat();
  }

  Future<void> _loadUserContext() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        _userName =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        _userFirstName = (data['firstName'] ?? '').toString().trim();
        _userTag = data['userName'] ?? '';
        _tier = (data['getAnchorData']?['tier'] ?? '0').toString();
        _accountNumber = data['getAnchorData']?['virtualAccount']?['data']
                    ?['attributes']?['accountNumber'] ??
                '';
      }

      final prefs = await SharedPreferences.getInstance();
      final balance = prefs.getDouble('cached_balance');
      if (balance != null) {
        _cachedBalance = '₦${NumberFormat('#,##0.00').format(balance)}';
      }

      final sentSnap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      final receivedSnap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('receiverId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      _recentTransactions = [
        ...sentSnap.docs.map((d) => {...d.data(), '_direction': 'sent'}),
        ...receivedSnap.docs
            .map((d) => {...d.data(), '_direction': 'received'}),
      ];

      _recentTransactions.sort((a, b) {
        final ta = _parseTimestamp(a);
        final tb = _parseTimestamp(b);
        return tb.compareTo(ta);
      });

      if (_recentTransactions.length > 30) {
        _recentTransactions = _recentTransactions.sublist(0, 30);
      }

      // Load aliases
      final aliasSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('padi_aliases')
          .get();
      _aliases = aliasSnap.docs.map(PadiAlias.fromDoc).toList();
    } catch (e) {
      print('MyPadi: Error loading user context: $e');
    }
  }

  DateTime _parseTimestamp(Map<String, dynamic> data) {
    final ts =
        data['timestamp'] ?? data['createdAtFirestore'] ?? data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _buildSystemPrompt() {
    final lang = padiLanguages.firstWhere(
      (l) => l.code == _currentLangCode,
      orElse: () => padiLanguages.first,
    );

    final txSummary = _recentTransactions.take(15).map((tx) {
      final type = tx['type'] ?? 'unknown';
      final amount = tx['amount'] ?? 0;
      // atm_payment is always stored as 'sent' but is actually money received
      final rawDir = tx['_direction'] ?? 'sent';
      final dir = type == 'atm_payment' ? 'received' : rawDir;
      final status = tx['status'] ?? '';
      final ts = _parseTimestamp(tx);
      final dateStr = DateFormat('MMM d, yyyy').format(ts);
      final name =
          tx['receiverName'] ?? tx['counterpartyName'] ?? tx['network'] ?? '';
      return '- $dateStr: $dir $type ₦${NumberFormat('#,##0').format(amount)} ${name != '' ? 'to/from \$name' : ''} ($status)';
    }).join('\n');

    return '''
You are MyPadi, a friendly and helpful AI financial assistant inside the PadiPay app — a Nigerian fintech app.
Your personality: warm, concise, and smart.

LANGUAGE INSTRUCTION:
${lang.instruction}

USER CONTEXT:
- Name: $_userName
- PadiTag: $_userTag
- Account Number: $_accountNumber
- Account Tier: $_tier
- Cached Balance: $_cachedBalance

RECENT TRANSACTIONS:
$txSummary

SAVED CONTACTS (user's personal aliases / nicknames):
${_buildAliasesPrompt()}
When the user mentions any alias name, resolve it to the corresponding account or PadiTag.

CAPABILITIES — you can help users with:
1. **Transfer money** — call transfer_money with recipient details
2. **Buy airtime** — call buy_airtime with phone number and amount
3. **Pay bills** — call pay_bill for electricity, cable, data
4. **Check balance** — call check_balance to fetch real-time balance
5. **Search transactions** — call search_transactions to look up history
6. **Generate statement** — call generate_statement for date ranges
7. **Navigate the app** — call open_feature to go to specific pages
8. **Spending insights** — call get_spending_summary for analytics
9. **Giveaway** — call do_giveaway when user wants to send money to multiple people by their tags/usernames. Extract all mentioned tags/usernames. NEVER use transfer_money for giveaway requests.
10. **Customer support** — answer common questions directly. If the issue needs human intervention (failed transaction not reversed, account frozen, KYC disputes, fraud, etc.), call submit_support_ticket to log it.

CUSTOMER SUPPORT KNOWLEDGE:
- **Failed transaction / debit without credit**: Ask for the transaction date, amount, and recipient. Reassure the user that most reversals happen within 24–72 hours. If it's been longer, submit a support ticket.
- **Account frozen / restricted**: This is usually due to BVN mismatch, tier limit exceeded, or a compliance flag. Advise the user to check their profile and complete any pending verification. Escalate by submitting a ticket.
- **KYC / Tier upgrade**: Tier 1 requires BVN; Tier 2 requires a valid government ID and a selfie. Direct the user to their Profile page to upload documents.
- **Wrong transfer**: PadiPay can initiate a recall request, but reversal is not guaranteed. Collect details and submit a support ticket immediately.
- **Card issues** (virtual card declined, card frozen): Direct user to the Cards page. If still broken, submit a ticket.
- **PIN reset**: Advise user to go to Profile → Change PIN. If locked out, submit a ticket.
- **Referral / promo not credited**: Collect referral code and submit a ticket.
- **App crashes or slow**: Ask the user to clear the app cache or reinstall. If it persists, submit a ticket.
- Support tickets are logged to Firestore and the support team will respond via in-app notification or email within 24 hours (business days).

RULES:
- For money actions (transfer, airtime, bills), gather the needed info conversationally. Don't call the function until you have enough details.
- For giveaway: extract ALL tags mentioned and call do_giveaway immediately — do NOT ask for bank account or bank name.
- Always confirm amounts before executing. Say something like "I'll set up a ₦X,000 transfer to [name]. Let me take you there."
- Never expose internal API details, account IDs, or error stack traces.
- If you're unsure, ask a clarifying question rather than guessing.
- Keep responses SHORT — 1-3 sentences max unless the user asks for detail.
- When providing transaction summaries, format amounts with ₦ and commas.
- Currency is always Nigerian Naira (₦ / NGN).
- IMPORTANT: "spent" and "debits" only refers to OUTGOING transactions (direction=sent) with status=successful or status=completed. NEVER count incoming credits (direction=received) or failed/pending transactions as spending.
- IMPORTANT: "atm_payment" transactions are INCOMING credits (a customer paid you via their ATM card). NEVER treat them as spending or expenses — always treat them as money received.
- Today's date is ${DateFormat('MMMM d, yyyy').format(DateTime.now())}.
''';
  }

  String _buildAliasesPrompt() {
    if (_aliases.isEmpty) return 'No contacts saved yet.';
    return _aliases.map((a) {
      if (a.type == 'tag') {
        return '- "${a.alias}" → PadiTag @${a.padiTag} (use this tag when searching transactions or sending)';
      } else {
        final parts = <String>[];
        if (a.displayName != null && a.displayName!.isNotEmpty) parts.add('name: ${a.displayName}');
        if (a.accountNumber != null) parts.add('account: ${a.accountNumber}');
        if (a.bankName != null) parts.add('bank: ${a.bankName}');
        return '- "${a.alias}" → ${parts.join(', ')}';
      }
    }).join('\n');
  }

  /// Reload aliases (call after user edits contacts).
  Future<void> reloadAliases() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('padi_aliases')
        .get();
    _aliases = snap.docs.map(PadiAlias.fromDoc).toList();
  }

  // ── Send message (streaming) ──────────────────────────────────────────────

  Stream<String> sendMessageStream(String userMessage) async* {
    if (!_initialized) await initialize(langCode: _currentLangCode);

    try {
      final response = _chat.sendMessageStream(Content.text(userMessage));
      final buffer = StringBuffer();

      await for (final chunk in response) {
        if (chunk.functionCalls.isNotEmpty) {
          for (final fc in chunk.functionCalls) {
            final result = await _handleFunctionCall(fc);
            final fnResponse = _chat.sendMessageStream(
              Content.functionResponses([
                FunctionResponse(fc.name, result),
              ]),
            );
            await for (final r in fnResponse) {
              final text = r.text;
              if (text != null && text.isNotEmpty) {
                buffer.write(text);
                yield buffer.toString();
              }
            }
          }
        }

        final text = chunk.text;
        if (text != null && text.isNotEmpty) {
          buffer.write(text);
          yield buffer.toString();
        }
      }
    } catch (e) {
      yield 'Sorry, I ran into an issue. Please try again.';
      print('MyPadi sendMessage error: $e');
    }
  }

  // ── Last action extracted from function calls ─────────────────────────────

  PadiActionResult? lastAction;

  Future<Map<String, dynamic>> _handleFunctionCall(FunctionCall fc) async {
    switch (fc.name) {
      case 'transfer_money':
        lastAction = PadiActionResult(PadiAction.transfer, {
          'recipient_name': fc.args['recipient_name'],
          'amount': fc.args['amount'],
          'bank_name': fc.args['bank_name'],
          'account_number': fc.args['account_number'],
        });
        return {'status': 'ready', 'message': 'Transfer page will open with pre-filled details.'};

      case 'buy_airtime':
        lastAction = PadiActionResult(PadiAction.buyAirtime, {
          'phone_number': fc.args['phone_number'],
          'amount': fc.args['amount'],
          'network': fc.args['network'],
        });
        return {'status': 'ready', 'message': 'Airtime purchase page will open.'};

      case 'pay_bill':
        lastAction = PadiActionResult(PadiAction.payBill, {
          'bill_type': fc.args['bill_type'],
          'provider': fc.args['provider'],
          'amount': fc.args['amount'],
        });
        return {'status': 'ready', 'message': 'Bill payment page will open.'};

      case 'check_balance':
        lastAction = PadiActionResult(PadiAction.checkBalance);
        return await _fetchLiveBalance();

      case 'search_transactions':
        lastAction = PadiActionResult(PadiAction.viewTransactions);
        return _searchTransactions(
            fc.args['query'] as String?, (fc.args['limit'] as num?)?.toInt() ?? 10);

      case 'generate_statement':
        lastAction = PadiActionResult(PadiAction.generateStatement, {
          'start_date': fc.args['start_date'],
          'end_date': fc.args['end_date'],
        });
        return {'status': 'ready', 'message': 'Account statement page will open.'};

      case 'do_giveaway':
        final rawTags = fc.args['tags'];
        final tagsList = rawTags is List
            ? rawTags.map((t) => t.toString().trim().toLowerCase().replaceAll('@', '')).where((t) => t.isNotEmpty).toList()
            : <String>[];
        lastAction = PadiActionResult(PadiAction.openGiveaway, {
          'tags': tagsList,
          'amount_per_person': fc.args['amount_per_person']?.toString(),
        });
        return {'status': 'ready', 'message': 'Giveaway page will open with ${tagsList.length} recipients pre-filled.'};

      case 'open_feature':
        final feature = fc.args['feature'] as String? ?? '';
        lastAction = PadiActionResult(_mapFeature(feature), {'feature': feature});
        return {'status': 'ready', 'message': '$feature page will open.'};

      case 'get_spending_summary':
        return _getSpendingSummary(fc.args['period'] as String? ?? 'this_month');

      case 'submit_support_ticket':
        return await _submitSupportTicket(
          subject: fc.args['subject'] as String? ?? 'Support Request',
          description: fc.args['description'] as String? ?? '',
          category: fc.args['category'] as String? ?? 'other',
        );

      default:
        return {'error': 'Unknown function'};
    }
  }

  PadiAction _mapFeature(String feature) {
    switch (feature) {
      case 'ghost_mode': return PadiAction.openGhostMode;
      case 'giveaway': return PadiAction.openGiveaway;
      case 'cards': return PadiAction.openCards;
      case 'loans': return PadiAction.openLoans;
      case 'transfer': return PadiAction.transfer;
      case 'airtime': return PadiAction.buyAirtime;
      case 'bills': return PadiAction.payBill;
      default: return PadiAction.none;
    }
  }

  Future<Map<String, dynamic>> _fetchLiveBalance() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {'error': 'Not authenticated'};

      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();

      final accountId = userDoc.data()!['getAnchorData']['virtualAccount']['data']['id']?.toString();

      final callable = FirebaseFunctions.instance.httpsCallable('fetchAccountBalance');
      final result = await callable.call({'accountId': accountId});
      final balance = (result.data['data']['availableBalance']?.toDouble() ?? 0.0) / 100;

      _cachedBalance = '₦${NumberFormat('#,##0.00').format(balance)}';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_balance', balance);

      return {'balance': _cachedBalance, 'raw_balance': balance};
    } catch (e) {
      if (_cachedBalance.isNotEmpty) {
        return {'balance': _cachedBalance, 'note': 'Cached balance — could not fetch live data.'};
      }
      return {'error': 'Unable to fetch balance right now.'};
    }
  }

  Map<String, dynamic> _searchTransactions(String? query, int limit) {
    var results = List<Map<String, dynamic>>.from(_recentTransactions);

    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      results = results.where((tx) {
        final type = (tx['type'] ?? '').toString().toLowerCase();
        final name = (tx['receiverName'] ?? tx['counterpartyName'] ?? '').toString().toLowerCase();
        final network = (tx['network'] ?? '').toString().toLowerCase();
        final status = (tx['status'] ?? '').toString().toLowerCase();
        final dir = (tx['_direction'] ?? '').toString().toLowerCase();
        // If query implies credits/debits filter
        if (q == 'credit' || q == 'received' || q == 'incoming') {
          return dir == 'received';
        }
        if (q == 'debit' || q == 'sent' || q == 'outgoing') {
          return dir == 'sent';
        }
        return type.contains(q) || name.contains(q) || network.contains(q) || status.contains(q);
      }).toList();
    }

    if (results.length > limit) results = results.sublist(0, limit);

    final formatted = results.map((tx) {
      final type = tx['type'] ?? 'unknown';
      final amount = tx['amount'] ?? 0;
      final dir = tx['_direction'] ?? 'sent';
      final status = tx['status'] ?? '';
      final ts = _parseTimestamp(tx);
      final name = tx['receiverName'] ?? tx['counterpartyName'] ?? tx['network'] ?? '';
      return {
        'type': type, 'direction': dir,
        'amount': '₦${NumberFormat('#,##0').format(amount)}',
        'date': DateFormat('MMM d, yyyy h:mm a').format(ts),
        'name': name, 'status': status,
      };
    }).toList();

    return {'count': formatted.length, 'transactions': formatted};
  }

  Map<String, dynamic> _getSpendingSummary(String period) {
    final now = DateTime.now();
    DateTime start;
    switch (period) {
      case 'today':
        start = DateTime(now.year, now.month, now.day); break;
      case 'this_week':
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day); break;
      case 'last_month':
        start = DateTime(now.year, now.month - 1, 1); break;
      case 'this_month':
      default:
        start = DateTime(now.year, now.month, 1); break;
    }

    // Only count outgoing (sent) successful/completed transactions as "spending"
    // atm_payment is stored as 'sent' but is actually money RECEIVED (credit) — exclude it
    final txInPeriod = _recentTransactions.where((tx) {
      final ts = _parseTimestamp(tx);
      final dir = (tx['_direction'] ?? '').toString();
      final type = (tx['type'] ?? '').toString();
      final status = (tx['status'] ?? '').toString().toLowerCase();
      final isDebit = dir == 'sent' && type != 'atm_payment';
      final isSuccess = status == 'successful' || status == 'completed' || status == 'success';
      return ts.isAfter(start) && isDebit && isSuccess;
    }).toList();

    final Map<String, double> byCategory = {};
    double total = 0;
    for (final tx in txInPeriod) {
      final type = (tx['type'] ?? 'other').toString();
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      byCategory[type] = (byCategory[type] ?? 0) + amount;
      total += amount;
    }

    return {
      'period': period,
      'total_spent': '₦${NumberFormat('#,##0').format(total)}',
      'transaction_count': txInPeriod.length,
      'breakdown': byCategory.entries.map((e) => {
        'category': e.key,
        'amount': '₦${NumberFormat('#,##0').format(e.value)}',
        'percentage': total > 0 ? '${(e.value / total * 100).toStringAsFixed(1)}%' : '0%',
      }).toList(),
    };
  }

  // ── Support ticket ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _submitSupportTicket({
    required String subject,
    required String description,
    required String category,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {'error': 'Not authenticated'};

      final ticketRef = FirebaseFirestore.instance
          .collection('support_tickets')
          .doc();

      await ticketRef.set({
        'ticketId': ticketRef.id,
        'userId': user.uid,
        'userName': _userName,
        'userTag': _userTag,
        'accountNumber': _accountNumber,
        'subject': subject,
        'description': description,
        'category': category,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'status': 'submitted',
        'ticketId': ticketRef.id,
        'message': 'Support ticket submitted. Our team will respond within 24 hours (business days).',
      };
    } catch (e) {
      print('MyPadi: Error submitting support ticket: $e');
      return {'error': 'Failed to submit ticket. Please try again.'};
    }
  }

  // ── Chat history persistence ──────────────────────────────────────────────

  static Future<void> saveChat(
      String sessionId, String title, List<ChatMessage> messages) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || messages.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('padi_chats')
        .doc(sessionId)
        .set({
      'title': title,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'messages': messages.map((m) => m.toJson()).toList(),
    }, SetOptions(merge: true));
  }

  static Future<List<PadiChatSession>> loadChatHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('padi_chats')
        .orderBy('lastMessageAt', descending: true)
        .limit(30)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      final msgsList = (data['messages'] as List<dynamic>?) ?? [];
      final messages = msgsList
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final createdAt = data['createdAt'];
      final lastAt = data['lastMessageAt'];
      return PadiChatSession(
        id: doc.id,
        title: data['title'] ?? 'Chat',
        createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
        lastMessageAt: lastAt is Timestamp ? lastAt.toDate() : DateTime.now(),
        messages: messages,
      );
    }).toList();
  }

  static Future<void> deleteChat(String sessionId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('padi_chats')
        .doc(sessionId)
        .delete();
  }
}
