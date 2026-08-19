# Video Demo Script: Cross-Subnet Order Coordinator (Terminal-Only)
**Target Length:** 60-90 seconds | **Format:** 3-Act Narrative | **Visuals:** Terminal screen recordings only
**Commands to Record:** `npm run bootstrap` → `npm run demo` → `npx tsx scripts/verify-demo.ts`

---

## ACT 1: THE VILLAIN (0-15s) — "The Problem"
**[VOICEOVER ONLY — no terminal yet]**

> **NARRATOR:** "The SEC has made one thing clear: DeFi pooled deposits and vaults with discretionary managers may be viewed as securities. But the real problem isn't regulation, it's trust. That's why we built a deterministic, bilateral trade execution engine for sovereign individuals on Avalanche."

---

## ACT 2: THE HERO (15-70s) — "The Solution"

### Beat 1: The Stage is Set (15-22s) — 💥 **WOW #1**
**[TERMINAL: `npm run bootstrap` — live output]**

```
Verifying L1 connectivity and contract deployments...

✓ Initiator L1 (http://127.0.0.1:9654/ext/bc/.../rpc) - Block: 17
✓ Settlement L1 (http://127.0.0.1:9656/ext/bc/.../rpc) - Block: 96
✓ InitiatorMessenger deployed at 0x789a...
✓ SettlementMessenger deployed at 0x4a43...
✓ TradeEscrow deployed at 0xd17C...
✓ MockWAVAX deployed at 0x764a...
✓ MockUSDC deployed at 0xEC1b...
✓ MockDEX deployed at 0x473d...

✓ All L1s reachable and contracts verified at deployed addresses.
```

> **NARRATOR:** "Here is the setup. Two Avalanche L1s — different RPCs, different chain IDs, separate infrastructures."

### Beat 2: The Trade Executes (22-45s) — 💥 **WOW #2**
**[TERMINAL: `npm run demo` — live output, show key moments]**

```
Initiator: 0xAd8b...
Executor: 0xb756...
Keeper: 0x21Cd...
Initiator Payout: 0x15d3...

Relayer already running.
--- Funding & approvals ---
Executor mWAVAX: 500000
MockDEX mUSDC: 2000

--- Initiator sends order ---
Order ID: 0x7afa8da5b175c0e4fdae7c3410831a1eaf7118889b12b8f5215112ff4a5d254e
Order sent. Tx: 0x3568bd2966eee3fd11f87462d8656da886407739412fcea66ef160bb4cb3d9a3

--- Waiting for ICM relayer to deliver message ---
Message delivered and escrow leg opened.

--- Executor executes trade ---
Commission: 250 mWAVAX
Trade amount: 499750 mWAVAX
Executor mUSDC after swap: 1000
Trade closed

--- Keeper triggers payout ---
Commission paid

--- Final balances ---
Escrow mWAVAX: 0
Escrow mUSDC: 0
Initiator Payout mWAVAX: 250
Keeper mWAVAX: 0
Executor mWAVAX: 0
Executor mUSDC: 1000

Demo completed successfully.
```

> **NARRATOR:** "Now the trade executes. The Initiator broadcasts an order to the Settlement L1 via Avalanche's native Interchain Messaging protocol, carried by the ICM relayer. The Settlement Messenger receives it, authenticates, and opens the escrow. TradeEscrow locks in commission for the Strategy provider and the remaining amount is immediately released to the Executor. The Executor performs the swap. Then, anyone can permissionlessly trigger the Keeper payout. The destination is immutable and no one can corrupt the flow."

### Beat 3: Cryptographic Proof (45-70s) — 💥 **WOW #3**
**[TERMINAL: `npx tsx scripts/verify-demo.ts` — live output]**

