# Salarn — Crypto Copy-Trading Platform

A full-featured crypto copy-trading web application. Users can deposit funds, trade cryptocurrencies, copy expert traders, and manage their portfolio. Admins have a full control panel.

## Tech Stack

- **Frontend**: React 18, TypeScript, Vite, Tailwind CSS v4
- **Auth & DB**: Supabase (Auth + PostgreSQL)
- **UI**: Radix UI, Framer Motion, Recharts, Lucide Icons
- **Routing**: React Router v6
- **State**: TanStack Query v5

---

## 1. Supabase Setup

### Step 1 — Create a Supabase project
Go to [supabase.com](https://supabase.com) → New Project.

### Step 2 — Run the schema
Open **SQL Editor** in your Supabase dashboard and run the entire contents of `SUPABASE_SCHEMA.sql`. This creates all tables, RLS policies, triggers, and indexes.

### Step 3 — Get your credentials
Go to **Settings → API**:
- `Project URL` → `VITE_SUPABASE_URL`
- `anon public` key → `VITE_SUPABASE_ANON_KEY`

### Step 4 — Configure Auth settings
In **Authentication → URL Configuration**:
- **Site URL**: your deployed domain (e.g. `https://salarn.vercel.app`)
- **Redirect URLs**: add `https://salarn.vercel.app/auth/callback`

In **Authentication → Email**:
- For instant access without email confirmation: disable **"Confirm email"** in Authentication → Providers → Email.

---

## 2. Local Development

```bash
# Install dependencies
pnpm install

# Create .env.local with your Supabase credentials
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key

# Start dev server
pnpm run dev
```

---

## 3. Vercel Deployment

### Step 1 — Import the repo into Vercel
1. Push this repo to GitHub
2. Go to [vercel.com](https://vercel.com) → New Project → Import your repo

### Step 2 — Configure build settings in Vercel

| Setting | Value |
|---------|-------|
| **Framework Preset** | Other |
| **Build Command** | `npm install -g pnpm@10 && pnpm install --filter @workspace/salarn && pnpm --filter @workspace/salarn run build` |
| **Output Directory** | `artifacts/salarn/dist` |
| **Install Command** | *(leave empty)* |
| **Root Directory** | *(leave empty — use repo root)* |

> **Note**: The `vercel.json` file in `artifacts/salarn/` handles SPA routing rewrites automatically.

### Step 3 — Set Environment Variables in Vercel

| Variable | Value |
|----------|-------|
| `VITE_SUPABASE_URL` | `https://your-project.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | `your-anon-key` |
| `BASE_PATH` | `/` |

### Step 4 — Deploy
Click **Deploy**. Vercel will build and deploy your app.

---

## 4. Making Someone an Admin

After signup, run this SQL in Supabase SQL Editor:

```sql
UPDATE public.users
SET role = 'admin'
WHERE email = 'admin@example.com';
```

The user will see the Admin panel on next sign-in.

---

## 5. Features

### User Features
- **Landing page** — Live crypto ticker, feature highlights, top trader showcase
- **Sign Up / Sign In** — Email+password via Supabase Auth, PKCE flow, no race conditions
- **Forgot Password** — Email reset with secure link
- **Dashboard** — Portfolio chart, live market data, quick actions
- **Portfolio** — Holdings breakdown with P&L, pie and bar charts
- **Trade** — Buy/sell cryptos with real-time price charts
- **Copy Trading** — Follow expert traders with configurable allocation
- **Transactions** — Full history with OTP-secured withdrawals
- **Settings** — Profile management

### Admin Features
- **Admin Dashboard** — Platform overview with charts and stats
- **Manage Users** — View all users, toggle admin role
- **Manage Cryptos** — Add/edit/delete coins, sync live prices
- **Manage Traders** — Add/approve/remove copy traders
- **Transactions** — Approve/reject deposits and withdrawals, generate OTP codes
- **Platform Settings** — Deposit addresses, fees, platform info

---

## 6. Auth Notes (No Race Conditions)

- **Sign Up**: Uses Supabase PKCE flow. If email confirmation is disabled, session is created immediately and the auth state change redirects the user automatically.
- **Sign In**: After `signInWithPassword` succeeds, the user row is force-fetched from the database (bypassing cache) to ensure the role is always fresh. A 8-second safety timeout prevents infinite loading.
- **Admin Role Switch**: The `AdminRoute` component checks the live `user.role` from the database on every navigation. After an admin grants/revokes a role, the affected user sees the change on their next page load.
- **Auth Callback**: Handles PKCE code exchange, implicit token flow, recovery links, and expired/used links — all with user-friendly error messages.
- **Sign Out**: Clears local auth state before calling Supabase to prevent race conditions where a stale session could reload.
