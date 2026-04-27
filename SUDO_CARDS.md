# PadiPay Virtual Cards — Full Feature Reference

> Applies to the **consumer app** (`padi_pay`) only.  
> The business app does **not** support card creation or management.

---

## 1. Overview

PadiPay virtual cards are powered by the **Sudo Africa** card-issuing API.  
Cards are currency-scoped: users can hold separate **NGN** cards and **USD** cards.  
Every card is backed by a Sudo customer + deposit account created per user.  
All real-time authorisation decisions are handled server-side in the `sudoWebhook` Cloud Function.

---

## 2. Card Lifecycle

### 2.1 Creating a Card

**UI:** `lib/home_pages/card_page.dart` → "Get a Card" button → `lib/top_up/fund_card.dart` → `lib/top_up/fund_card_step_two.dart`

**Cloud Function:** `sudoFundAndCreateCard`

**Flow:**
1. User selects currency (NGN / USD) and chooses a card type.
2. User pays the card creation/funding fee via Anchor bank transfer.
3. On payment confirmation the function:
   - Creates (or reuses) a Sudo customer for the user.
   - Creates (or reuses) a Sudo deposit account.
   - Resolves (or auto-creates) a Sudo funding source.
   - Issues the virtual card via `POST /cards`.
   - Auto-changes the default PIN immediately after card creation.
   - Saves the card document to `users/{uid}/cards/{docId}`.
4. User receives a push notification + email confirming the card.

**Firestore card document fields (at creation):**

| Field | Type | Description |
|---|---|---|
| `card_id` | string | Sudo card ID |
| `type` | string | e.g. `"virtual"` |
| `selectedCurrency` | string | `"NGN"` or `"USD"` |
| `status` | string | `"active"` \| `"inactive"` \| `"terminated"` |
| `frozen` | boolean | `true` if user-frozen |
| `deleted` | boolean | `true` if terminated by user |
| `terminatedAt` | timestamp | Set when card is terminated |
| `channels` | map | Per-channel flags (`pos`, `atm`, `web`) |
| `blockedMerchants` | map | Per-merchant flags (key = normalised name) |
| `sudoAccountId` | string | Linked Sudo deposit account ID |
| `createdAt` | timestamp | Card creation time |

### 2.2 Card Display

**File:** `lib/home_pages/card_page.dart`

- Cards are loaded from `users/{uid}/cards` on page load.
- Cards with `deleted: true` are **silently skipped** and never shown.
- Cards with no `card_id` and `status: "pending"` are shown as pending.
- Cards with `status: "failed"` are silently dropped (user was already notified).
- Cards are grouped by currency tab (NGN / USD).
- Card details (balance, last 4, expiry) are fetched via `sudoGetCard` after the list loads.

**Related files:**
- `lib/cards/card_design.dart` — visual card widget
- `lib/cards/card_utils.dart` — shared card helpers
- `lib/cards/sudo_card_service.dart` — Sudo API service layer
- `lib/card_details/card_details.dart` — full card details screen

---

## 3. More Actions Menu

**File:** `lib/ui/bottom_sheets.dart` → `MoreActionsBottomSheet`

Opened from the card page by tapping the `•••` menu on a card.

| Action | Description |
|---|---|
| Account Statement | Pick a date range; fetches and lists all card transactions |
| Freeze / Unfreeze Card | Toggle that freezes the card; webhook declines all transactions while frozen |
| Change Card Channels | Enable/disable POS, ATM, and Web/Online per card |
| Manage Merchants | Block or allow specific merchants per card |
| Change PIN | Change the card's 4-digit PIN |
| Terminate Card | Permanently deactivate the card (requires confirmation) |

---

## 4. Feature Details

### 4.1 Account Statement

**File:** `lib/account_statement/account_statement.dart`

- User selects a start and end date.
- Calls `sudoGetCardTransactions` with the card's Sudo ID and the ISO date range.
- Displays transactions with merchant name, amount (coloured red/green for debit/credit), and date.
- Shows a "No transactions found" message if the period is empty.

