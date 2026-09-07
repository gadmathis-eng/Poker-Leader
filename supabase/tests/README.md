# Vault ledger tests

`10_vault_flow.sql` walks the whole money path — deposit, table buy-in from the
Vault, direct Apple Pay buy-in, a hand, leaving the table, and a cash-out — and
checks the parts that have to hold: replayed requests must not move money twice,
a hand must be zero-sum, only the host may post one, a balance must never go
negative, the ledger must be immutable, and the books must reconcile.

It runs against a plain PostgreSQL server. `00_supabase_stubs.sql` supplies the
few Supabase pieces the migration leans on (`auth.users`, `auth.uid()`, and the
`anon` / `authenticated` / `service_role` roles), with `auth.uid()` reading a
session setting so the script can switch between players.

```bash
sudo -u postgres dropdb --if-exists vaultdemo
sudo -u postgres createdb vaultdemo
sudo -u postgres psql -v ON_ERROR_STOP=1 -d vaultdemo \
  -f supabase/tests/00_supabase_stubs.sql \
  -f supabase/migrations/20260907120000_vault_ledger.sql \
  -f supabase/tests/10_vault_flow.sql
```

Every `NOTICE: rejected as expected: …` line is a guard doing its job. The two
reconciliation queries near the end must both return no rows.
