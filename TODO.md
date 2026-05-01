# TODO - Update choose_upgrade_tier.dart to 3-Tier System

## Plan
1. Replace "Step 1" and "Step 2" UI with Tier 1, Tier 2, and Tier 3 cards
2. Implement sequential progression: Tier 1 → Tier 2 → Tier 3
3. Users cannot skip tiers (must complete Tier 1 before Tier 2, etc.)

## Tier Limits
- **Tier 1**: ₦10,000 per transaction, ₦50,000 daily, ₦50,000 max balance
- **Tier 2**: ₦100,000 per transaction, ₦500,000 daily, ₦500,000 max balance
- **Tier 3**: ₦5,000,000 per transaction, ₦10,000,000 daily, ₦100,000,000 max balance

## Implementation Steps
- [x] Read and understand file structure
- [x] Add tier completion getters (_tier1Completed, _tier2Completed, _tier3Completed)
- [x] Add tier limit getters with formatted Naira strings
- [x] Create _buildTierCard helper widget for reusable tier cards
- [x] Replace old Step 1/Step 2 cards with Tier 1/2/3 cards
- [x] Implement sequential button logic (can't skip tiers)
- [x] Pass int tier values to UpgradeTier constructor

## Status
- Complete: All changes implemented successfully
