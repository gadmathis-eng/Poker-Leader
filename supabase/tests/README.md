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
  -f supabase/migrations/20260904120000_open_tables.sql \
  -f supabase/migrations/20260907120000_vault_ledger.sql \
  -f supabase/migrations/20260907180000_vault_security_hardening.sql \
  -f supabase/migrations/20260907190000_open_tables_lockdown.sql \
  -f supabase/tests/10_vault_flow.sql \
  -f supabase/tests/20_vault_attacks.sql
```

Every `NOTICE: rejected as expected: …` line is a guard doing its job. The two
reconciliation queries at the end of each script must both return no rows.
`20_vault_attacks.sql` is the post-hardening suite: table takeover, forged
seats, leftover client-chosen deposit confirm, over-withdrawal, and privacy.
