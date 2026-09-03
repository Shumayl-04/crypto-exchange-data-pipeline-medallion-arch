-- Databricks notebook source
-- DBTITLE 1,Project title
-- MAGIC %md
-- MAGIC # Gold Layer
-- MAGIC
-- MAGIC This notebook defines the curated business-ready tables in `crypto_exchange.gold`. These tables sit on top of the Silver layer and provide stable, analytics-friendly datasets for downstream dashboarding and KPI reporting.

-- COMMAND ----------

-- DBTITLE 1,Latest asset snapshot header
-- MAGIC %md
-- MAGIC ## Latest asset snapshot
-- MAGIC
-- MAGIC A latest-state gold table with one current record per symbol. This is the primary dataset for overview tiles and current-market dashboards.

-- COMMAND ----------

-- DBTITLE 1,gold_asset_snapshot
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.gold_asset_snapshot
COMMENT "Gold — latest market snapshot per asset enriched for business consumption"
AS
WITH ranked_market AS (
  SELECT
    m.symbol,
    m.coin_id,
    COALESCE(m.coin_name, m.symbol)                                   AS coin_name,
    m.price,
    m.highest,
    m.lowest,
    m.change_24h,
    m.price_position,
    m.market_cap,
    m.volume,
    m.source_exchange,
    m.price_change_direction,
    m.market_cap_tier,
    m.price_timestamp,
    m.ingestion_timestamp,
    m.api_source,
    ROW_NUMBER() OVER (
      PARTITION BY m.symbol
      ORDER BY m.price_timestamp DESC, m.ingestion_timestamp DESC
    )                                                                 AS rn
  FROM crypto_exchange.silver.silver_market_data m
)
SELECT
  symbol,
  coin_id,
  coin_name,
  source_exchange,
  price                                                           AS current_price,
  highest                                                         AS day_high,
  lowest                                                          AS day_low,
  ROUND(highest - lowest, 6)                                      AS intraday_range,
  change_24h,
  price_change_direction,
  market_cap,
  market_cap_tier,
  volume,
  ROUND(price_position, 4)                                        AS price_position,
  CASE
    WHEN price_position >= 0.80 THEN 'NEAR_HIGH'
    WHEN price_position <= 0.20 THEN 'NEAR_LOW'
    ELSE 'MID_RANGE'
  END                                                             AS price_band,
  CAST(price_timestamp AS DATE)                                   AS snapshot_date,
  price_timestamp,
  ingestion_timestamp,
  api_source
FROM ranked_market
WHERE rn = 1;

-- COMMAND ----------

-- DBTITLE 1,Daily market summary header
-- MAGIC %md
-- MAGIC ## Daily market summary
-- MAGIC
-- MAGIC Aggregated market KPIs by day, exchange, and market-cap tier for trend analysis.

-- COMMAND ----------

-- DBTITLE 1,gold_market_summary_daily
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.gold_market_summary_daily
COMMENT "Gold — daily market summary by exchange and market-cap tier"
AS
SELECT
  CAST(price_timestamp AS DATE)                                   AS snapshot_date,
  source_exchange,
  COALESCE(market_cap_tier, 'UNCLASSIFIED')                       AS market_cap_tier,
  COUNT(*)                                                        AS asset_count,
  ROUND(AVG(current_price), 6)                                    AS avg_price,
  ROUND(AVG(change_24h), 6)                                       AS avg_change_24h,
  ROUND(AVG(price_position), 4)                                   AS avg_price_position,
  SUM(COALESCE(market_cap, 0))                                    AS total_market_cap,
  SUM(COALESCE(volume, 0))                                        AS total_volume,
  SUM(CASE WHEN price_change_direction = 'UP' THEN 1 ELSE 0 END)  AS gainers_count,
  SUM(CASE WHEN price_change_direction = 'DOWN' THEN 1 ELSE 0 END) AS losers_count,
  SUM(CASE WHEN price_change_direction = 'FLAT' THEN 1 ELSE 0 END) AS flat_count,
  MAX(price_timestamp)                                            AS latest_price_timestamp,
  MAX(ingestion_timestamp)                                        AS latest_ingestion_timestamp
FROM crypto_exchange.gold.gold_asset_snapshot
GROUP BY
  CAST(price_timestamp AS DATE),
  source_exchange,
  COALESCE(market_cap_tier, 'UNCLASSIFIED');

-- COMMAND ----------

