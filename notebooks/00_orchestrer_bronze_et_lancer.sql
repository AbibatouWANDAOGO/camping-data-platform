-- Databricks notebook source
SHOW CATALOGS;

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS camping;

-- COMMAND ----------

USE CATALOG camping;

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

-- COMMAND ----------

CREATE VOLUME IF NOT EXISTS bronze.depot;

-- COMMAND ----------

SHOW SCHEMAS IN camping;

-- COMMAND ----------

SHOW VOLUMES IN camping.bronze;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC base = "/Volumes/camping/bronze/depot/"
-- MAGIC for d in ["pms", "ota", "iot", "clients", "consentements",
-- MAGIC           "referentiel/emplacements", "referentiel/campings", "referentiel/finalites"]:
-- MAGIC     dbutils.fs.mkdirs(base + d)

-- COMMAND ----------

LIST '/Volumes/camping/bronze/depot/pms/';

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.sejours_pms AS
SELECT *, _metadata.file_path AS fichier_source, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/pms/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------


CREATE OR REPLACE TABLE bronze.export_ota AS
SELECT *, _metadata.file_path AS fichier_source, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/ota/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.emplacements AS
SELECT *, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/referentiel/emplacements/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.campings AS
SELECT *, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/referentiel/campings/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.releves_compteurs AS
SELECT *, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/iot/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.clients_pms AS
SELECT *, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/clients/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.consentements AS
SELECT *, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/consentements/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.finalites AS
SELECT *, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/referentiel/finalites/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

SELECT 'sejours_pms' AS table_bronze, count(*) AS lignes, 16 AS attendu FROM camping.bronze.sejours_pms
UNION ALL SELECT 'export_ota', count(*), 3 FROM camping.bronze.export_ota
UNION ALL SELECT 'emplacements', count(*), 12 FROM camping.bronze.emplacements
UNION ALL SELECT 'campings', count(*), 1 FROM camping.bronze.campings
UNION ALL SELECT 'releves_compteurs', count(*), 132 FROM camping.bronze.releves_compteurs
UNION ALL SELECT 'clients_pms', count(*), 18 FROM camping.bronze.clients_pms
UNION ALL SELECT 'consentements', count(*), 25 FROM camping.bronze.consentements
UNION ALL SELECT 'finalites', count(*), 5 FROM camping.bronze.finalites;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os
-- MAGIC for racine, dossiers, fichiers in os.walk("/Volumes/camping/bronze/depot"):
-- MAGIC     for f in fichiers:
-- MAGIC         print(os.path.join(racine, f))

-- COMMAND ----------

-- MAGIC %python
-- MAGIC base = "/Volumes/camping/bronze/depot/referentiel/"
-- MAGIC for nom in ["emplacements", "campings", "finalites"]:
-- MAGIC     dbutils.fs.mkdirs(base + nom)
-- MAGIC     dbutils.fs.mv(base + nom + ".csv", base + nom + "/" + nom + ".csv")

-- COMMAND ----------

CREATE OR REPLACE TABLE camping.bronze.emplacements AS
SELECT *, _metadata.file_path AS fichier_source, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/referentiel/emplacements/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE camping.bronze.campings AS
SELECT *, _metadata.file_path AS fichier_source, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/referentiel/campings/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

CREATE OR REPLACE TABLE camping.bronze.finalites AS
SELECT *, _metadata.file_path AS fichier_source, current_timestamp() AS charge_le
FROM read_files('/Volumes/camping/bronze/depot/referentiel/finalites/', format => 'csv', header => true, inferColumnTypes => false);

-- COMMAND ----------

SELECT 'sejours_pms' AS table_bronze, count(*) AS lignes, 16 AS attendu FROM camping.bronze.sejours_pms
UNION ALL SELECT 'export_ota', count(*), 3 FROM camping.bronze.export_ota
UNION ALL SELECT 'emplacements', count(*), 12 FROM camping.bronze.emplacements
UNION ALL SELECT 'campings', count(*), 1 FROM camping.bronze.campings
UNION ALL SELECT 'releves_compteurs', count(*), 132 FROM camping.bronze.releves_compteurs
UNION ALL SELECT 'clients_pms', count(*), 18 FROM camping.bronze.clients_pms
UNION ALL SELECT 'consentements', count(*), 25 FROM camping.bronze.consentements
UNION ALL SELECT 'finalites', count(*), 5 FROM camping.bronze.finalites;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC dbutils.fs.mkdirs("/Volumes/camping/bronze/depot/scripts")

-- COMMAND ----------

LIST '/Volumes/camping/bronze/depot/scripts/';

-- COMMAND ----------