```
╔══════════════════════════════════════════════════════════════════════╗
║        CROSS-SUBNET DEMO VERIFICATION - TRANSACTION TRAIL          ║
╚══════════════════════════════════════════════════════════════════════╝

📋 ORDER ID: 0x7afa8da5b175c0e4fdae7c3410831a1eaf7118889b12b8f5215112ff4a5d254e

📍 STEP 1: INITIATOR L1 (Initiator Subnet)
   ✅ OrderSent Event
      Tx Hash: 0x3568bd2966eee3fd11f87462d8656da886407739412fcea66ef160bb4cb3d9a3
      Block: 18
      Gas Used: 138548
      Teleporter Message ID: 0xfa525633ae99effd8883fbb5e033631484e7691fc9c2fff8d6a65a1955cf9cf7

📍 STEP 2: CROSS-CHAIN MESSAGE DELIVERY (Teleporter/ICM)

📍 STEP 3: SETTLEMENT L1 (Settlement Subnet)
   ✅ OrderReceived Event (Teleporter Message Authenticated)
      Tx Hash: 0x539a785030980a1282a6f94962664d6f109fef44badaf1749da9fe60c2594df5
      Block: 100
      Gas Used: 723354
   ✅ TradeFunded Event (Escrow Opened)
      Commission Locked: 250 mWAVAX (5 bps)
      Trade Amount Released: 499750 mWAVAX → Executor
      Initiator Payout: 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

   ✅ TradeExecuted Event (Swap Verified & Output Released)
      Tx Hash: 0xc0fbe241b57a7ae6d8b31fcf85e99721c5b27f509baa719b1bf949810e42bbd1
      Block: 104
      Output Received: 1000 mUSDC → Executor
      Slippage Check: PASSED (output ≥ minAmountOut)

   ✅ CommissionPaid Event (Permissionless Keeper Payout)
      Tx Hash: 0x0f5f44534effdecc7b9f2486d706d00d2399a820ec42607c66586278ecdc26d5
      Block: 105
      Commission: 250 mWAVAX → Initiator Payout
      🔒 Payout destination FIXED to initiatorPayout (caller cannot redirect)

📊 FINAL STATE VERIFICATION
   TradeEscrow mWAVAX:  0  (should be 0 - commission paid out)
   TradeEscrow mUSDC:   0    (should be 0 - output released)
   Initiator Payout:    250 mWAVAX  (commission received)
   Executor:            0 mWAVAX, 1000 mUSDC

🔐 INVARIANT CHECKS
   ✅ funded:     true
   ✅ executed:   true
   ✅ paid:       true
   ✅ payout fixed:    Commission can ONLY go to 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

║  ✅ VERIFICATION COMPLETE - Cross-subnet trade executed trustlessly  ║
```

> **NARRATOR:** "And with massive implications for institutional trading, the cryptographic audit trail is critical. Every transaction hash, every block number, every gas value is visible on both chains."

---

## ACT 3: THE TRIUMPH (70-90s) — "The Changed World"

### Beat 4: The Reveal (70-82s) — 💥 **WOW #4**
**[TERMINAL: Freeze on final verification box — `✅ VERIFICATION COMPLETE - Cross-subnet trade executed trustlessly`]**

> **NARRATOR:** "Look at the final state. We just experienced trustless non-custodial trade execution between parties. No pooled deposits. No controlling manager."

### Beat 5: TADA! (82-90s) — 🎉 **TADA!**
**[TERMINAL: Clean final frame — hold on the green checkmark box]**

> **NARRATOR:** "This is the power of cross-subnet coordination, built on Avalanche."
> 
> **[CUT TO: Repository URL on screen — github.com/.../avax-cross-subnet]**

---

## Production Notes

| Element | Detail |
|---------|--------|
| **Recording** | 1080p minimum, terminal font size 16+, high contrast theme |
| **Pacing** | Cut on action (keystrokes → output). No dead air. |
| **Voiceover** | Record separately, sync to edits. Confident, technical but accessible. |
| **Music** | Subtle tension in Act 1, building momentum Act 2, resolution Act 3 |
| **Captions** | Include key commands and addresses for viewers to replicate |

---

## Quick Reference: Commands for Recording

```bash
# ACT 1 - Problem context (narration only, no commands needed)

# ACT 2 - The Solution
npm run bootstrap         # ~5s — MUST show live
npm run demo              # ~30s — show key moments, not full wait
npx tsx scripts/verify-demo.ts  # ~10s — THE verification moment

# ACT 3 - Triumph (narration over verification output freeze-frame)
```

---

## Alternative: 60-Second Cut (If Time Constrained)

| Time | Content |
|------|---------|
| 0-10s | Problem: "Trust is the villain. Deterministic bilateral execution is the answer." |
| 10-25s | Bootstrap + Demo (sped up) |
| 25-45s | Live demo + verification script |
| 45-55s | Invariant close-up: "Payout FIXED. Caller cannot redirect." |
| 55-60s | TADA + Logo |

---

## Key Messages to Land

1. **Native messaging** (Teleporter) ≠ bridges
2. **Escrow = enforcement**, not trust
3. **Permissionless but bounded** — keeper calls, destination fixed
4. **Verifiable** — every tx on both chains, cryptographic proof
5. **Production path** — documented in `docs/EXTENDING.md`

---

*Script v2.0 — Updated with consolidated continuous narrative. Ready to record.*