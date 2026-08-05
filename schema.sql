-- ========================================================
-- NUBANK 25 MONTHS FINANCIAL DASHBOARD - SUPABASE DDL SCHEMA
-- ========================================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Create Categories Table
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    type VARCHAR(20) CHECK (type IN ('INCOME', 'EXPENSE', 'TRANSFER', 'INVESTMENT', 'CRYPTO')),
    color_code VARCHAR(7) DEFAULT '#0284C7',
    icon_name VARCHAR(50) DEFAULT 'wallet',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Create Counterparties Table (CRM Financeiro)
CREATE TABLE IF NOT EXISTS public.counterparties (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    document VARCHAR(50) DEFAULT 'N/A',
    total_volume NUMERIC(15, 2) DEFAULT 0.00,
    transaction_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Create Main Transactions Table
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guid VARCHAR(100) UNIQUE NOT NULL,
    transaction_date TIMESTAMPTZ NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    type VARCHAR(10) CHECK (type IN ('INFLOW', 'OUTFLOW')),
    description TEXT NOT NULL,
    category_name VARCHAR(100) NOT NULL,
    counterparty_name VARCHAR(255) DEFAULT 'Não Especificado',
    payment_method VARCHAR(50) DEFAULT 'PIX',
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Create Monthly Summaries Table (DRE Cache Performance)
CREATE TABLE IF NOT EXISTS public.monthly_summaries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    year_month VARCHAR(7) NOT NULL UNIQUE, -- YYYY-MM
    total_inflow NUMERIC(15, 2) DEFAULT 0.00,
    total_outflow NUMERIC(15, 2) DEFAULT 0.00,
    net_result NUMERIC(15, 2) DEFAULT 0.00,
    commitment_rate NUMERIC(5, 2) DEFAULT 0.00,
    transaction_count INT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Create Indexes for High Performance Querying
CREATE INDEX IF NOT EXISTS idx_transactions_date ON public.transactions(transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON public.transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON public.transactions(category_name);
CREATE INDEX IF NOT EXISTS idx_transactions_counterparty ON public.transactions(counterparty_name);

-- 7. Trigger Procedure for Automatic DRE Monthly Aggregation
CREATE OR REPLACE FUNCTION public.recalculate_monthly_summary()
RETURNS TRIGGER AS $$
DECLARE
    target_ym VARCHAR(7);
BEGIN
    IF (TG_OP = 'DELETE') THEN
        target_ym := TO_CHAR(OLD.transaction_date, 'YYYY-MM');
    ELSE
        target_ym := TO_CHAR(NEW.transaction_date, 'YYYY-MM');
    END IF;

    INSERT INTO public.monthly_summaries (year_month, total_inflow, total_outflow, net_result, commitment_rate, transaction_count, updated_at)
    SELECT 
        target_ym,
        COALESCE(SUM(CASE WHEN type = 'INFLOW' THEN amount ELSE 0 END), 0) AS total_inflow,
        COALESCE(SUM(CASE WHEN type = 'OUTFLOW' THEN ABS(amount) ELSE 0 END), 0) AS total_outflow,
        COALESCE(SUM(amount), 0) AS net_result,
        CASE 
            WHEN SUM(CASE WHEN type = 'INFLOW' THEN amount ELSE 0 END) > 0 
            THEN ROUND((SUM(CASE WHEN type = 'OUTFLOW' THEN ABS(amount) ELSE 0 END) / SUM(CASE WHEN type = 'INFLOW' THEN amount ELSE 0 END)) * 100, 2)
            ELSE 100.00
        END AS commitment_rate,
        COUNT(*) AS transaction_count
    FROM public.transactions
    WHERE TO_CHAR(transaction_date, 'YYYY-MM') = target_ym
    ON CONFLICT (year_month) DO UPDATE SET
        total_inflow = EXCLUDED.total_inflow,
        total_outflow = EXCLUDED.total_outflow,
        net_result = EXCLUDED.net_result,
        commitment_rate = EXCLUDED.commitment_rate,
        transaction_count = EXCLUDED.transaction_count,
        updated_at = NOW();

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_monthly_summary ON public.transactions;
CREATE TRIGGER trg_update_monthly_summary
AFTER INSERT OR UPDATE OR DELETE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.recalculate_monthly_summary();

-- 8. Enable Row Level Security (RLS) & Public Policies for Demo
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.counterparties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_summaries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow Public Select Transactions" ON public.transactions FOR SELECT USING (true);
CREATE POLICY "Allow Public Insert Transactions" ON public.transactions FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow Public Select Categories" ON public.categories FOR SELECT USING (true);
CREATE POLICY "Allow Public Select Counterparties" ON public.counterparties FOR SELECT USING (true);
CREATE POLICY "Allow Public Select Monthly Summaries" ON public.monthly_summaries FOR SELECT USING (true);
