# Video Demo Script: Cross-Subnet Order Coordinator (Terminal-Only)
**Target Length:** 60-90 seconds | **Format:** 3-Act Narrative | **Visuals:** Terminal screen recordings only
**Commands to Record:** `npm run bootstrap` → `npm run demo` → `npx tsx scripts/verify-demo.ts`

---

## ACT 1: THE VILLAIN (0-15s) — "The Problem"
**[VOICEOVER ONLY — no terminal yet]**

> **NARRATOR:** "The SEC just warned: actively managed crypto vaults and lending pools may be securities. Pooled deposits. Discretionary managers. Headstands and backflips to avoid the law. But what if you didn't build a vault at all? What if you built deterministic, bilateral execution — where the rules are burned into the message before it ever crosses chains?"

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

> **NARRATOR:** "Two sovereign Avalanche L1s. Both live. Different RPC endpoints. Different chain IDs. Every contract verified at its address. This isn't a shared chain — it's two separate chains coordinated natively."

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

> **NARRATOR:** "The Initiator broadcasts a deterministic order. The message crosses to the Settlement L1 via Avalanche ICM. The Settlement Messenger authenticates it. TradeEscrow locks 5 bps commission *instantly* and releases the trade amount to the Executor. The Executor swaps inside the slippage bound burned into the order. The Keeper triggers payout — but the commission *can only go to the initiator payout address*. The caller cannot redirect it. No pooled deposits. No discretionary manager. Just code."

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

> **NARRATOR:** "Don't trust the demo output. Verify it yourself. Every transaction. Both chains. Cryptographic proof. The OrderSent on the Initiator L1 with its Teleporter Message ID. The OrderReceived on the Settlement L1 — same message, authenticated. TradeFunded locks commission. TradeExecuted enforces slippage. CommissionPaid — permissionless caller, but destination *immutable*."

---

## ACT 3: THE TRIUMPH (70-90s) — "The Changed World"

### Beat 4: The Reveal (70-82s) — 💥 **WOW #4**
**[TERMINAL: Freeze on final verification box — `✅ VERIFICATION COMPLETE - Cross-subnet trade executed trustlessly`]**

> **NARRATOR:** "*Escrow is the enforcement layer*. Commission locked at open. Slippage enforced at close. Payout destination immutable. The Executor never holds the commission. The Keeper can't redirect it. The Initiator payout *must* receive it. No vault. No lending pool. No discretionary manager. Code as law."

### Beat 5: TADA! (82-90s) — 🎉 **TADA!**
**[TERMINAL: Clean final frame — hold on the green checkmark box]**

> **NARRATOR:** "Cross-subnet coordination. Deterministic. Non-custodial. Native Avalanche."
> 
> **[CUT TO: Repository URL on screen — github.com/.../avax-cross-subnet]**
