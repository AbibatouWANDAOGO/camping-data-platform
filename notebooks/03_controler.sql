-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Notebook 03 : contrôler les résultats

-- COMMAND ----------

USE CATALOG camping;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Dernier choix de consentement STATS de chaque client (sert au contrôle R13) :

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW dernier_choix_stats AS
SELECT client_ref, statut
FROM (SELECT client_ref, statut,
             row_number() OVER (PARTITION BY client_ref ORDER BY horodatage DESC) AS rn
      FROM silver.consentement WHERE finalite = 'STATS')
WHERE rn = 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Les valeurs contrôlées :

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW valeurs AS
SELECT 'règle' AS categorie, 'R1 Séjours dont le départ n’est pas après l’arrivée' AS controle, CAST((SELECT count(*) FROM silver.sejour WHERE date_depart <= date_arrivee) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R2 Écart entre le nombre de nuitées et la durée des séjours' AS controle, CAST((SELECT abs(count(*) - (SELECT sum(datediff(date_depart, date_arrivee)) FROM silver.sejour)) FROM silver.nuitee) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R3 Taux d’occupation hors de 0 à 1' AS controle, CAST((SELECT count(*) FROM gold.dp_occupation_yield WHERE taux_occupation NOT BETWEEN 0 AND 1) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R4 Emplacements occupés supérieurs aux disponibles' AS controle, CAST((SELECT count(*) FROM gold.dp_occupation_yield WHERE emplacements_occupes > emplacements_disponibles) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R5 Doublons de grain dans dp_occupation_yield' AS controle, CAST((SELECT count(*) FROM (SELECT date_nuit, camping, categorie_code FROM gold.dp_occupation_yield GROUP BY date_nuit, camping, categorie_code HAVING count(*) > 1)) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R6 Doublons de grain dans dp_taxe_sejour' AS controle, CAST((SELECT count(*) FROM (SELECT commune, mois FROM gold.dp_taxe_sejour GROUP BY commune, mois HAVING count(*) > 1)) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R7 Doublons de grain dans dp_conso_anomalies' AS controle, CAST((SELECT count(*) FROM (SELECT emplacement_id, heure FROM gold.dp_conso_anomalies GROUP BY emplacement_id, heure HAVING count(*) > 1)) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R8 Doublons de grain dans dp_profil_clientele' AS controle, CAST((SELECT count(*) FROM (SELECT mois, tranche_age, type_groupe, pays FROM gold.dp_profil_clientele GROUP BY mois, tranche_age, type_groupe, pays HAVING count(*) > 1)) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R9 Montants de taxe différents de nuitées × tarif' AS controle, CAST((SELECT count(*) FROM gold.dp_taxe_sejour WHERE abs(montant_a_reverser - nuitees_adultes * tarif_adulte_nuit) > 0.005) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R10 Écart (en euros) entre le chiffre d’affaires du gold et les séjours, arrondis compris' AS controle, CAST((SELECT abs((SELECT sum(chiffre_affaires) FROM gold.dp_occupation_yield) - (SELECT sum(montant_ttc) FROM silver.sejour))) AS DOUBLE) AS observe, CAST(0.10 AS DOUBLE) AS attendu, '<=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R11 Réservations OTA sans séjour PMS rapproché' AS controle, CAST((SELECT count(*) FROM silver.reservation_ota WHERE sejour_id IS NULL) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R12 Fuites probables en dehors de 0 h à 5 h' AS controle, CAST((SELECT count(*) FROM gold.dp_conso_anomalies WHERE fuite_probable AND hour(heure) NOT BETWEEN 0 AND 5) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'règle' AS categorie, 'R13 Séjours du profil de clientèle moins séjours des clients consentants' AS controle, CAST((SELECT abs((SELECT coalesce(sum(nb_sejours), 0) FROM gold.dp_profil_clientele) - (SELECT count(*) FROM silver.sejour s JOIN dernier_choix_stats d ON d.client_ref = s.client_ref WHERE d.statut = 'ACCORDE'))) AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'sécurité' AS categorie, 'SEC1 Masques posés sur client_identite (e-mail et téléphone)' AS controle, CAST((SELECT count(*) FROM camping.information_schema.column_masks WHERE table_name = 'client_identite') AS DOUBLE) AS observe, CAST(2 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'sécurité' AS categorie, 'SEC2 Colonnes taguées dcp dans le gold' AS controle, CAST((SELECT count(*) FROM camping.information_schema.column_tags WHERE schema_name = 'gold' AND tag_name = 'dcp') AS DOUBLE) AS observe, CAST(0 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V1 Séjours valides' AS controle, CAST((SELECT count(*) FROM silver.sejour) AS DOUBLE) AS observe, CAST(15 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V2 Séjours rejetés' AS controle, CAST((SELECT count(*) FROM silver.sejour_rejete) AS DOUBLE) AS observe, CAST(1 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V3 Nuitées' AS controle, CAST((SELECT count(*) FROM silver.nuitee) AS DOUBLE) AS observe, CAST(62 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V4 Lignes de dp_occupation_yield' AS controle, CAST((SELECT count(*) FROM gold.dp_occupation_yield) AS DOUBLE) AS observe, CAST(39 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V5 Taxe de séjour d’août 2025' AS controle, CAST((SELECT coalesce(sum(montant_a_reverser), 0) FROM gold.dp_taxe_sejour WHERE mois = DATE '2025-08-01') AS DOUBLE) AS observe, CAST(55.20 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V6 Heures en fuite probable' AS controle, CAST((SELECT count(*) FROM gold.dp_conso_anomalies WHERE fuite_probable) AS DOUBLE) AS observe, CAST(6 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V7 Réservations OTA rapprochées' AS controle, CAST((SELECT count(*) FROM silver.reservation_ota WHERE sejour_id IS NOT NULL) AS DOUBLE) AS observe, CAST(3 AS DOUBLE) AS attendu, '=' AS regle
UNION ALL
SELECT 'jeu d’exemple' AS categorie, 'V8 Chiffre d’affaires du profil de clientèle' AS controle, CAST((SELECT coalesce(sum(chiffre_affaires), 0) FROM gold.dp_profil_clientele) AS DOUBLE) AS observe, CAST(2485.00 AS DOUBLE) AS attendu, '=' AS regle

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Les verdicts :

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW controles AS
SELECT categorie, controle, observe, attendu,
       CASE WHEN regle = '=' THEN abs(observe - attendu) < 0.0001 ELSE observe <= attendu END AS ok
FROM valeurs

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Liste des contrôles
-- MAGIC Toutes les lignes doivent avoir `ok = true`.

-- COMMAND ----------

SELECT categorie, controle, observe, attendu, ok FROM controles ORDER BY categorie, controle

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Arrêt du job en cas d’échec
-- MAGIC Cette cellule échoue (et fait échouer le job) si un contrôle `règle` ou `sécurité` n’est pas `ok`. Si les contrôles `SEC1` ou `SEC2` échouent alors que le masque et les étiquettes sont posés, vérifiez le nom des colonnes de `information_schema.column_masks` et `column_tags`.

-- COMMAND ----------

SELECT assert_true((SELECT count(*) FROM controles WHERE categorie IN ('règle', 'sécurité') AND NOT ok) = 0, 'Contrôle en échec : voir la liste des contrôles ci-dessus')