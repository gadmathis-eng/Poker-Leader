# The Vault

The Vault is a player's private account balance: money they have put in, money
they have on a table, and money they can take back out. This document covers how
it is built, what keeps it private, what keeps it correct, and what is still
missing before it could hold real money.

**Nothing in this system is real money today.** Every deposit is simulated,
Apple Pay is mocked, and no payout is made. That is a deliberate, labelled state
described under [Sandbox phase](#sandbox-phase), not something hidden.

---

## The shape of it

| Layer | Where | What it does |
|---|---|---|
| Ledger and rules | `supabase/migrations/20260907120000_vault_ledger.sql` | Owns every balance. Decides who may do what. |
| Backend seam | `PokerLeader/Core/Vault/VaultBackend.swift` | The only interface the app has to money. |
| Real backend | `Core/Vault/SupabaseVaultBackend.swift` | Calls the Postgres functions. |
| Demo backend | `Core/Vault/SandboxVaultBackend.swift` | Same rules, in-process, for demoing without a project. |
| Payment seam | `Core/Vault/PaymentProvider.swift` | Where an approved provider is connected later. |
| App state | `Core/Vault/VaultStore.swift` | Sequences the steps, holds the last answer. |
| Screens | `Features/Vault/` | Vault tab, Add Money, Cash Out, buy-in, settlement. |

## Money is an integer

Every amount, everywhere, is a whole number of cents in a `bigint` or an `Int`.
There is no floating point in the Vault and no `Decimal` arithmetic on balances.
`Money` (`Core/Vault/Money.swift`) is the only type that crosses between cents
and the `Decimal` the rest of the app uses for table stakes, and it rounds to the
nearest cent in both directions.

## Double-entry, and why the balance column is not the truth

Money is never added to a balance. It is *moved* between accounts, and each
movement is a transaction holding two or more entries whose signed cents sum to
exactly zero. A deposit is not "+$100 to the player" — it is "-$100 from the
payment provider's clearing account, +$100 to the player's available account".

Six kinds of account:

| Kind | Owner | Holds |
|---|---|---|
| `available` | player | spendable and withdrawable money |
| `in_play` | player, per table | money committed to one table |
| `pending_withdrawal` | player | money reserved while a cash-out runs |
| `psp_clearing` | system | the outside world money arrives from |
| `payout_clearing` | system | the outside world money leaves to |
| `fees` | system | fees retained by the operator |

Player accounts carry a check constraint that they may never go negative. The
three system accounts are expected to, and their negative total is the mirror of
everything held on behalf of players.

`vault_ledger_transactions` and `vault_ledger_entries` both have triggers that
refuse `UPDATE` and `DELETE` outright. A correction is a new, opposing
transaction; nothing is ever edited or erased. `vault_accounts.balance_cents` is
a running total maintained inside the same database transaction as the entries
that moved it, and `vault_reconcile_accounts()` re-derives every balance from the
entries to prove the two agree. `vault_reconcile_transactions()` proves every
transaction still sums to zero. Both should always return no rows.

### What each movement looks like

| Event | Entries |
|---|---|
| Deposit | `psp_clearing` −N, `available` +N |
| Buy-in from Vault | `available` −N, `in_play` +N |
| Buy-in with Apple Pay | `psp_clearing` −N, `in_play` +N |
| A hand (posted by the poker engine) | `in_play`(loser) −N, `in_play`(winner) +N |
| Leaving a table | `in_play` −N, `available` +N |
| Cash-out requested | `available` −N, `pending_withdrawal` +N |
| Cash-out paid | `pending_withdrawal` −N, `payout_clearing` +(N−fee), `fees` +fee |
| Cash-out rejected, canceled, failed | `pending_withdrawal` −N, `available` +N |

## Privacy

A player's Vault is visible to that player and to nobody else.

- Row-level security on `vault_accounts`, `vault_ledger_transactions`,
  `vault_ledger_entries`, `vault_statement_entries`, `vault_payment_intents`,
  `vault_withdrawals`, `vault_table_stakes`, `vault_audit_log` and
  `vault_compliance_profiles` narrows every `select` to `auth.uid() = user_id`.
  There is no policy that lets one player read another's row, so there is no
  query the app could send that would return one.
- `authenticated` is granted `select` and nothing else on every one of those
  tables. Insert, update and delete are not granted at all — not narrowed,
  *absent*. Every write goes through a `security definer` function that re-checks
  the caller against `auth.uid()`.
- The one financial fact that crosses between players is a seat's chips in play,
  served by `vault_table_chips(invite_code)`. It refuses callers who are not
  themselves at that table, and it returns the player key, the display name and
  the chip count. It does not return a buy-in total, a vault balance, a payment
  method or a history, because it cannot: those columns are not in its result.
- Nothing in the interface relies on being hidden. Removing every screen in
  `Features/Vault/` would not expose one player's balance to another, because the
  privacy is in the grants and the policies, not the views.

## Idempotency

Every mutating call carries an idempotency key. The database has a unique index
on `(user_id, idempotency_key)` for ledger transactions, deposit intents and
withdrawals; sending the same key again returns the original result instead of
moving money a second time. Some keys are derived from what they identify rather
than generated:

- A hand is keyed `hand:<table>:<hand id>`. The poker engine posts that key
  once, when it settles. A second settlement is a no-op.
- A settled deposit is keyed `intent:<intent id>`, so a webhook delivered twice —
  which providers do — credits once.
- A buy-in paid by card is keyed on the payment intent, so a retry after a
  timeout attaches to the payment that already exists.

Beyond keys, a settled payment intent is stamped `consumed_at` when it is spent
on a seat, so one verified payment can buy exactly one buy-in.

## Concurrency

`vault_post_transaction` locks every account it is about to touch with
`SELECT … FOR UPDATE`, in a stable order, before writing any entry. The stable
order is what stops two postings that touch the same pair of accounts from
deadlocking against each other. Balance updates and entry writes happen in the
same database transaction, so a crash between them is impossible: either the
whole movement happened or none of it did. `vault_table_buy_in` and
`vault_leave_table` take a row lock on the table and the stake before reading the
figures they act on.

## What the client can and cannot do

The app can ask. It cannot decide.

- There is no method on `VaultBackend` that sets a balance, credits a win, or
  marks a payment verified, and no table grant that would let one be added.
- A deposit is worth nothing until the backend settles it. `VaultStore.addMoney`
  opens an intent, runs the provider, and then asks the backend to settle that
  intent; the balance it reports afterwards is the backend's, not a local sum.
- A buy-in paid by card must name a deposit intent the backend has already
  settled, for the right amount, for the right table, not yet spent. An app that
  simply claimed a payment had happened would be refused at every one of those
  four checks.
- A hand's result is never accepted from the client. `vault_record_hand` refuses
  any payload. The poker engine deals, takes actions, names the winner, and
  posts the Vault movement itself.
- Cash-outs are resolved by `vault_resolve_withdrawal`, which refuses any caller
  that has an `auth.uid()`. A player cannot mark their own withdrawal paid.

## Sandbox phase

`vault_config.sandbox_mode` is `true`. While it is:

- `vault_sandbox_confirm_deposit` stands in for the provider's signed webhook, so
  a mock Apple Pay deposit can be settled without a real payment. It still cannot
  say how much arrived — the amount comes from the stored intent.
- `vault_sandbox_resolve_withdrawal` walks a pending cash-out to a finished state
  so the pending → completed path can be seen without a payout rail.
- Identity and payout-method verification are not required for a cash-out,
  because the money is not real.
- Every statement row is stamped `is_demo`, and the interface shows a
  **Test Mode · Demo Funds** badge wherever a figure appears.

Turning `sandbox_mode` off closes all of that: deposits can then only be settled
by `service_role` from a verified webhook, cash-outs only by an operator or
payout provider, and the identity and payout-method gates in
`vault_assert_allowed` turn on.

### Connecting a real provider

1. Implement `VaultPaymentProvider` against the approved provider's SDK and swap
   it into `VaultProviders.payment`. `authorize` returns a token to hand to the
   backend — never a balance, never a receipt the app treats as settlement.
2. Add a webhook endpoint that verifies the provider's signature and calls
   `vault_settle_deposit_intent` as `service_role`. That function is already the
   only path that turns an intent into money.
3. Implement `VaultPayoutProvider` and an operator process that calls
   `vault_resolve_withdrawal`. Apple Pay is not a candidate here: it takes
   payments, it does not send them, which is why the Cash Out screen names the
   payout provider's destination instead.
4. Set `vault_config.sandbox_mode = false`.
5. No provider secret goes in the app. Publishable identifiers are configuration;
   private keys stay on the server. No card details or Apple Pay credentials are
   stored anywhere in this system — the provider holds them and the backend sees
   only opaque identifiers.

## Compliance

`vault_compliance_profiles` carries one row per player, and
`vault_assert_allowed(user, activity, amount)` is called before every deposit,
buy-in and cash-out. It covers:

| Requirement | How |
|---|---|
| Location and jurisdiction | `jurisdiction_code`, `jurisdiction_status`; `blocked` refuses everything |
| Account restrictions and suspensions | `account_status` of `restricted`, `suspended`, `closed` |
| Self-exclusion | `self_excluded_until` blocks deposits and play, never cash-outs |
| Deposit limits | per-player `daily_deposit_limit_cents`, capped by the global limit |
| Loss limits | `daily_loss_limit_cents`, measured against the day's statement |
| Session limits | `session_limit_minutes` |
| Identity verification | `identity_status` must be `verified` for a live cash-out |
| Sanctions screening | `sanctions_status`; `hit` blocks, `review` holds cash-outs |
| Payout method | `payout_method_status` must be `verified` for a live cash-out |
| Anti-money-laundering and fraud | `vault_audit_log` records every attempt with its outcome; `vault_rate_limits` caps deposit, buy-in and withdrawal frequency |
| Chargebacks, disputes, reversals | `deposit_reversed` and `chargeback` statement kinds, posted as new opposing transactions |
| Reconciliation | `vault_reconcile_accounts()`, `vault_reconcile_transactions()` |

The fields exist and are enforced; what is not built is the machinery that
*populates* them — a geolocation check, a KYC provider, a sanctions list, a
transaction-monitoring rules engine. Those are integrations, and the gates are
where they plug in.

### Apple

The real-money nature of this feature is not concealed from App Review. When it
goes live it needs, at minimum: a real-money gaming entitlement and the
geographic restrictions that come with it; an Apple Pay merchant configuration;
age gating; the responsible-gaming disclosures the App Store requires; and a
review of whether the jurisdictions being served permit it. Real-money wagering
is out of scope for in-app purchase, which is why the payment path is a payment
provider rather than StoreKit.

## Known gaps

Worth being plain about, because the architecture points at them:

- **The game is server-authoritative.** `poker_start_hand` deals, `poker_act`
  is the only betting entry, and settlement is posted from that result. A
  modified client cannot name a winner, submit cards, rewrite the pot, or
  mark a hand finished so they can walk out of it. A player who disconnects
  is folded after 45 seconds; chips they had already put in stay in the pot.
  Live board, pot and turn are readable only by people at the table. A
  six-character code is enough to preview who is sitting, not to watch the
  hand.
- **Table currency is the settlement unit.** Buy-ins, bets, stacks, pots and
  Vault postings are integer cents of `open_tables.session_currency_code`.
  The client cannot register a table in a different currency or settle
  through a display-rate conversion. A keypad may convert *into* the table
  unit so someone can type a familiar figure; after that the number does
  not move again.
- **The Vault wallet is one currency.** `vault_summary` reports the available
  wallet's currency and only sums that currency. Chips on a table in another
  unit stay on that table until they are cashed off; they are not added into
  the Vault total as extra dollars.
- **Cloud mid-hand add-ons are not built.** Extra chips on a signed-in table
  would be a Vault buy-in, not a local rewrite of the pot. The table hides
  Add money on that path until a server top-up exists.
- **Disconnect timeout needs someone to poke the server.** A player who sits
  idle is folded after 45 seconds the next time an authorized phone calls
  view, act, start, or leave. There is no cron; if every phone is gone the
  hand waits until someone comes back.
- **A table's buy-in range is set by the published host.** `vault_register_table`
  reads the host from `open_tables` and refuses anyone else. The range is
  frozen once anyone has money on the table.
- **The sandbox backend is not a security boundary.** It lives on the device and
  belongs to whoever is holding the phone. It exists so the flows can be walked
  through with test money, and `VaultStore` steps over it the moment a real
  backend is reachable.
- **Compliance data is not sourced.** See above.

## Testing

The SQL side has an end-to-end harness that runs against a plain PostgreSQL
server — see `supabase/tests/README.md`. It walks a deposit, both kinds of
buy-in, a server-dealt hand, a departure and a cash-out, and hard-fails if a
guard does not hold: replays move nothing twice, a client-supplied hand
result is refused, balances stay non-negative, the ledger cannot be edited,
and the books reconcile. `30_poker_attacks.sql` covers a modified client
trying to name a winner, submit cards, change the board, act out of turn,
over-bet, rewrite the pot, replay an action, settle twice, recover committed
chips by leaving or by forging a finished hand, or change settlement by
picking a different currency.

The Swift side is covered by `PokerLeaderTests/SandboxVaultBackendTests.swift`
and `PokerLeaderTests/MoneyTests.swift`, which put the demo backend through the
same path and check the same invariants.
