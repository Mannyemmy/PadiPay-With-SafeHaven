# PadiPay Main App — Optimization Fixes Applied

**Date:** April 18, 2026

---

## 1. DUPLICATE STREAM SUBSCRIPTION (CRITICAL)
**File:** `lib/home_pages/home_page.dart`
**Problem:** `_setupNotifStream()` was called twice in `initState()`, creating duplicate Firestore listeners — doubling state updates, Firestore reads, and memory usage.
**Fix:** Removed the duplicate call. Added `_notifSub?.cancel()` guard before resubscribing.

---

## 2. EMPTY ERROR CALLBACKS ON STREAM LISTENERS (HIGH)
**File:** `lib/home_pages/home_page.dart`
**Problem:** Notification and transaction stream listeners had `onError: (_) {}` — silently swallowing errors. Network failures, permission issues, or Firestore problems went undetected.
**Fix:** Replaced empty error handlers with logging + graceful state fallback (e.g., resetting to 0 unread notifications on error).

---

## 3. TRANSACTION QUERIES WITHOUT .limit() (HIGH)
**Files:** `lib/home_pages/home_page.dart`, `lib/home_pages/transactions_page.dart`
**Problem:** Transaction stream queries fetched ALL user transactions with no `.limit()`. Users with 1000+ transactions downloaded everything on app open, causing UI jank, memory bloat, and excessive Firestore reads.
**Fix:** Added `.orderBy('timestamp', descending: true).limit(50)` on home page streams, `.limit(200)` on transaction history page.

---

## 4. `late StreamSubscription` CRASH RISK (HIGH)
**File:** `lib/home_pages/transactions_page.dart`
**Problem:** `late StreamSubscription` declarations crash at dispose time if the subscription was never initialized (e.g., user signed out before streams set up).
**Fix:** Changed to nullable `StreamSubscription?` types. Updated `dispose()` to use `?.cancel()`.

---

## 5. MISSING `mounted` CHECKS ON setState (MEDIUM)
**File:** `lib/home_pages/transactions_page.dart`
**Problem:** Stream listeners called `setState()` without checking `mounted`, risking "setState called after dispose" errors.
**Fix:** Added `if (mounted)` guards to all stream listener callbacks.

---

## 6. FULL COLLECTION SCAN IN BANK LOOKUP (HIGH)
**File:** `lib/utils.dart` — `resolveBankId()`
**Problem:** Fallback case-insensitive bank lookup loaded the entire `banks` collection (1000+ documents) for every lookup.
**Fix:** Added in-memory `_bankIdCache` map. Banks are loaded once into cache, then all subsequent lookups are O(1) from the cached map.

---

## 7. REDUNDANT BANK COLLECTION READS IN GHOST MODE (HIGH)
**File:** `lib/ghost_mode/ghost_mode.dart`
**Problem:** `collection('banks').get()` was called 3 times in a single page lifecycle. The fallback case-insensitive lookup did a full collection scan.
**Fix:** Replaced the 3rd bank read with the already-loaded in-memory `banks` list from `_fetchBanks()`.

---

## 8. SEQUENTIAL BILLER FETCH (MEDIUM)
**File:** `lib/bills/pay_bills.dart` — `_fetchBillers()`
**Problem:** Data, television, and electricity biller categories were fetched sequentially with `await`. If each takes 300ms, total = 900ms.
**Fix:** Wrapped all 3 fetches in `Future.wait()` for parallel execution. Total time ≈ 300ms.

---

## 9. Image.network WITHOUT ERROR HANDLING (MEDIUM)
**File:** `lib/bills/pay_bills.dart`
**Problem:** `Image.network()` calls for biller logos had no error handling — broken URLs caused invisible/broken image widgets.
**Fix:** Added `errorBuilder` fallback and `cacheWidth/cacheHeight` for memory-efficient decoding.

---

## 10. fetchAccountBalance RE-THROWS AFTER CATCH (MEDIUM)
**File:** `lib/home_pages/home_page.dart`
**Problem:** `fetchAccountBalance()` caught errors, set state to defaults, then re-threw the exception — causing the calling code to crash.
**Fix:** Removed the re-throw. The function now returns `0.0` on failure instead of crashing the caller.

---

## 11. PROFILE LISTENER ERROR HANDLING (LOW)
**File:** `lib/profile/profile_page.dart`
**Problem:** BVN match listener had no `onError` callback.
**Fix:** Added `onError` handler.
