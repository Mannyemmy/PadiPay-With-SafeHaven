# MyPadi AI Assistant

## Overview
MyPadi is an AI-powered financial assistant built into the PadiPay app. It uses **Gemini 2.5 Flash** with function calling to let users interact with the app using natural language — checking balances, sending money, buying airtime, and more, all through conversation.

## Architecture
- **Frontend only** — runs entirely in the Flutter app using the `google_generative_ai` Dart package (v0.4.7)
- **No backend deployment needed** — Gemini API is called directly from the client
- **Streaming responses** — text appears word-by-word for a fast feel
- **Function calling** — Gemini decides when to trigger app actions based on conversation context

## Files
| File | Purpose |
|------|---------|
| `lib/my_padi/my_padi_service.dart` | Gemini integration, function declarations, user context, action handling |
| `lib/my_padi/my_padi_page.dart` | Chat UI — bubbles, typing indicator, quick actions, navigation |
| `lib/home_pages/home_page.dart` | Entry point — MyPadi grid tile navigates to chat page |

## Current Capabilities

### Informational
| Feature | Example Prompt |
|---------|---------------|
| **Check balance** | "What's my balance?" |
| **Search transactions** | "Did I send money to Chioma?", "Show my last 5 transfers" |
| **Spending summary** | "How much did I spend this month?", "My spending breakdown this week" |
| **App guidance** | "How do I use Ghost Mode?", "What can you do?" |

### Action-Based (navigates to the relevant page)
| Feature | Example Prompt |
|---------|---------------|
| **Transfer money** | "Send ₦5,000 to John", "I want to transfer money" |
| **Buy airtime** | "Buy ₦1,000 MTN airtime for 08012345678" |
| **Pay bills** | "Pay my DSTV subscription", "I need to pay my electricity bill" |
| **Generate statement** | "Give me my account statement for March" |
| **Open any feature** | "Take me to Ghost Mode", "Open my cards", "Go to Give-Away" |

### Smart Context
- Knows the user's name, PadiTag, account number, tier
- Has access to the last 30 transactions for searches and analytics
- Cached balance for instant answers, live fetch on demand
- Maintains conversation history within a session

## How It Works
1. On open, loads user profile + recent transactions from Firestore
2. Injects context into Gemini system prompt (name, balance, transactions)
3. User sends a message → streamed to Gemini via `ChatSession`
4. Gemini either responds with text or calls a function (e.g., `transfer_money`)
5. Function calls return data to Gemini, which formats a user-friendly response
6. If the action requires navigation, a button appears + auto-navigates after 1.2s

## Future Features

### Phase 1 — Quick Wins
- [ ] **Voice input** — tap mic to speak instead of type (use `speech_to_text` package)
- [ ] **Pre-filled actions** — when Gemini says "transfer ₦5k to John", open the transfer page with amount and recipient already filled in
- [ ] **Transaction receipts** — "Show me the receipt for my last transfer" → display or share PDF
- [ ] **Favorites/shortcuts** — "Send ₦2k to my usual number" (learn frequent recipients)
- [ ] **Suggested follow-ups** — after each response, show 2-3 contextual chip suggestions

### Phase 2 — Intelligence
- [ ] **Bill reminders** — "Remind me to pay DSTV on the 15th" → local notifications
- [ ] **Budget tracking** — "Set a ₦50k monthly spending limit" → warn when approaching
- [ ] **Anomaly alerts** — "You spent 3x more on airtime this week than usual"
- [ ] **Recurring payments** — "Buy ₦500 airtime every Monday for this number"
- [ ] **Financial tips** — contextual advice based on spending patterns ("You could save ₦X by...")

### Phase 3 — Advanced
- [ ] **Multi-turn confirmations** — execute transfers/airtime directly from chat after PIN verification, without navigating away
- [ ] **Image understanding** — snap a bill/invoice photo and MyPadi extracts the details to pay
- [ ] **Backend AI endpoint** — move Gemini calls to Cloud Functions for API key security + server-side tool execution
- [ ] **Conversation history** — persist chat across sessions in Firestore
- [ ] **PadiTag lookup** — "What's Chioma's PadiTag?" → search contacts/Firestore
- [ ] **Multi-language** — support Pidgin, Yoruba, Igbo, Hausa prompts naturally
- [ ] **Proactive assistant** — push notifications like "Your balance is low, top up?" or "Electricity bill due tomorrow"

## Security Notes
- API key is currently hardcoded in the client (same pattern as targeted_giveaway_page.dart)
- For production, move to a Cloud Function proxy or Firebase Remote Config
- No sensitive data (passwords, PINs, full account IDs) is ever sent to Gemini
- Transaction data sent to Gemini is limited to type, amount, date, and name — no internal IDs

## Deployment
**No backend changes needed.** MyPadi runs entirely on the client side using the existing `google_generative_ai` Flutter package and the existing Gemini API key. Just build and deploy the app.
