-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Notebook 02 : charger silver et gold depuis le bronze
-- MAGIC Chaque nuit, il remplit les tables silver (typage, séjours rejetés, rapprochement OTA / PMS, nuitées, consommation) puis les quatre data products du gold.
-- MAGIC
-- MAGIC **À lancer** : chaque nuit, après le chargement du bronze. Les tables sont remplacées (`INSERT OVERWRITE`), donc le notebook peut être relancé sans doublons.
-- MAGIC
-- MAGIC **Statut** : déjà exécuté (script `02_charger_silver_gold.sql`).

-- COMMAND ----------

-- =====================================================================
-- 02_charger_silver_gold  (Databricks SQL, niveau avancé)
-- Bronze -> silver -> gold. Chaque table bronze est en texte (voir annexe G).
-- Exécuté sur Databricks Free Edition ; les valeurs obtenues ont été comparées à des valeurs
-- calculées à part sur les fichiers CSV (contrôles du notebook 03).
-- Ordre des dépendances : référentiels, clients, séjours, nuitées, data products.
-- =====================================================================
USE CATALOG camping;

-- COMMAND ----------

-- ---- 1. Référentiels -------------------------------------------------
INSERT OVERWRITE silver.camping
SELECT camping, commune, CAST(classement_etoiles AS INT), CAST(tarif_taxe_adulte_nuit AS DECIMAL(5,2))
FROM bronze.campings;

-- COMMAND ----------

INSERT OVERWRITE silver.categorie VALUES
  ('NU', 'Emplacement nu'), ('MH', 'Mobil-home'), ('PR', 'Premium');

-- COMMAND ----------

INSERT OVERWRITE silver.canal
SELECT DISTINCT canal AS canal_code, canal AS libelle
FROM (SELECT canal FROM bronze.sejours_pms UNION SELECT canal FROM bronze.export_ota);

-- COMMAND ----------

INSERT OVERWRITE silver.emplacement
SELECT emplacement_id, camping, categorie AS categorie_code, CAST(NULL AS INT) AS surface_m2 FROM bronze.emplacements;

-- COMMAND ----------

-- historique des catégories : une version initiale par emplacement, valable depuis le début de l'historique
-- (convention : 2000-01-01). Quand la catégorie change, on ferme la version en cours et on en ouvre une nouvelle.
INSERT OVERWRITE silver.emplacement_historique
SELECT emplacement_id, categorie AS categorie_code, DATE '2000-01-01' AS date_debut_validite, CAST(NULL AS DATE) AS date_fin_validite
FROM bronze.emplacements;

-- COMMAND ----------

INSERT OVERWRITE silver.finalite_traitement
SELECT finalite, libelle, base_legale, CAST(duree_conservation_mois AS INT), point_de_depart
FROM bronze.finalites;

-- COMMAND ----------

-- ---- 2. Clients : pseudonymisé d'un côté, identité de l'autre ---------
INSERT OVERWRITE silver.client
SELECT client_ref, year(CAST(date_naissance AS DATE)), pays FROM bronze.clients_pms;

-- COMMAND ----------

-- minimisation : situation_familiale et nom_conjoint n'entrent pas en silver
INSERT OVERWRITE silver.client_identite
SELECT client_ref, nom, prenom, CAST(date_naissance AS DATE), email, telephone, adresse, code_postal, ville,
       nationalite, piece_identite_num, CAST(date_creation AS DATE), CAST(date_derniere_activite AS DATE)
FROM bronze.clients_pms;

-- COMMAND ----------

-- un choix sans date ne peut pas servir de preuve : il reste en bronze, il n'entre pas en silver
INSERT OVERWRITE silver.consentement
SELECT client_ref, finalite, CAST(horodatage AS TIMESTAMP), statut, canal, version_texte
FROM bronze.consentements
WHERE nullif(trim(horodatage), '') IS NOT NULL;

-- COMMAND ----------

-- ---- 3. Séjours valides et séjours rejetés ----------------------------
INSERT OVERWRITE silver.sejour
SELECT sejour_id, client_ref, emplacement_id, canal, CAST(date_arrivee AS DATE), CAST(date_depart AS DATE),
       CAST(nb_adultes AS INT), CAST(nb_mineurs AS INT), CAST(montant_ttc AS DECIMAL(10,2))
FROM bronze.sejours_pms
WHERE CAST(date_depart AS DATE) > CAST(date_arrivee AS DATE);

-- COMMAND ----------

INSERT OVERWRITE silver.sejour_rejete
SELECT sejour_id, client_ref, emplacement_id, canal, CAST(date_arrivee AS DATE), CAST(date_depart AS DATE),
       CAST(nb_adultes AS INT), CAST(nb_mineurs AS INT), CAST(montant_ttc AS DECIMAL(10,2)),
       'date_depart non posterieure a date_arrivee' AS motif, current_timestamp() AS rejete_le
FROM bronze.sejours_pms
WHERE CAST(date_depart AS DATE) <= CAST(date_arrivee AS DATE);

