-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Notebook 04 : purger les données personnelles échues
-- MAGIC Efface les données personnelles arrivées au bout de leur durée de conservation, **dans le silver et dans le bronze**.
-- MAGIC
-- MAGIC **Règles** (finalités du sujet) :
-- MAGIC - `CONTRAT` : l’identité du client est effacée 36 mois après sa dernière activité ;
-- MAGIC - `POLICE` : le numéro de pièce d’identité est effacé 6 mois après le départ.
-- MAGIC
-- MAGIC **À lancer** : chaque nuit, **après** le notebook 02 et **avant** le notebook 03, vers 5 h 15.
-- MAGIC
-- MAGIC **À savoir**
-- MAGIC - La date de référence est fixée à `2025-09-06` pour le jeu d’exemple : en production, la remplacer par `current_date()`.
-- MAGIC - Le client pseudonymisé (`silver.client`) et ses séjours restent : sans l’identité, ils ne permettent plus de reconnaître la personne, et la comptabilité conserve ses pièces.
-- MAGIC - Un `DELETE` ne suffit pas sur une table Delta : les anciennes versions restent lisibles dans l’historique. `VACUUM` les supprime après le délai de conservation par défaut (7 jours).
-- MAGIC - Le fichier du dépôt (`clients/clients_pms.csv`) contient encore les lignes effacées : au prochain chargement du bronze, elles seraient recopiées. En production, le PMS cesse de les envoyer ; pour la démonstration, retirer ces lignes du fichier.
-- MAGIC - Si la modification échoue à cause du masque de colonne, retirez-le le temps de la purge (`ALTER TABLE ... ALTER COLUMN email DROP MASK`), puis reposez-le avec le notebook 01.

-- COMMAND ----------

USE CATALOG camping;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Préparer
-- MAGIC Un journal des purges garde la preuve de l’effacement (nombre de fiches, date), sans aucune donnée identifiante, puis la date de référence.

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS silver.purge_journal (
  purge_le TIMESTAMP NOT NULL COMMENT 'Date et heure de la purge',
  finalite STRING NOT NULL COMMENT 'CONTRAT ou POLICE',
  nb_lignes BIGINT NOT NULL COMMENT 'Nombre de fiches concernées',
  date_reference DATE NOT NULL COMMENT 'Date de référence de la purge'
) COMMENT 'Journal des purges : preuve de l’effacement, sans aucune donnée identifiante'

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW params AS SELECT DATE '2025-09-06' AS date_reference

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Repérer les fiches échues

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW echus_contrat AS
SELECT i.client_ref FROM silver.client_identite i CROSS JOIN params p
WHERE add_months(i.date_derniere_activite, 36) < p.date_reference

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW echus_police AS
SELECT i.client_ref FROM silver.client_identite i
JOIN (SELECT client_ref, max(date_depart) AS dernier_depart FROM silver.sejour GROUP BY client_ref) s ON s.client_ref = i.client_ref
CROSS JOIN params p
WHERE i.piece_identite_num IS NOT NULL AND add_months(s.dernier_depart, 6) < p.date_reference

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Nombre de fiches échues par finalité :

-- COMMAND ----------

SELECT 'CONTRAT' AS finalite, count(*) AS fiches_echues FROM echus_contrat
UNION ALL
SELECT 'POLICE', count(*) FROM echus_police

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Écrire le journal puis effacer

-- COMMAND ----------

INSERT INTO silver.purge_journal
SELECT current_timestamp(), 'CONTRAT', count(*), (SELECT date_reference FROM params) FROM echus_contrat

-- COMMAND ----------

INSERT INTO silver.purge_journal
SELECT current_timestamp(), 'POLICE', count(*), (SELECT date_reference FROM params) FROM echus_police

-- COMMAND ----------

-- bronze : pièces d’identité échues (règle POLICE, 6 mois après le départ)
UPDATE bronze.clients_pms SET piece_identite_num = NULL
WHERE client_ref IN (SELECT client_ref FROM echus_police)

-- COMMAND ----------

-- bronze : fiches échues (règle CONTRAT, 36 mois après la dernière activité)
DELETE FROM bronze.clients_pms
WHERE client_ref IN (SELECT b.client_ref FROM bronze.clients_pms b CROSS JOIN params p
                     WHERE add_months(CAST(b.date_derniere_activite AS DATE), 36) < p.date_reference)

-- COMMAND ----------

-- silver : pièces d’identité échues
UPDATE silver.client_identite SET piece_identite_num = NULL
WHERE client_ref IN (SELECT client_ref FROM echus_police)

-- COMMAND ----------

-- silver : identités échues (le client pseudonymisé et ses séjours restent : ils ne permettent plus d’identifier la personne)
DELETE FROM silver.client_identite
WHERE client_ref IN (SELECT client_ref FROM echus_contrat)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Contrôler l’effacement
-- MAGIC Au 6 septembre 2025, `C1A0` et `C6B2` (dernière activité en 2022) ne doivent plus exister : résultat attendu **0 et 0**.

-- COMMAND ----------

SELECT 'silver.client_identite' AS table_controlee, count(*) AS clients_echus_restants FROM silver.client_identite WHERE client_ref IN ('C1A0', 'C6B2')
UNION ALL
SELECT 'bronze.clients_pms', count(*) FROM bronze.clients_pms WHERE client_ref IN ('C1A0', 'C6B2')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5. L’historique Delta
-- MAGIC `DESCRIBE HISTORY` montre les opérations ; `VACUUM` supprime les anciennes versions des fichiers.

-- COMMAND ----------

DESCRIBE HISTORY silver.client_identite

-- COMMAND ----------

VACUUM silver.client_identite

-- COMMAND ----------

VACUUM bronze.clients_pms