**Cloud Function:** `sudoGetCardTransactions`  
**Sudo API:** `GET /cards/{cardId}/transactions?fromDate=&toDate=&limit=`

---

### 4.2 Freeze / Unfreeze Card

**File:** `lib/ui/bottom_sheets.dart` → `_toggleFreeze()`

- Calls `sudoUpdateCard` with `status: 'inactive'` (freeze) or `status: 'active'` (unfreeze).
- Writes `frozen: true / false` to the Firestore card document.
- The `sudoWebhook` Cloud Function checks `cardData.frozen === true` on every `authorization.request` and immediately declines with response code `62` (Restricted card).
- Decline triggers: push notification + email to the user.

**Webhook decline reason stored in:** `sudo_declined_auths/{authId}.declineReason = "card_frozen"`

---

### 4.3 Change Card Channels

**File:** `lib/card_channels/card_channels.dart` → `ChangeCardChannelsPage`

Three toggleable channels:

| Channel | Firestore key | Covers |
|---|---|---|
| POS | `channels.pos` | In-store terminal payments |
| ATM | `channels.atm` | ATM withdrawals |
| Web / Online | `channels.web` | E-commerce / internet payments |

- Default state: **all channels allowed** (key absent or `true`).
- Setting a channel to `false` blocks it.
- Stored in `users/{uid}/cards/{docId}.channels`.
- The webhook declines with response code `57` when the incoming transaction channel matches a blocked key.
- Decline triggers: push notification + email.

**Webhook channel detection logic:**  
Reads `eventObject.transactionMetadata.channel` or `eventObject.terminal.terminalType`, normalises to `pos` / `atm` / `web`.

**Webhook decline reason:** `sudo_declined_auths/{authId}.declineReason = "channel_blocked"`

---

### 4.4 Manage Merchants

**File:** `lib/card_channels/card_merchants.dart` → `ManageMerchantsPage`

- Merchant list is sourced from `users/{uid}/transactions` where `source == 'sudo_card'`.
- All unique merchant names across **all** the user's cards are shown.
- Blocking / allowing is **per-card** (each card has its own `blockedMerchants` map).

**Merchant key normalisation:**  
`NETFLIX.COM` → `netflix_com`  
Rule: `name.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/, '')`

**Storage:** `users/{uid}/cards/{docId}.blockedMerchants = { 'netflix_com': false }`  
`false` = blocked. Key absent (or `true`) = allowed.

**Toggle behaviour:**
- Block: `update({'blockedMerchants.$key': false})`
- Unblock: `update({'blockedMerchants.$key': FieldValue.delete()})` (removes key)

**Webhook check:** After channel check, before balance check. Declines with response code `57`.  
**Webhook decline reason:** `sudo_declined_auths/{authId}.declineReason = "merchant_blocked"`

---

### 4.5 Change PIN

**File:** `lib/ui/bottom_sheets.dart` → `ChangeSudoCardPinSheet`

- Calls `sudoChangeCardPin` with the card ID and new PIN.
- Validates new PIN (4 digits, not trivial sequences).

**Cloud Function:** `sudoChangeCardPin`  
**Sudo API:** `PUT /cards/{cardId}/pin`

---

### 4.6 Terminate Card

**File:** `lib/ui/bottom_sheets.dart` → `_terminateCard()`

1. Shows a confirmation `AlertDialog` — user must explicitly tap **Terminate**.
2. Calls `sudoUpdateCard` with `status: 'terminated'` to deactivate the card at the Sudo level.
3. Writes `deleted: true` and `terminatedAt: <timestamp>` to the Firestore card document.
4. Navigates the user back to the home screen.

**After termination:**
- Card no longer appears in the cards list (`_fetchCards()` skips `deleted: true` docs).
- Any future `authorization.request` for that card is immediately declined with response code `14` (Invalid card number). Checked **before** the frozen check.

**Webhook decline reason:** `sudo_declined_auths/{authId}.declineReason = "card_terminated"`

---

## 5. Top-Up / Fund Card