-- COMMAND ----------

-- ---- 4. Réservations OTA rapprochées du PMS (règle de doublon) --------
-- même emplacement, mêmes dates, même canal : c'est la même réservation
INSERT OVERWRITE silver.reservation_ota
SELECT o.ota_ref, o.canal, o.emplacement_id, CAST(o.date_arrivee AS DATE), CAST(o.date_depart AS DATE),
       CAST(o.nb_adultes AS INT), CAST(o.nb_mineurs AS INT), CAST(o.montant_ttc AS DECIMAL(10,2)), s.sejour_id
FROM bronze.export_ota o
LEFT JOIN silver.sejour s
  ON  s.emplacement_id = o.emplacement_id
  AND s.date_arrivee   = CAST(o.date_arrivee AS DATE)
  AND s.date_depart    = CAST(o.date_depart AS DATE)
  AND s.canal_code     = o.canal;

-- COMMAND ----------

-- ---- 5. Relevés des compteurs -----------------------------------------
INSERT OVERWRITE silver.releve_compteur
SELECT emplacement_id, CAST(horodatage AS TIMESTAMP), CAST(kwh_cumul AS DECIMAL(12,2)), CAST(litres_cumul AS DECIMAL(14,2))
FROM bronze.releves_compteurs;

-- COMMAND ----------

-- ---- 5 bis. Consommation de chaque quart d'heure ---------------------
-- consommation = index - index précédent ; si l'index baisse, le compteur a redémarré : c'est la nouvelle valeur
INSERT OVERWRITE silver.conso_quart_heure
WITH r AS (
  SELECT emplacement_id, horodatage, kwh_cumul, litres_cumul,
         lag(kwh_cumul)    OVER (PARTITION BY emplacement_id ORDER BY horodatage) AS kwh_prec,
         lag(litres_cumul) OVER (PARTITION BY emplacement_id ORDER BY horodatage) AS litres_prec
  FROM silver.releve_compteur)
SELECT emplacement_id, horodatage,
       CAST(CASE WHEN kwh_prec IS NULL THEN NULL WHEN kwh_cumul < kwh_prec THEN kwh_cumul ELSE kwh_cumul - kwh_prec END AS DECIMAL(10,2)) AS kwh,
       CAST(CASE WHEN litres_prec IS NULL THEN NULL WHEN litres_cumul < litres_prec THEN litres_cumul ELSE litres_cumul - litres_prec END AS DECIMAL(12,2)) AS litres,
       coalesce(kwh_cumul < kwh_prec OR litres_cumul < litres_prec, false) AS remise_a_zero
FROM r;

-- COMMAND ----------

-- ---- 6. Nuitées : une ligne par séjour et par nuit ---------------------
-- sequence() liste les nuits, explode() en fait une ligne par nuit ; la nuit du départ est exclue
INSERT OVERWRITE silver.nuitee
SELECT s.sejour_id, n.date_nuit, s.emplacement_id, s.nb_adultes, s.nb_mineurs,
       CAST(s.montant_ttc / datediff(s.date_depart, s.date_arrivee) AS DECIMAL(12,4)) AS montant_nuit
FROM silver.sejour s
LATERAL VIEW explode(sequence(s.date_arrivee, date_sub(s.date_depart, 1), INTERVAL 1 DAY)) n AS date_nuit;

-- COMMAND ----------

-- ---- 7. GOLD : dp_occupation_yield ------------------------------------
-- la catégorie et le nombre d'emplacements disponibles sont ceux de la version valable la nuit concernée
INSERT OVERWRITE gold.dp_occupation_yield
WITH nuits AS (SELECT DISTINCT date_nuit FROM silver.nuitee),
version AS (
  SELECT nu.date_nuit, e.emplacement_id, e.camping, h.categorie_code
  FROM nuits nu
  JOIN silver.emplacement_historique h
    ON nu.date_nuit >= h.date_debut_validite AND (h.date_fin_validite IS NULL OR nu.date_nuit <= h.date_fin_validite)
  JOIN silver.emplacement e ON e.emplacement_id = h.emplacement_id),
dispo AS (SELECT date_nuit, camping, categorie_code, count(*) AS n FROM version GROUP BY date_nuit, camping, categorie_code),
occ AS (
  SELECT n.date_nuit, v.camping, v.categorie_code,
         count(DISTINCT n.emplacement_id) AS occupes,
         sum(n.montant_nuit) AS ca,
         count(CASE WHEN s.canal_code = 'DIRECT' THEN 1 END) AS directes
  FROM silver.nuitee n
  JOIN version v ON v.date_nuit = n.date_nuit AND v.emplacement_id = n.emplacement_id
  JOIN silver.sejour s ON s.sejour_id = n.sejour_id
  GROUP BY n.date_nuit, v.camping, v.categorie_code)
