-- ================================================================
-- SALARN — Complete Supabase Schema
-- Run this entire script in Supabase SQL Editor (once, from top to bottom)
-- ================================================================

-- ── EXTENSIONS ──────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ================================================================
-- TABLE: users
-- Mirrors auth.users but stores app-level profile + role
-- ================================================================
CREATE TABLE IF NOT EXISTS public.users (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id       UUID UNIQUE,                          -- links to auth.users.id
  email         TEXT NOT NULL UNIQUE,
  full_name     TEXT,
  role          TEXT NOT NULL DEFAULT 'user'
                  CHECK (role IN ('user', 'admin')),
  wallet_address TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast auth_id lookups (used on every request)
CREATE INDEX IF NOT EXISTS users_auth_id_idx ON public.users (auth_id);
CREATE INDEX IF NOT EXISTS users_email_idx ON public.users (email);

-- ================================================================
-- TABLE: user_balances
-- One row per user, tracks USD balance and investment totals
-- ================================================================
CREATE TABLE IF NOT EXISTS public.user_balances (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_email        TEXT NOT NULL UNIQUE REFERENCES public.users(email) ON DELETE CASCADE,
  balance_usd       NUMERIC(18, 8) NOT NULL DEFAULT 0 CHECK (balance_usd >= 0),
  total_invested    NUMERIC(18, 8) NOT NULL DEFAULT 0,
  total_profit_loss NUMERIC(18, 8) NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_balances_email_idx ON public.user_balances (user_email);

-- ================================================================
-- TABLE: cryptocurrencies
-- Admin-managed list of tradeable coins
-- ================================================================
CREATE TABLE IF NOT EXISTS public.cryptocurrencies (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  symbol      TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  price       NUMERIC(24, 8) NOT NULL DEFAULT 0,
  change_24h  NUMERIC(10, 4) NOT NULL DEFAULT 0,
  market_cap  NUMERIC(30, 2) NOT NULL DEFAULT 0,
  volume_24h  NUMERIC(30, 2) NOT NULL DEFAULT 0,
  icon_color  TEXT NOT NULL DEFAULT '#6366f1',
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS cryptos_symbol_idx    ON public.cryptocurrencies (symbol);
CREATE INDEX IF NOT EXISTS cryptos_active_idx    ON public.cryptocurrencies (is_active, market_cap DESC);

-- ================================================================
-- TABLE: portfolio
-- User holdings — one row per user+coin combination
-- ================================================================
CREATE TABLE IF NOT EXISTS public.portfolio (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_email    TEXT NOT NULL REFERENCES public.users(email) ON DELETE CASCADE,
  crypto_symbol TEXT NOT NULL REFERENCES public.cryptocurrencies(symbol) ON DELETE CASCADE,
  amount        NUMERIC(24, 8) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  avg_buy_price NUMERIC(24, 8) NOT NULL DEFAULT 0 CHECK (avg_buy_price >= 0),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_email, crypto_symbol)
);

CREATE INDEX IF NOT EXISTS portfolio_user_email_crypto_idx ON public.portfolio (user_email, crypto_symbol);

-- ================================================================
-- TABLE: transactions
-- All financial events: deposits, withdrawals, buys, sells, profits
-- ================================================================
CREATE TABLE IF NOT EXISTS public.transactions (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_email     TEXT NOT NULL REFERENCES public.users(email) ON DELETE CASCADE,
  type           TEXT NOT NULL
                   CHECK (type IN ('deposit', 'withdrawal', 'buy', 'sell', 'copy_profit')),
  amount         NUMERIC(18, 8) NOT NULL CHECK (amount > 0),
  crypto_symbol  TEXT,
  crypto_amount  NUMERIC(24, 8) CHECK (crypto_symbol IS NULL OR crypto_amount > 0),
  status         TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
  notes          TEXT,
  wallet_address TEXT,
  otp_code       TEXT,
  otp_verified   BOOLEAN DEFAULT FALSE,
  otp_expires_at TIMESTAMPTZ,
  reviewed_by    TEXT,
  reviewed_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS transactions_user_email_idx  ON public.transactions (user_email, created_at DESC);
CREATE INDEX IF NOT EXISTS transactions_status_idx      ON public.transactions (status);
CREATE INDEX IF NOT EXISTS transactions_type_idx        ON public.transactions (type);
CREATE INDEX IF NOT EXISTS transactions_reviewed_at_idx ON public.transactions (reviewed_at DESC);

-- ================================================================
-- TABLE: copy_traders
-- Admin-managed roster of traders users can copy
-- ================================================================
CREATE TABLE IF NOT EXISTS public.copy_traders (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  trader_name       TEXT NOT NULL,
  specialty         TEXT,
  total_profit_pct  NUMERIC(10, 2) NOT NULL DEFAULT 0,
  monthly_profit_pct NUMERIC(10, 2) NOT NULL DEFAULT 0,
  win_rate          NUMERIC(5, 2) NOT NULL DEFAULT 0 CHECK (win_rate BETWEEN 0 AND 100),
  total_trades      INTEGER NOT NULL DEFAULT 0 CHECK (total_trades >= 0),
  followers         INTEGER NOT NULL DEFAULT 0 CHECK (followers >= 0),
  profit_split_pct  NUMERIC(5, 2) NOT NULL DEFAULT 20 CHECK (profit_split_pct BETWEEN 0 AND 100),
  min_allocation    NUMERIC(18, 2) NOT NULL DEFAULT 100 CHECK (min_allocation >= 0),
  is_approved       BOOLEAN NOT NULL DEFAULT FALSE,
  risk_level        TEXT NOT NULL DEFAULT 'medium'
                      CHECK (risk_level IN ('low', 'medium', 'high')),
  avatar_color      TEXT NOT NULL DEFAULT '#6366f1',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS copy_traders_approved_idx ON public.copy_traders (is_approved, total_profit_pct DESC);

-- ================================================================
-- TABLE: copy_trades
-- Active user-to-trader copy relationships
-- ================================================================
CREATE TABLE IF NOT EXISTS public.copy_trades (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_email      TEXT NOT NULL REFERENCES public.users(email) ON DELETE CASCADE,
  trader_id       UUID NOT NULL REFERENCES public.copy_traders(id) ON DELETE CASCADE,
  trader_name     TEXT NOT NULL,
  allocation      NUMERIC(18, 2) NOT NULL CHECK (allocation > 0),
  profit_loss     NUMERIC(18, 8) NOT NULL DEFAULT 0,
  profit_loss_pct NUMERIC(10, 4) NOT NULL DEFAULT 0,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS copy_trades_user_email_idx       ON public.copy_trades (user_email, is_active);
CREATE INDEX IF NOT EXISTS copy_trades_trader_id_active_idx ON public.copy_trades (trader_id, is_active);

-- Prevent duplicate active copy trades for the same user+trader
CREATE UNIQUE INDEX IF NOT EXISTS unique_active_copy_trade
  ON public.copy_trades (user_email, trader_id)
  WHERE is_active = TRUE;

-- ================================================================
-- TABLE: platform_settings
-- Admin-editable key-value store for platform configuration
-- ================================================================
CREATE TABLE IF NOT EXISTS public.platform_settings (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key        TEXT NOT NULL UNIQUE,
  value      TEXT NOT NULL DEFAULT '',
  label      TEXT,
  updated_by TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── DEFAULT PLATFORM SETTINGS ────────────────────────────────────
INSERT INTO public.platform_settings (key, value, label) VALUES
  ('deposit_address_btc',      '',      'Bitcoin (BTC) Address'),
  ('deposit_address_eth',      '',      'Ethereum (ETH) Address'),
  ('deposit_address_usdt_trc20','',     'USDT TRC20 Address'),
  ('deposit_address_usdt_erc20','',     'USDT ERC20 Address'),
  ('deposit_address_bnb',      '',      'BNB Address'),
  ('trading_fee_pct',          '0.5',   'Trading Fee (%)'),
  ('withdrawal_fee_pct',       '1.0',   'Withdrawal Fee (%)'),
  ('min_deposit_usd',          '50',    'Minimum Deposit (USD)'),
  ('min_withdrawal_usd',       '20',    'Minimum Withdrawal (USD)'),
  ('platform_name',            'Salarn','Platform Name'),
  ('support_email',            '',      'Support Email'),
  ('telegram_support',         '',      'Telegram Support')
ON CONFLICT (key) DO NOTHING;

-- ================================================================
-- TRIGGER: auto-update updated_at on row changes
-- ================================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER user_balances_updated_at
  BEFORE UPDATE ON public.user_balances
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER cryptocurrencies_updated_at
  BEFORE UPDATE ON public.cryptocurrencies
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER portfolio_updated_at
  BEFORE UPDATE ON public.portfolio
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ================================================================
-- TRIGGER: auto-create user profile + balance row after Supabase signup
-- Fires when auth.users gets a new row (via Supabase Auth)
-- ================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Insert profile row
  INSERT INTO public.users (auth_id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data->>'full_name',
    'user'
  )
  ON CONFLICT (auth_id) DO UPDATE
    SET email     = EXCLUDED.email,
        full_name = COALESCE(EXCLUDED.full_name, public.users.full_name),
        updated_at = NOW();

  -- Insert zero-balance row for this user
  INSERT INTO public.user_balances (user_email, balance_usd, total_invested, total_profit_loss)
  VALUES (NEW.email, 0, 0, 0)
  ON CONFLICT (user_email) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Drop and recreate to ensure it's current
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ================================================================
-- FUNCTION: get_portfolio_value
-- Returns total USD value of a user's portfolio at current prices
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_portfolio_value(p_user_email TEXT)
RETURNS NUMERIC AS $$
DECLARE
  total_value NUMERIC := 0;
  p_row       RECORD;
  crypto_price NUMERIC;
BEGIN
  FOR p_row IN
    SELECT crypto_symbol, amount
    FROM public.portfolio
    WHERE user_email = p_user_email
  LOOP
    SELECT price INTO crypto_price
    FROM public.cryptocurrencies
    WHERE symbol = p_row.crypto_symbol
    LIMIT 1;

    total_value := total_value + (COALESCE(crypto_price, 0) * p_row.amount);
  END LOOP;

  RETURN total_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ================================================================
-- ROW LEVEL SECURITY (RLS)
-- ================================================================

-- Enable RLS on all tables
ALTER TABLE public.users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_balances      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cryptocurrencies   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.portfolio          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.copy_traders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.copy_trades        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_settings  ENABLE ROW LEVEL SECURITY;

-- ── Helper: is the calling user an admin? ────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE auth_id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = '';

-- ── users ────────────────────────────────────────────────────────
-- Anyone can read their own profile; admins can read/write all
CREATE POLICY "users_select_own"   ON public.users FOR SELECT USING (auth_id = auth.uid() OR public.is_admin());
CREATE POLICY "users_update_own"   ON public.users FOR UPDATE USING (auth_id = auth.uid() OR public.is_admin());
CREATE POLICY "users_insert"       ON public.users FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "users_admin_delete" ON public.users FOR DELETE USING (public.is_admin());

-- ── user_balances ────────────────────────────────────────────────
CREATE POLICY "balances_select" ON public.user_balances FOR SELECT
  USING (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());
CREATE POLICY "balances_insert" ON public.user_balances FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "balances_update" ON public.user_balances FOR UPDATE
  USING (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());

-- ── cryptocurrencies ─────────────────────────────────────────────
-- Everyone can read; only admins can write
CREATE POLICY "cryptos_select_all"  ON public.cryptocurrencies FOR SELECT USING (TRUE);
CREATE POLICY "cryptos_admin_write" ON public.cryptocurrencies FOR ALL    USING (public.is_admin());

-- ── portfolio ────────────────────────────────────────────────────
CREATE POLICY "portfolio_select" ON public.portfolio FOR SELECT
  USING (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());
CREATE POLICY "portfolio_write" ON public.portfolio FOR ALL
  USING (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());

-- ── transactions ─────────────────────────────────────────────────
CREATE POLICY "txns_select" ON public.transactions FOR SELECT
  USING (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());
CREATE POLICY "txns_insert" ON public.transactions FOR INSERT
  WITH CHECK (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());
CREATE POLICY "txns_update" ON public.transactions FOR UPDATE
  USING (public.is_admin());

-- ── copy_traders ─────────────────────────────────────────────────
-- All authenticated users can read approved traders; admins manage all
CREATE POLICY "traders_select_approved" ON public.copy_traders FOR SELECT USING (is_approved = TRUE OR public.is_admin());
CREATE POLICY "traders_admin_write"     ON public.copy_traders FOR ALL    USING (public.is_admin());

-- ── copy_trades ──────────────────────────────────────────────────
CREATE POLICY "copy_trades_select" ON public.copy_trades FOR SELECT
  USING (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());
CREATE POLICY "copy_trades_insert" ON public.copy_trades FOR INSERT
  WITH CHECK (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());
CREATE POLICY "copy_trades_update" ON public.copy_trades FOR UPDATE
  USING (user_email = (SELECT email FROM public.users WHERE auth_id = auth.uid()) OR public.is_admin());

-- ── platform_settings ────────────────────────────────────────────
-- All authenticated users can read; only admins can write
CREATE POLICY "settings_select" ON public.platform_settings FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "settings_write"  ON public.platform_settings FOR ALL   USING (public.is_admin());

-- ================================================================
-- GRANTS (for anon and authenticated Supabase roles)
-- ================================================================
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.cryptocurrencies TO anon, authenticated;
GRANT SELECT ON public.copy_traders TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_balances TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portfolio TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.copy_trades TO authenticated;
GRANT SELECT ON public.platform_settings TO authenticated;
GRANT INSERT, UPDATE ON public.platform_settings TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.copy_traders TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.cryptocurrencies TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.users TO authenticated;
GRANT DELETE ON public.copy_trades TO authenticated;
GRANT DELETE ON public.transactions TO authenticated;

-- ================================================================
-- DONE — Schema is complete and ready for production
-- ================================================================
