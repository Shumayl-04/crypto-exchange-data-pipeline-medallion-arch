-- Databricks notebook source
-- DBTITLE 1,Project title
-- MAGIC %md
-- MAGIC # Final Analytics
-- MAGIC
-- MAGIC This notebook creates dashboard-ready analytics tables in `crypto_exchange.gold`. It builds on the Gold layer and prepares focused datasets for KPI cards, leaderboards, trend views, and alert-oriented dashboard components.

-- COMMAND ----------

-- DBTITLE 1,KPI overview header
-- MAGIC %md
-- MAGIC ## KPI overview
-- MAGIC
-- MAGIC A single-row KPI table for top-level dashboard scorecards.

-- COMMAND ----------

-- DBTITLE 1,dashboard_kpi_overview
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.dashboard_kpi_overview
COMMENT "Gold analytics — single-row KPI table for dashboard scorecards"
AS
SELECT
  current_timestamp()                                              AS analytics_generated_at,
  MAX(snapshot_date)                                               AS latest_snapshot_date,
  MAX(price_timestamp)                                             AS latest_price_timestamp,
  COUNT(*)                                                         AS tracked_assets,
  COUNT(DISTINCT source_exchange)                                  AS exchanges_covered,
  SUM(CASE WHEN price_change_direction = 'UP' THEN 1 ELSE 0 END)   AS gainers_count,
  SUM(CASE WHEN price_change_direction = 'DOWN' THEN 1 ELSE 0 END) AS losers_count,
  SUM(CASE WHEN market_cap_tier = 'LARGE_CAP' THEN 1 ELSE 0 END)   AS large_cap_assets,
  ROUND(AVG(change_24h), 6)                                        AS avg_change_24h,
  SUM(COALESCE(market_cap, 0))                                     AS total_market_cap,
  SUM(COALESCE(volume, 0))                                         AS total_volume
FROM crypto_exchange.gold.gold_asset_snapshot;

-- COMMAND ----------

-- DBTITLE 1,Top movers header
-- MAGIC %md
-- MAGIC ## Top movers
-- MAGIC
-- MAGIC A leaderboard dataset with both top gainers and top losers from the latest snapshot.

-- COMMAND ----------

-- DBTITLE 1,dashboard_top_movers
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.dashboard_top_movers
COMMENT "Gold analytics — latest top gainers and losers for dashboard leaderboards"
AS
WITH latest_snapshot AS (
  SELECT *
  FROM crypto_exchange.gold.gold_asset_snapshot
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM crypto_exchange.gold.gold_asset_snapshot)
), ranked AS (
  SELECT
    symbol,
    coin_name,
    source_exchange,
    current_price,
    change_24h,
    market_cap,
    volume,
    price_band,
    ROW_NUMBER() OVER (ORDER BY change_24h DESC, market_cap DESC)  AS gain_rank,
    ROW_NUMBER() OVER (ORDER BY change_24h ASC, market_cap DESC)   AS loss_rank
  FROM latest_snapshot
)
SELECT
  'TOP_GAINER'                                                     AS mover_group,
  gain_rank                                                        AS mover_rank,
  symbol,
  coin_name,
  source_exchange,
  current_price,
  change_24h,
  market_cap,
  volume,
  price_band
FROM ranked
WHERE gain_rank <= 10
UNION ALL
SELECT
  'TOP_LOSER'                                                      AS mover_group,
  loss_rank                                                        AS mover_rank,
  symbol,
  coin_name,
  source_exchange,
  current_price,
  change_24h,
  market_cap,
  volume,
  price_band
FROM ranked
WHERE loss_rank <= 10;

-- COMMAND ----------

-- DBTITLE 1,Market leaders header
-- MAGIC %md
-- MAGIC ## Market leaders
-- MAGIC
-- MAGIC A reusable table for top assets by market capitalization and volume.

-- COMMAND ----------

-- DBTITLE 1,dashboard_market_leaders
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.dashboard_market_leaders
COMMENT "Gold analytics — ranked current market leaders by market cap and volume"
AS
SELECT
  symbol,
  coin_name,
  source_exchange,
  current_price,
  change_24h,
  market_cap,
  volume,
  market_cap_tier,
  DENSE_RANK() OVER (ORDER BY market_cap DESC, volume DESC)        AS market_cap_rank,
  DENSE_RANK() OVER (ORDER BY volume DESC, market_cap DESC)        AS volume_rank,
  snapshot_date,
  price_timestamp
FROM crypto_exchange.gold.gold_asset_snapshot;

-- COMMAND ----------

-- DBTITLE 1,Exchange breakdown header
-- MAGIC %md
-- MAGIC ## Exchange breakdown
-- MAGIC
-- MAGIC Dashboard aggregates by exchange and market-cap tier, useful for stacked charts and comparison widgets.

-- COMMAND ----------

-- DBTITLE 1,dashboard_exchange_breakdown
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.dashboard_exchange_breakdown
COMMENT "Gold analytics — exchange and tier breakdown for dashboard segment analysis"
AS
SELECT
  snapshot_date,
  source_exchange,
  market_cap_tier,
  asset_count,
  avg_price,
  avg_change_24h,
  avg_price_position,
  total_market_cap,
  total_volume,
  gainers_count,
  losers_count,
  flat_count
FROM crypto_exchange.gold.gold_market_summary_daily;

-- COMMAND ----------

-- DBTITLE 1,Conversion spotlight header
-- MAGIC %md
-- MAGIC ## Conversion spotlight
-- MAGIC
-- MAGIC A dashboard-friendly subset of conversion data focused on the most common benchmark assets.

-- COMMAND ----------

-- DBTITLE 1,dashboard_conversion_spotlight
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.dashboard_conversion_spotlight
COMMENT "Gold analytics — latest benchmark conversion pairs for dashboard selectors and pair cards"
AS
SELECT
  from_symbol,
  from_asset_name,
  to_symbol,
  to_asset_name,
  pair,
  amount,
  converted_amount,
  rate,
  inverse_rate,
  ingestion_timestamp,
  api_source
FROM crypto_exchange.gold.gold_conversion_latest
WHERE from_symbol IN ('BTC', 'ETH', 'BNB', 'USDT', 'USDC')
   OR to_symbol IN ('BTC', 'ETH', 'BNB', 'USDT', 'USDC');

-- COMMAND ----------

-- DBTITLE 1,Stablecoin alerts header
-- MAGIC %md
-- MAGIC ## Stablecoin alerts
-- MAGIC
-- MAGIC An alert-ready view containing only stablecoins that need attention.

-- COMMAND ----------

-- DBTITLE 1,dashboard_stablecoin_alerts
CREATE OR REFRESH MATERIALIZED VIEW crypto_exchange.gold.dashboard_stablecoin_alerts
COMMENT "Gold analytics — alert-ready stablecoin deviations for dashboard monitoring"
AS
SELECT
  symbol,
  coin_name,
  source_exchange,
  current_price,
  peg_deviation_abs,
  peg_deviation_pct,
  peg_status,
  change_24h,
  snapshot_date,
  price_timestamp,
  ingestion_timestamp
FROM crypto_exchange.gold.gold_stablecoin_monitor
WHERE peg_status IN ('WARNING', 'CRITICAL');