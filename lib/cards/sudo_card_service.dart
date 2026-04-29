// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import

import 'package:cloud_functions/cloud_functions.dart';

final _functions = FirebaseFunctions.instance;

// ——— Customers ———

/// Create a Sudo customer.
Future<Map<String, dynamic>> sudoCreateCustomer({
  required String type,
  required String name,
  required String phoneNumber,
  required String status,
  required Map<String, dynamic> billingAddress,
  String? emailAddress,
  Map<String, dynamic>? individual,
  Map<String, dynamic>? company,
}) async {
  final body = <String, dynamic>{
    'type': type,
    'name': name,
    'phoneNumber': phoneNumber,
    'status': status,
    'billingAddress': billingAddress,
  };
  if (emailAddress != null) body['emailAddress'] = emailAddress;
  if (individual != null) body['individual'] = individual;
  if (company != null) body['company'] = company;

  final callable = _functions.httpsCallable('sudoCreateCustomer');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get all Sudo customers.
Future<Map<String, dynamic>> sudoGetCustomers({int? page, int? limit}) async {
  final body = <String, dynamic>{};
  if (page != null) body['page'] = page;
  if (limit != null) body['limit'] = limit;

  final callable = _functions.httpsCallable('sudoGetCustomers');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get a single Sudo customer.
Future<Map<String, dynamic>> sudoGetCustomer(String customerId) async {
  final callable = _functions.httpsCallable('sudoGetCustomer');
  final response = await callable.call({'customerId': customerId});
  return Map<String, dynamic>.from(response.data as Map);
}

/// Update a Sudo customer.
Future<Map<String, dynamic>> sudoUpdateCustomer({
  required String customerId,
  String? type,
  String? name,
  String? status,
  String? phoneNumber,
  String? emailAddress,
  Map<String, dynamic>? individual,
  Map<String, dynamic>? company,
  Map<String, dynamic>? billingAddress,
  Map<String, dynamic>? metadata,
}) async {
  final body = <String, dynamic>{'customerId': customerId};
  if (type != null) body['type'] = type;
  if (name != null) body['name'] = name;
  if (status != null) body['status'] = status;
  if (phoneNumber != null) body['phoneNumber'] = phoneNumber;
  if (emailAddress != null) body['emailAddress'] = emailAddress;
  if (individual != null) body['individual'] = individual;
  if (company != null) body['company'] = company;
  if (billingAddress != null) body['billingAddress'] = billingAddress;
  if (metadata != null) body['metadata'] = metadata;

  final callable = _functions.httpsCallable('sudoUpdateCustomer');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

// ——— Funding Sources ———

/// Create a funding source (e.g. gateway).
Future<Map<String, dynamic>> sudoCreateFundingSource({
  required String type,
  required String status,
  Map<String, dynamic>? jitGateway,
}) async {
  final body = <String, dynamic>{'type': type, 'status': status};
  if (jitGateway != null) body['jitGateway'] = jitGateway;

  final callable = _functions.httpsCallable('sudoCreateFundingSource');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get all funding sources.
Future<Map<String, dynamic>> sudoGetFundingSources() async {
  final callable = _functions.httpsCallable('sudoGetFundingSources');
  final response = await callable.call();
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get a single funding source.
Future<Map<String, dynamic>> sudoGetFundingSource(String fundingSourceId) async {
  final callable = _functions.httpsCallable('sudoGetFundingSource');
  final response = await callable.call({'fundingSourceId': fundingSourceId});
  return Map<String, dynamic>.from(response.data as Map);
}

/// Update a funding source.
Future<Map<String, dynamic>> sudoUpdateFundingSource({
  required String fundingSourceId,
  String? status,
  Map<String, dynamic>? jitGateway,
}) async {
  final body = <String, dynamic>{'fundingSourceId': fundingSourceId};
  if (status != null) body['status'] = status;
  if (jitGateway != null) body['jitGateway'] = jitGateway;

  final callable = _functions.httpsCallable('sudoUpdateFundingSource');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

// ——— Cards ———

/// Create a Sudo card.
Future<Map<String, dynamic>> sudoCreateCard({
  required String customerId,
  required String type,
  required String currency,
  required String status,
  String? fundingSourceId,
  String? brand,
  String? number,
  bool? enable2FA,
  String? issuerCountry,
  Map<String, dynamic>? metadata,
  Map<String, dynamic>? spendingControls,
  String? bankCode,
  String? accountNumber,
  String? debitAccountId,
  int? amount,
  bool? sendPINSMS,
  String? expirationDate,
}) async {
  final body = <String, dynamic>{
    'customerId': customerId,
    'type': type,
    'currency': currency,
    'status': status,
  };
  if (fundingSourceId != null) body['fundingSourceId'] = fundingSourceId;
  if (brand != null) body['brand'] = brand;
  if (number != null) body['number'] = number;
  if (enable2FA != null) body['enable2FA'] = enable2FA;
  if (issuerCountry != null) body['issuerCountry'] = issuerCountry;
  if (metadata != null) body['metadata'] = metadata;
  if (spendingControls != null) body['spendingControls'] = spendingControls;
  if (bankCode != null) body['bankCode'] = bankCode;
  if (accountNumber != null) body['accountNumber'] = accountNumber;
  if (debitAccountId != null) body['debitAccountId'] = debitAccountId;
  if (amount != null) body['amount'] = amount;
  if (sendPINSMS != null) body['sendPINSMS'] = sendPINSMS;
  if (expirationDate != null) body['expirationDate'] = expirationDate;

  final callable = _functions.httpsCallable('sudoCreateCard');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get all cards.
Future<Map<String, dynamic>> sudoGetCards({int? page, int? limit}) async {
  final body = <String, dynamic>{};
  if (page != null) body['page'] = page;
  if (limit != null) body['limit'] = limit;

  final callable = _functions.httpsCallable('sudoGetCards');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get all cards for a customer.
Future<Map<String, dynamic>> sudoGetCustomerCards(
  String customerId, {
  int? page,
  int? limit,
}) async {
  final body = <String, dynamic>{'customerId': customerId};
  if (page != null) body['page'] = page;
  if (limit != null) body['limit'] = limit;

  final callable = _functions.httpsCallable('sudoGetCustomerCards');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get a single card.
Future<Map<String, dynamic>> sudoGetCard(String cardId) async {
  final callable = _functions.httpsCallable('sudoGetCard');
  final response = await callable.call({'cardId': cardId});
  return Map<String, dynamic>.from(response.data as Map);
}

/// Send default card PIN via SMS.
Future<Map<String, dynamic>> sudoSendDefaultCardPin(String cardId) async {
  final callable = _functions.httpsCallable('sudoSendDefaultCardPin');
  final response = await callable.call({'cardId': cardId});
  return Map<String, dynamic>.from(response.data as Map);
}

/// Change card PIN.
Future<Map<String, dynamic>> sudoChangeCardPin({
  required String cardId,
  required String oldPin,
  required String newPin,
}) async {
  final callable = _functions.httpsCallable('sudoChangeCardPin');
  final response = await callable.call({
    'cardId': cardId,
    'oldPin': oldPin,
    'newPin': newPin,
  });
  return Map<String, dynamic>.from(response.data as Map);
}

/// Enroll a card for 2FA.
Future<Map<String, dynamic>> sudoEnrollCard2FA(String cardId) async {
  final callable = _functions.httpsCallable('sudoEnrollCard2FA');
  final response = await callable.call({'cardId': cardId});
  return Map<String, dynamic>.from(response.data as Map);
}

/// Update a card (status, spending controls, cancel, etc.).
Future<Map<String, dynamic>> sudoUpdateCard({
  required String cardId,
  String? status,
  String? fundingSourceId,
  Map<String, dynamic>? metadata,
  Map<String, dynamic>? spendingControls,
  String? cancellationReason,
  String? creditAccountId,
}) async {
  final body = <String, dynamic>{'cardId': cardId};
  if (status != null) body['status'] = status;
  if (fundingSourceId != null) body['fundingSourceId'] = fundingSourceId;
  if (metadata != null) body['metadata'] = metadata;
  if (spendingControls != null) body['spendingControls'] = spendingControls;
  if (cancellationReason != null) body['cancellationReason'] = cancellationReason;
  if (creditAccountId != null) body['creditAccountId'] = creditAccountId;

  final callable = _functions.httpsCallable('sudoUpdateCard');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Digitalize a card (get payload for Card Digitalization SDK).
Future<Map<String, dynamic>> sudoDigitalizeCard(String cardId) async {
  final callable = _functions.httpsCallable('sudoDigitalizeCard');
  final response = await callable.call({'cardId': cardId});
  return Map<String, dynamic>.from(response.data as Map);
}

/// Order physical cards.
Future<Map<String, dynamic>> sudoOrderPhysicalCards({
  required String debitAccountId,
  required String brand,
  required String currency,
  required int allocation,
  required bool expedite,
  required String shippingMethod,
  required Map<String, dynamic> shippingAddress,
  String? customerId,
  String? design,
  List<String>? nameOnCards,
}) async {
  final body = <String, dynamic>{
    'debitAccountId': debitAccountId,
    'brand': brand,
    'currency': currency,
    'allocation': allocation,
    'expedite': expedite,
    'shippingMethod': shippingMethod,
    'shippingAddress': shippingAddress,
  };
  if (customerId != null) body['customerId'] = customerId;
  if (design != null) body['design'] = design;
  if (nameOnCards != null) body['nameOnCards'] = nameOnCards;

  final callable = _functions.httpsCallable('sudoOrderPhysicalCards');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

/// Get transactions for a card.
Future<Map<String, dynamic>> sudoGetCardTransactions(
  String cardId, {
  int? page,
  int? limit,
  String? fromDate,
  String? toDate,
}) async {
  final body = <String, dynamic>{'cardId': cardId};
  if (page != null) body['page'] = page;
  if (limit != null) body['limit'] = limit;
  if (fromDate != null) body['fromDate'] = fromDate;
  if (toDate != null) body['toDate'] = toDate;

  final callable = _functions.httpsCallable('sudoGetCardTransactions');
  final response = await callable.call(body);
  return Map<String, dynamic>.from(response.data as Map);
}

// ——— Accounts ———

/// Fetch all business accounts and return the _id of the company settlement
/// account for the given [currency] ('NGN' or 'USD').
///
/// Settlement accounts are identified by type='account' and having no
/// 'customer' field (they are business-level, not per-user wallets).
Future<String?> sudoGetSettlementAccountId(String currency) async {
  final callable = _functions.httpsCallable('sudoGetAccounts');
  final response = await callable.call({'currency': currency.toUpperCase()});
  final responseMap = Map<String, dynamic>.from(response.data as Map);
  final list = responseMap['data'];
  if (list is! List) return null;
  for (final item in list) {
    if (item is! Map) continue;
    final acc = Map<String, dynamic>.from(item as Map);
    final accType = acc['type']?.toString();
    final accCurrency = acc['currency']?.toString().toUpperCase();
    // Settlement accounts: type='account', no 'customer' key (company-level)
    if (accType == 'account' &&
        accCurrency == currency.toUpperCase() &&
        !acc.containsKey('customer')) {
      return acc['_id']?.toString();
    }
  }
  return null;
}