-- DBTITLE 1,Latest conversion reference header
-- MAGIC %md
-- MAGIC ## Latest conversion reference
-- MAGIC
-- MAGIC The most recent conversion rate for each currency pair, enriched with readable asset names for downstream use in selectors and pair cards.

-- COMMAND ----------

-- DBTITLE 1,gold_conversion_latest
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.gold_conversion_latest
COMMENT "Gold — latest available conversion rate for each asset pair"
AS
WITH ranked_conversions AS (
  SELECT
    c.from_symbol,
    c.to_symbol,
    c.pair,
    c.amount,
    c.converted_amount,
    c.rate,
    c.inverse_rate,
    c.ingestion_timestamp,
    c.api_source,
    ROW_NUMBER() OVER (
      PARTITION BY c.from_symbol, c.to_symbol
      ORDER BY c.ingestion_timestamp DESC
    )                                                             AS rn
  FROM crypto_exchange.silver.silver_conversions c
)
SELECT
  rc.from_symbol,
  COALESCE(f.name, rc.from_symbol)                                AS from_asset_name,
  rc.to_symbol,
  COALESCE(t.name, rc.to_symbol)                                  AS to_asset_name,
  rc.pair,
  rc.amount,
  rc.converted_amount,
  rc.rate,
  rc.inverse_rate,
  rc.ingestion_timestamp,
  rc.api_source
FROM ranked_conversions rc
LEFT JOIN crypto_exchange.silver.silver_crypto_list f
  ON rc.from_symbol = f.symbol
LEFT JOIN crypto_exchange.silver.silver_crypto_list t
  ON rc.to_symbol = t.symbol
WHERE rc.rn = 1;

-- COMMAND ----------

-- DBTITLE 1,Stablecoin monitor header
-- MAGIC %md
-- MAGIC ## Stablecoin monitor
-- MAGIC
-- MAGIC A focused monitoring table for stablecoins, useful for dashboard alerts and peg-deviation widgets.

-- COMMAND ----------

-- DBTITLE 1,gold_stablecoin_monitor
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.gold_stablecoin_monitor
COMMENT "Gold — stablecoin monitoring view with peg deviation metrics"
AS
SELECT
  symbol,
  coin_name,
  source_exchange,
  current_price,
  day_high,
  day_low,
  change_24h,
  ROUND(ABS(current_price - 1.0), 6)                              AS peg_deviation_abs,
  ROUND(ABS(current_price - 1.0) * 100, 4)                        AS peg_deviation_pct,
  CASE
    WHEN ABS(current_price - 1.0) >= 0.05 THEN 'CRITICAL'
    WHEN ABS(current_price - 1.0) >= 0.01 THEN 'WARNING'
    ELSE 'NORMAL'
  END                                                             AS peg_status,
  snapshot_date,
  price_timestamp,
  ingestion_timestamp,
  api_source
FROM crypto_exchange.gold.gold_asset_snapshot
WHERE symbol IN ('USDT', 'USDC', 'BUSD', 'DAI', 'TUSD', 'FDUSD', 'USDP');

-- COMMAND ----------

-- DBTITLE 1,Exchange coverage header
-- MAGIC %md
-- MAGIC ## Exchange coverage summary
-- MAGIC
-- MAGIC An exchange-level table that summarizes current asset coverage, valuation, and movement signals.

-- COMMAND ----------

-- DBTITLE 1,gold_exchange_coverage
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.gold_exchange_coverage
COMMENT "Gold — exchange-level coverage and market summary based on latest asset snapshot"
AS
SELECT
  source_exchange,
  COUNT(*)                                                        AS tracked_assets,
  COUNT(DISTINCT market_cap_tier)                                 AS market_cap_tiers_present,
  ROUND(AVG(change_24h), 6)                                       AS avg_change_24h,
  SUM(COALESCE(market_cap, 0))                                    AS total_market_cap,
  SUM(COALESCE(volume, 0))                                        AS total_volume,
  SUM(CASE WHEN price_change_direction = 'UP' THEN 1 ELSE 0 END)  AS gainers_count,
  SUM(CASE WHEN price_change_direction = 'DOWN' THEN 1 ELSE 0 END) AS losers_count,
  MAX(price_timestamp)                                            AS latest_price_timestamp,
  MAX(ingestion_timestamp)                                        AS latest_ingestion_timestamp
FROM crypto_exchange.gold.gold_asset_snapshot
GROUP BY source_exchange;