**Files:** `lib/top_up/fund_card.dart`, `lib/top_up/fund_card_step_two.dart`

- User initiates a top-up from the card page.
- Calls the bank transfer flow to fund the card's Sudo deposit account.

---

## 6. Webhook — `sudoWebhook` (Cloud Function)

**File:** `functions/index.js` → `exports.sudoWebhook`

Receives all real-time events from Sudo Africa. Handles:

| Event | Action |
|---|---|
| `authorization.request` | Real-time auth decision (approve or decline) |
| `authorization.declined` | Log declined auth; notify user if not already done |
| `transaction.created` | Write transaction to `users/{uid}/transactions`; push notification |
| `transaction.refund` | Write refund transaction; notify user |
| `card.terminated` | Mark card as terminated in Firestore; notify user |
| `card.balance` | No-op (acknowledged) |

### Authorization.request decision order:

1. **Card lookup** — find card in Firestore by Sudo card ID → decline `14` if not found
2. **Terminated/deleted check** — `cardData.deleted === true` → decline `14`
3. **Frozen check** — `cardData.frozen === true` → decline `62`
4. **Channel check** — `cardData.channels[txChannel] === false` → decline `57`
5. **Merchant check** — `cardData.blockedMerchants[merchantKey] === false` → decline `57`
6. **Balance check** — query Anchor balance; if insufficient → decline `51`
7. **Prefund transfer** — transfer user funds → company account before approving
8. **Approve** — return `00`

### Prefund flow (NGN cards only):

- Before approving any NGN transaction, funds are moved from the user's Anchor deposit account to the company account via a book transfer.
- Prefund is logged in `sudo_card_prefunds/{key}`.
- If the prefund succeeds but the response send fails, an automatic **reversal** book transfer is attempted.
- USD cards: covered by the Sudo settlement account — no prefund needed.

---

## 7. Firestore Collections

| Collection | Purpose |
|---|---|
| `users/{uid}/cards/{docId}` | Card documents (one per issued card) |
| `users/{uid}/transactions` | All transactions including card transactions (`source: 'sudo_card'`) |
| `sudo_card_prefunds/{key}` | Internal prefund/reversal log (not shown in user UI) |
| `sudo_declined_auths/{authId}` | Log of every declined authorization |

---

## 8. Cloud Functions Reference

| Function | Description |
|---|---|
| `sudoFundAndCreateCard` | Create a new virtual card (full flow: customer → account → card) |
| `sudoCreateCard` | Low-level card creation (used internally) |
| `sudoGetCard` | Fetch a single card's details from Sudo |
| `sudoGetCards` | Fetch all cards for the authenticated user |
| `sudoGetCustomerCards` | Fetch cards by Sudo customer ID |
| `sudoUpdateCard` | Update card status (freeze → `inactive`, unfreeze → `active`, terminate → `terminated`) |
| `sudoChangeCardPin` | Change the card's PIN |
| `sudoSendDefaultCardPin` | Send the default PIN to the user |
| `sudoEnrollCard2FA` | Enroll card in 2FA |
| `sudoGenerateCardToken` | Generate a one-time card token for secure display |
| `sudoGetCardTransactions` | Fetch card transaction history with date range filtering |
| `sudoDigitalizeCard` | (Deprecated / not in UI) Digitalize card for mobile wallets |
| `sudoOrderPhysicalCards` | Order physical card (not surfaced in current UI) |
| `sudoCreateCustomer` | Create a Sudo customer profile for the user |
| `sudoUpdateCustomer` | Update Sudo customer details |
| `sudoCreateAccount` | Create a Sudo deposit account |
| `sudoGetAccounts` | List Sudo deposit accounts |
| `sudoGetAccountBalance` | Get balance of a Sudo deposit account |
| `sudoCreateFundingSource` | Create a funding source for card charges |
| `sudoGetFundingSources` | List funding sources |
| `sudoGetFundingSource` | Get a single funding source |
| `sudoUpdateFundingSource` | Update a funding source |
| `sudoWebhook` | Receives all real-time Sudo events (auth, transactions, terminations) |
