# Sudo Cards — Go-Live Checklist

This document tracks every change required before switching Sudo card issuance from
sandbox to production. Work through all items top-to-bottom and tick each one off.

---

## 1. Sudo Dashboard

- [ ] Complete Sudo Africa KYB / compliance review and receive production approval
- [ ] Obtain **production API key** from the Sudo dashboard (different from sandbox key)
- [ ] Confirm which card schemes are enabled on the production account: Verve / MasterCard _(Visa is currently unavailable on sandbox; verify production availability with Sudo)_
- [ ] Confirm physical card issuing is enabled if needed (requires separate Sudo contract)
- [ ] Note down the **production Vault ID** for SecureProxy (sandbox = `we0dsa28s`, production = `vdl2xefo5`)

---

## 2. Firebase Secret

- [ ] Add the production Sudo API key to Firebase Secret Manager:
  ```
  firebase functions:secrets:set SUDO_API_KEY
  # paste the production key when prompted
  ```
- [ ] Verify the secret is accessible: `firebase functions:secrets:access SUDO_API_KEY`
- [ ] Do **not** commit the raw key to source control

---

## 3. Cloud Functions (`functions/index.js`)

### 3a. Switch the base URL
- [ ] Change line 7486:
  ```js
  // BEFORE (sandbox):
  const SUDO_BASE_URL = "https://api.sandbox.sudo.cards";

  // AFTER (production):
  const SUDO_BASE_URL = "https://api.sudo.cards";
  ```

### 3b. Remove the sandbox simulator fund call
- [ ] In `sudoFundAndCreateCard`, replace the Step 1 block that calls
  `/accounts/simulator/fund` with a **real funding mechanism** (e.g. a customer
  top-up flow, bank transfer, or wallet debit) coordinated with Sudo support.
  The simulator endpoint does not exist in production.

  Current sandbox block to replace (≈ line 7659):
  ```js
  // Step 1: Fund the Sudo account via sandbox simulator
  url: `${SUDO_BASE_URL}/accounts/simulator/fund`,
  ```

### 3c. Verify all other Sudo endpoints are production-compatible
- [ ] `POST /customers` — no change needed (same path in prod)
- [ ] `POST /accounts` — no change needed
- [ ] `POST /cards` — no change needed
- [ ] `GET /cards/{id}/token` (`sudoGenerateCardToken`) — no change needed
- [ ] `GET /customers` — no change needed
- [ ] `GET /cards/{id}` — no change needed

### 3d. Deploy
- [ ] `firebase deploy --only functions` (or target specific functions)
- [ ] Smoke-test each callable from the Flutter app against production

---

## 4. Flutter App (`lib/ui/bottom_sheets.dart`)

### 4a. SecureProxy vault ID
- [ ] In `_SudoSecureCardSheetState` (class near bottom of `bottom_sheets.dart`),
  change the vault ID constant:
  ```dart
  // BEFORE (sandbox):
  static const String _vaultId = 'we0dsa28s';

  // AFTER (production):
  static const String _vaultId = 'vdl2xefo5';
  ```
  > The SecureProxy JS URL itself (`https://js.securepro.xyz/sudo-show/1.1/...`)
  > is the same for both environments per Sudo docs.

### 4b. Double-check card scheme labels
- [ ] `BasicDetailsBottomSheet` scheme options currently offer: **Verve**, **MasterCard**
- [ ] Confirm with Sudo which schemes are live on your production account before
  presenting all options to users

---

## 5. Firestore

- [ ] Ensure `users/{uid}/sudoCustomerId` and `users/{uid}/sudoDebitAccountId` are
  populated correctly when accounts are created in production (the values are
  sandbox IDs during testing — they must not carry over)
- [ ] If any Firestore documents still hold sandbox customer/account IDs, purge or
  migrate them before launch
- [ ] Confirm `cards/{docId}` schema is correct and no `card_id: undefined` documents
  exist (guard is in place in the function, but verify in Firestore console)

---

## 6. Security & PCI-DSS

- [ ] **Do not log or store** raw PAN, CVV2, or PIN anywhere — cloud function
  `sudoGenerateCardToken` returns only a short-lived JWT token; the actual
  sensitive data flows via SecureProxy iframes and never touches our servers ✅
- [ ] Rotate the production Sudo API key immediately if it is ever accidentally
  logged, printed, or committed
- [ ] Ensure Firebase App Check is enforced on all Sudo-related callables in
  production (currently `sudoGenerateCardToken`, `sudoFundAndCreateCard`, etc.)
- [ ] Review Sudo's webhook signing secret — verify webhook events are
  authenticated before processing them in any future webhook handler
- [ ] Confirm `ensureVerifiedOrStandUser` auth guard is active on all Sudo callables ✅

---

## 7. Testing Before Launch

- [ ] Create a test customer + account end-to-end in production (use a real but
  small funding amount)
- [ ] Create a virtual Verve card and verify:
  - Card document appears in Firestore with a real `card_id`
  - Push notification is received (`card_created` type)
  - Card appears in the app UI
  - "View Secure Card Details" button shows PAN / CVV2 / PIN via SecureProxy WebView
- [ ] Test a MasterCard creation
- [ ] Test a USD card with a custom funding amount
- [ ] Test card creation failure path (e.g. insufficient balance) — verify
  `card_failed` notification is sent and failed card is not shown in UI
- [ ] Verify the notifications page shows `card_created` (green) and `card_failed`
  (red) entries correctly

---

## 8. App Store Considerations

- [ ] The app renders card PAN inside a WebView iframe — confirm this does not
  violate Apple App Store screenshot/screen-recording policies
- [ ] Add a privacy disclosure in the App Store listing: card data is displayed
  via a PCI-DSS compliant secure proxy and is never stored by Padi Pay

---

## 9. Final Sign-off

| Item | Owner | Done |
|------|-------|------|
| Sudo production API key set in Firebase Secrets | | ☐ |
| `SUDO_BASE_URL` switched to production | | ☐ |
| Simulator fund replaced with real funding | | ☐ |
| SecureProxy vault ID set to `vdl2xefo5` | | ☐ |
| Sandbox Firestore data purged | | ☐ |
| End-to-end card creation tested in production | | ☐ |
| PCI-DSS review signed off | | ☐ |
| Firebase App Check enforced on Sudo callables | | ☐ |
