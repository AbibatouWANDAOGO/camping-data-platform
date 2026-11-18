-- Databricks notebook source
   CREATE OR REPLACE TABLE camping.gold.dp_occupation_yield_sans_commentaires AS
   SELECT * FROM camping.gold.dp_occupation_yield;

-- COMMAND ----------

   SELECT column_name, comment FROM camping.information_schema.columns
   WHERE table_schema = 'gold' AND table_name = 'dp_occupation_yield_sans_commentaires'
   ORDER BY ordinal_position;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC for c in ["date_nuit", "camping", "categorie_code", "emplacements_disponibles", "emplacements_occupes",
-- MAGIC              "taux_occupation", "chiffre_affaires", "nuitees_directes", "part_direct"]:
-- MAGIC        spark.sql(f"ALTER TABLE camping.gold.dp_occupation_yield_sans_commentaires ALTER COLUMN {c} COMMENT ''")