-- MAGIC %python
-- MAGIC def split_sql(text):
-- MAGIC     out, cur, q = [], [], False
-- MAGIC     for line in text.splitlines():
-- MAGIC         if not q and line.strip().startswith("--"):
-- MAGIC             continue
-- MAGIC         for ch in line + "\n":
-- MAGIC             if ch == "'":
-- MAGIC                 q = not q
-- MAGIC             if ch == ";" and not q:
-- MAGIC                 s = "".join(cur).strip()
-- MAGIC                 if s:
-- MAGIC                     out.append(s)
-- MAGIC                 cur = []
-- MAGIC             else:
-- MAGIC                 cur.append(ch)
-- MAGIC     s = "".join(cur).strip()
-- MAGIC     if s:
-- MAGIC         out.append(s)
-- MAGIC     return out
-- MAGIC
-- MAGIC def run_script(nom):
-- MAGIC     chemin = "/Volumes/camping/bronze/depot/scripts/" + nom
-- MAGIC     instructions = split_sql(open(chemin, encoding="utf-8").read())
-- MAGIC     erreurs = 0
-- MAGIC     for i, s in enumerate(instructions, 1):
-- MAGIC         try:
-- MAGIC             spark.sql(s)
-- MAGIC         except Exception as e:
-- MAGIC             erreurs += 1
-- MAGIC             print(f"ERREUR instruction {i} : {s[:80]!r} -> {str(e)[:250]}")
-- MAGIC     print(f"{nom} : {len(instructions)} instructions, {erreurs} erreur(s)")

-- COMMAND ----------

-- MAGIC %python
-- MAGIC run_script("01_creer_tables_hackolade.sql")

-- COMMAND ----------

SHOW TABLES IN camping.silver;

-- COMMAND ----------

SHOW TABLES IN camping.gold;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC run_script("02_charger_silver_gold.sql")

-- COMMAND ----------

SELECT 'sejour' AS t, count(*) AS n, 15 AS attendu FROM camping.silver.sejour
UNION ALL SELECT 'sejour_rejete', count(*), 1 FROM camping.silver.sejour_rejete
UNION ALL SELECT 'reservation_ota', count(*), 3 FROM camping.silver.reservation_ota
UNION ALL SELECT 'nuitee', count(*), 62 FROM camping.silver.nuitee
UNION ALL SELECT 'consentement', count(*), 24 FROM camping.silver.consentement
UNION ALL SELECT 'emplacement_historique', count(*), 12 FROM camping.silver.emplacement_historique
UNION ALL SELECT 'conso_quart_heure', count(*), 132 FROM camping.silver.conso_quart_heure
UNION ALL SELECT 'dp_occupation_yield', count(*), 39 FROM camping.gold.dp_occupation_yield
UNION ALL SELECT 'dp_conso_anomalies', count(*), 36 FROM camping.gold.dp_conso_anomalies
UNION ALL SELECT 'dp_taxe_sejour', count(*), 2 FROM camping.gold.dp_taxe_sejour
UNION ALL SELECT 'dp_profil_clientele', count(*), 6 FROM camping.gold.dp_profil_clientele;

-- COMMAND ----------

SELECT categorie_code, emplacements_occupes, emplacements_disponibles, taux_occupation
FROM camping.gold.dp_occupation_yield WHERE date_nuit = '2025-08-31' ORDER BY categorie_code;

-- COMMAND ----------

SELECT * FROM camping.gold.dp_taxe_sejour ORDER BY mois;

-- COMMAND ----------

SELECT emplacement_id, heure, litres, fuite_probable, emplacement_occupe
FROM camping.gold.dp_conso_anomalies WHERE fuite_probable ORDER BY heure;

-- COMMAND ----------

SELECT count(*) AS reservations, count(sejour_id) AS rapprochees FROM camping.silver.reservation_ota;

-- COMMAND ----------

SELECT count(*) AS lignes, sum(nb_sejours) AS sejours, sum(nb_clients) AS clients, sum(nb_nuitees) AS nuitees, sum(chiffre_affaires) AS ca
FROM camping.gold.dp_profil_clientele;

-- COMMAND ----------

SELECT sum(chiffre_affaires) AS ca_total FROM camping.gold.dp_occupation_yield;

-- COMMAND ----------

   SELECT table_name, column_name, tag_name FROM camping.information_schema.column_tags WHERE schema_name = 'silver';

-- COMMAND ----------

   SELECT table_name, column_name, mask_name FROM camping.information_schema.column_masks;

-- COMMAND ----------

   CREATE OR REPLACE TABLE camping.gold.dp_occupation_yield_sans_commentaires AS
   SELECT * FROM camping.gold.dp_occupation_yield;