SELECT d.date_nuit, d.camping, d.categorie_code,
       CAST(d.n AS INT), CAST(coalesce(o.occupes, 0) AS INT),
       CAST(coalesce(o.occupes, 0) / d.n AS DECIMAL(5,4)),
       CAST(coalesce(o.ca, 0) AS DECIMAL(12,2)),
       CAST(coalesce(o.directes, 0) AS INT),
       CAST(try_divide(coalesce(o.directes, 0), o.occupes) AS DECIMAL(5,4))
FROM dispo d
LEFT JOIN occ o ON o.date_nuit = d.date_nuit AND o.camping = d.camping AND o.categorie_code = d.categorie_code;

-- COMMAND ----------

-- ---- 8. GOLD : dp_taxe_sejour -----------------------------------------
INSERT OVERWRITE gold.dp_taxe_sejour
SELECT c.commune, trunc(n.date_nuit, 'MM') AS mois,
       CAST(sum(n.nb_adultes) AS INT) AS nuitees_adultes, c.tarif_taxe_adulte_nuit,
       CAST(sum(n.nb_adultes) * c.tarif_taxe_adulte_nuit AS DECIMAL(12,2)) AS montant_a_reverser
FROM silver.nuitee n
JOIN silver.emplacement e ON e.emplacement_id = n.emplacement_id
JOIN silver.camping c ON c.camping = e.camping
GROUP BY c.commune, trunc(n.date_nuit, 'MM'), c.tarif_taxe_adulte_nuit;

-- COMMAND ----------

-- ---- 9. GOLD : dp_conso_anomalies -------------------------------------
-- somme par heure des quarts d'heure ; fuite probable : six heures sur six à 40 L ou plus entre 0 h et 6 h
INSERT OVERWRITE gold.dp_conso_anomalies
WITH h AS (
  SELECT emplacement_id, date_trunc('HOUR', horodatage) AS heure,
         sum(kwh) AS kwh, sum(litres) AS litres, max(remise_a_zero) AS remise_a_zero
  FROM silver.conso_quart_heure GROUP BY emplacement_id, date_trunc('HOUR', horodatage)),
f AS (SELECT *, to_date(heure - INTERVAL 12 HOURS) AS date_nuit, hour(heure) AS hh FROM h),
fuite AS (
  SELECT emplacement_id, date_nuit,
         count(CASE WHEN hh BETWEEN 0 AND 5 AND litres >= 40 THEN 1 END) = 6 AS nuit_fuite
  FROM f GROUP BY emplacement_id, date_nuit),
occupe AS (SELECT DISTINCT emplacement_id, date_nuit FROM silver.nuitee)
SELECT f.emplacement_id, f.heure, CAST(f.kwh AS DECIMAL(10,2)), CAST(f.litres AS DECIMAL(12,2)), f.remise_a_zero,
       coalesce(fu.nuit_fuite, false) AND f.hh BETWEEN 0 AND 5 AS fuite_probable,
       o.emplacement_id IS NOT NULL AS emplacement_occupe
FROM f
LEFT JOIN fuite fu ON fu.emplacement_id = f.emplacement_id AND fu.date_nuit = f.date_nuit
LEFT JOIN occupe o ON o.emplacement_id = f.emplacement_id AND o.date_nuit = f.date_nuit;

-- COMMAND ----------

-- ---- 10. GOLD : dp_profil_clientele (clients consentants seulement) ----
-- dernier choix STATS = ACCORDE ; un client sans choix daté, ou dont le dernier choix est REFUSE ou RETIRE, est exclu
INSERT OVERWRITE gold.dp_profil_clientele
WITH dernier AS (
  SELECT client_ref, statut,
         row_number() OVER (PARTITION BY client_ref ORDER BY horodatage DESC) AS rn
  FROM silver.consentement WHERE finalite = 'STATS'),
ok AS (SELECT client_ref FROM dernier WHERE rn = 1 AND statut = 'ACCORDE'),
base AS (
  SELECT s.sejour_id, s.client_ref, trunc(s.date_arrivee, 'MM') AS mois, cl.pays_residence AS pays,
         year(s.date_arrivee) - cl.annee_naissance AS age,
         CASE WHEN s.nb_mineurs > 0 THEN 'famille' WHEN s.nb_adultes = 1 THEN 'solo' ELSE 'adultes' END AS type_groupe,
         datediff(s.date_depart, s.date_arrivee) AS nuitees, s.montant_ttc
  FROM silver.sejour s
  JOIN ok ON ok.client_ref = s.client_ref
  JOIN silver.client cl ON cl.client_ref = s.client_ref)
SELECT mois,
       CASE WHEN age < 25 THEN '18-24' WHEN age < 35 THEN '25-34' WHEN age < 45 THEN '35-44'
            WHEN age < 55 THEN '45-54' WHEN age < 65 THEN '55-64' ELSE '65+' END AS tranche_age,
       type_groupe, pays,
       CAST(count(DISTINCT client_ref) AS INT), CAST(count(*) AS INT), CAST(sum(nuitees) AS INT),
       CAST(sum(montant_ttc) AS DECIMAL(12,2))
FROM base
GROUP BY mois, 2, type_groupe, pays;
