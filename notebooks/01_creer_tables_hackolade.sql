-- =====================================================================
-- 01_creer_tables_hackolade  (Databricks SQL)
-- Contenu attendu du Forward-Engineering du modèle Camping_databricks :
-- schemas silver et gold, types Databricks, contraintes CHECK.
-- Les clés primaires composées sont ajoutées à la main (plugin Hackolade 0.2.55).
-- Exécuté sur Databricks Free Edition (lancé par le notebook 00, qui le lit dans le volume de dépôt).
-- =====================================================================
USE CATALOG camping;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

-- ------------------------------ SILVER : référentiels ----------------
CREATE TABLE IF NOT EXISTS silver.camping (
  camping                STRING        NOT NULL COMMENT 'Nom du camping (clé)',
  commune                STRING        NOT NULL COMMENT 'Commune de rattachement : sert à reverser la taxe de séjour',
  classement_etoiles     INT                    COMMENT 'Classement en étoiles',
  tarif_taxe_adulte_nuit DECIMAL(5,2)           COMMENT 'Tarif de la taxe de séjour par adulte et par nuit, en euros',
  CONSTRAINT pk_camping PRIMARY KEY (camping)
) COMMENT 'Les campings du groupe';

CREATE TABLE IF NOT EXISTS silver.categorie (
  categorie_code STRING NOT NULL COMMENT 'NU nu, MH mobil-home, PR premium',
  libelle        STRING NOT NULL COMMENT 'Libellé de la catégorie',
  CONSTRAINT pk_categorie PRIMARY KEY (categorie_code)
) COMMENT 'Catégories d''emplacement';

CREATE TABLE IF NOT EXISTS silver.canal (
  canal_code STRING NOT NULL COMMENT 'DIRECT, BOOKING, CAMPINGS...',
  libelle    STRING          COMMENT 'Libellé du canal de vente',
  CONSTRAINT pk_canal PRIMARY KEY (canal_code)
) COMMENT 'Canaux de vente';

CREATE TABLE IF NOT EXISTS silver.emplacement (
  emplacement_id STRING NOT NULL COMMENT 'Identifiant de la parcelle louée',
  camping        STRING NOT NULL COMMENT 'Camping de l''emplacement',
  categorie_code STRING NOT NULL COMMENT 'Catégorie actuelle de l''emplacement',
  surface_m2     INT              COMMENT 'Surface de l''emplacement en m2 (PMS ; absente du jeu d''exemple)',
  CONSTRAINT pk_emplacement PRIMARY KEY (emplacement_id),
  CONSTRAINT fk_emplacement_camping   FOREIGN KEY (camping)        REFERENCES silver.camping (camping),
  CONSTRAINT fk_emplacement_categorie FOREIGN KEY (categorie_code) REFERENCES silver.categorie (categorie_code)
) COMMENT 'Emplacements (parcelles) des campings';

-- ------------------------------ SILVER : clients et consentement -----
CREATE TABLE IF NOT EXISTS silver.client (
  client_ref      STRING NOT NULL COMMENT 'Référence pseudonymisée du client (clé du PMS)',
  annee_naissance INT             COMMENT 'Année de naissance seulement (statistiques)',
  pays_residence  STRING          COMMENT 'Pays de résidence',
  CONSTRAINT pk_client PRIMARY KEY (client_ref)
) COMMENT 'Client pseudonymisé : aucune donnée identifiante';

CREATE TABLE IF NOT EXISTS silver.client_identite (
  client_ref             STRING NOT NULL COMMENT '[DCP] Référence du client',
  nom                    STRING          COMMENT '[DCP] Nom',
  prenom                 STRING          COMMENT '[DCP] Prénom',
  date_naissance         DATE            COMMENT '[DCP] Date de naissance complète',
  email                  STRING          COMMENT '[DCP] E-mail (masqué)',
  telephone              STRING          COMMENT '[DCP] Téléphone (masqué)',
  adresse                STRING          COMMENT '[DCP] Adresse postale (facturation)',
  code_postal            STRING          COMMENT '[DCP] Code postal',
  ville                  STRING          COMMENT '[DCP] Ville',
  nationalite            STRING          COMMENT '[DCP] Nationalité (fiche de police)',
  piece_identite_num     STRING          COMMENT '[DCP] Numéro de pièce d''identité, clients étrangers, 6 mois après le départ',
  date_creation          DATE            COMMENT 'Création de la fiche',
  date_derniere_activite DATE            COMMENT 'Point de départ de la durée de conservation CONTRAT',
  CONSTRAINT pk_client_identite PRIMARY KEY (client_ref),
  CONSTRAINT fk_identite_client FOREIGN KEY (client_ref) REFERENCES silver.client (client_ref)
) COMMENT 'Identité du client, à part et protégée';

CREATE TABLE IF NOT EXISTS silver.finalite_traitement (
  finalite                STRING NOT NULL COMMENT 'CONTRAT, COMPTA, POLICE, STATS, MARKETING',
  libelle                 STRING          COMMENT 'Pour quoi faire',
  base_legale             STRING          COMMENT 'Base légale à vérifier (RGPD, article 6)',
  duree_conservation_mois INT             COMMENT 'Durée de conservation en mois',
  point_de_depart         STRING          COMMENT 'Événement qui déclenche la durée',
  CONSTRAINT pk_finalite PRIMARY KEY (finalite)
) COMMENT 'Finalités, base légale et durée de conservation';

CREATE TABLE IF NOT EXISTS silver.consentement (
  client_ref    STRING    NOT NULL COMMENT 'Le client',
  finalite      STRING    NOT NULL COMMENT 'STATS ou MARKETING',
  horodatage    TIMESTAMP NOT NULL COMMENT 'Date et heure du choix (preuve)',
  statut        STRING    NOT NULL COMMENT 'ACCORDE, REFUSE ou RETIRE',
  canal         STRING             COMMENT 'WEB ou ACCUEIL',
  version_texte STRING             COMMENT 'Version du texte d''information montré au client',
  CONSTRAINT fk_consent_client   FOREIGN KEY (client_ref) REFERENCES silver.client (client_ref),
  CONSTRAINT fk_consent_finalite FOREIGN KEY (finalite)   REFERENCES silver.finalite_traitement (finalite)
) COMMENT 'Journal des consentements : un événement par ligne, le dernier choix compte';

-- ------------------------------ SILVER : séjours ---------------------
CREATE TABLE IF NOT EXISTS silver.sejour (
  sejour_id      STRING        NOT NULL COMMENT 'Identifiant du séjour dans le PMS',
  client_ref     STRING        NOT NULL COMMENT 'Client',
  emplacement_id STRING        NOT NULL COMMENT 'Emplacement',
  canal_code     STRING        NOT NULL COMMENT 'Canal de vente',
  date_arrivee   DATE          NOT NULL COMMENT 'Date d''arrivée',
  date_depart    DATE          NOT NULL COMMENT 'Date de départ : la nuit du départ n''est pas comptée',
  nb_adultes     INT           NOT NULL COMMENT 'Nombre d''adultes',
  nb_mineurs     INT           NOT NULL COMMENT 'Nombre de mineurs (exonérés de taxe)',
  montant_ttc    DECIMAL(10,2) NOT NULL COMMENT 'Montant TTC du séjour',
  CONSTRAINT pk_sejour PRIMARY KEY (sejour_id),
  CONSTRAINT fk_sejour_client      FOREIGN KEY (client_ref)     REFERENCES silver.client (client_ref),
  CONSTRAINT fk_sejour_emplacement FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id),
  CONSTRAINT fk_sejour_canal       FOREIGN KEY (canal_code)     REFERENCES silver.canal (canal_code)
) COMMENT 'Séjours valides : la contrainte dates_coherentes refuse les autres';

CREATE TABLE IF NOT EXISTS silver.sejour_rejete (
  sejour_id      STRING        NOT NULL COMMENT 'Identifiant du séjour écarté',
  client_ref     STRING,
  emplacement_id STRING,
  canal_code     STRING,
  date_arrivee   DATE,
  date_depart    DATE,
  nb_adultes     INT,
  nb_mineurs     INT,
  montant_ttc    DECIMAL(10,2),
  motif          STRING        NOT NULL COMMENT 'Pourquoi le séjour est rejeté',
  rejete_le      TIMESTAMP     NOT NULL COMMENT 'Date du rejet',
  CONSTRAINT pk_sejour_rejete PRIMARY KEY (sejour_id)
) COMMENT 'Séjours écartés, signalés et non corrigés en silence';

CREATE TABLE IF NOT EXISTS silver.reservation_ota (
  ota_ref        STRING        NOT NULL COMMENT 'Identifiant chez l''agence en ligne (différent de sejour_id)',
  canal_code     STRING        NOT NULL COMMENT 'BOOKING, CAMPINGS...',
  emplacement_id STRING        NOT NULL COMMENT 'Emplacement attribué',
  date_arrivee   DATE          NOT NULL,
  date_depart    DATE          NOT NULL,
  nb_adultes     INT,
  nb_mineurs     INT,
  montant_ttc    DECIMAL(10,2),
  sejour_id      STRING                 COMMENT 'Séjour PMS rapproché (doublon) ; NULL si aucun',
  CONSTRAINT pk_reservation_ota PRIMARY KEY (ota_ref),
  CONSTRAINT fk_ota_sejour FOREIGN KEY (sejour_id) REFERENCES silver.sejour (sejour_id)
) COMMENT 'Réservations OTA rapprochées du séjour PMS pour ne les compter qu''une fois';

CREATE TABLE IF NOT EXISTS silver.nuitee (
  sejour_id      STRING        NOT NULL COMMENT 'Séjour',
  date_nuit      DATE          NOT NULL COMMENT 'La nuit (la nuit du départ n''existe pas)',
  emplacement_id STRING        NOT NULL COMMENT 'Emplacement occupé cette nuit-là',
  nb_adultes     INT           NOT NULL COMMENT 'Adultes (base de la taxe)',
  nb_mineurs     INT           NOT NULL COMMENT 'Mineurs (exonérés)',
  montant_nuit   DECIMAL(12,4) NOT NULL COMMENT 'Montant du séjour réparti à parts égales sur ses nuits',
  CONSTRAINT fk_nuitee_sejour      FOREIGN KEY (sejour_id)      REFERENCES silver.sejour (sejour_id),
  CONSTRAINT fk_nuitee_emplacement FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id)
) COMMENT 'Une ligne par séjour et par nuit : table centrale';

CREATE TABLE IF NOT EXISTS silver.releve_compteur (
  emplacement_id STRING        NOT NULL COMMENT 'Emplacement équipé',
  horodatage     TIMESTAMP     NOT NULL COMMENT 'Date et heure du relevé (toutes les 15 minutes)',
  kwh_cumul      DECIMAL(12,2)          COMMENT 'Index électrique en kWh (repart à zéro après une coupure)',
  litres_cumul   DECIMAL(14,2)          COMMENT 'Index d''eau en litres',
  CONSTRAINT fk_releve_emplacement FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id)
) COMMENT 'Relevés des compteurs, typés';

CREATE TABLE IF NOT EXISTS silver.emplacement_historique (
  emplacement_id      STRING NOT NULL COMMENT 'Emplacement',
  categorie_code      STRING NOT NULL COMMENT 'Catégorie valable pendant cette version',
  date_debut_validite DATE   NOT NULL COMMENT 'Premier jour de validité de cette catégorie',
  date_fin_validite   DATE            COMMENT 'Dernier jour de validité ; vide pour la version en cours',
  CONSTRAINT fk_histo_emplacement FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id),
  CONSTRAINT fk_histo_categorie   FOREIGN KEY (categorie_code) REFERENCES silver.categorie (categorie_code)
) COMMENT 'Versions de catégorie d''un emplacement : les chiffres d''une saison passée gardent l''ancienne catégorie';

CREATE TABLE IF NOT EXISTS silver.conso_quart_heure (
  emplacement_id STRING        NOT NULL COMMENT 'Emplacement équipé',
  horodatage     TIMESTAMP     NOT NULL COMMENT 'Date et heure du relevé qui clôt le quart d''heure',
  kwh            DECIMAL(10,2)          COMMENT 'kWh consommés pendant le quart d''heure (nouvelle valeur après une remise à zéro)',
  litres         DECIMAL(12,2)          COMMENT 'Litres consommés pendant le quart d''heure',
  remise_a_zero  BOOLEAN       NOT NULL COMMENT 'Un compteur a redémarré pendant ce quart d''heure',
  CONSTRAINT fk_conso_emplacement FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id)
) COMMENT 'Consommation de chaque quart d''heure, calculée à partir des index des compteurs';

-- ------------------------------ GOLD : data products ------------------
CREATE TABLE IF NOT EXISTS gold.dp_occupation_yield (
  date_nuit               DATE          NOT NULL COMMENT 'La nuit (grain : nuit x camping x catégorie)',
  camping                 STRING        NOT NULL COMMENT 'Camping',
  categorie_code          STRING        NOT NULL COMMENT 'NU, MH ou PR',
  emplacements_disponibles INT          NOT NULL COMMENT 'Emplacements de cette catégorie dans ce camping',
  emplacements_occupes    INT           NOT NULL COMMENT 'Emplacements occupés cette nuit-là',
  taux_occupation         DECIMAL(5,4)  NOT NULL COMMENT 'occupés / disponibles. Le taux global se recalcule avec les sommes, jamais par moyenne des taux',
  chiffre_affaires        DECIMAL(12,2) NOT NULL COMMENT 'Chiffre d''affaires TTC de la nuit',
  nuitees_directes        INT           NOT NULL COMMENT 'Nuitées vendues en direct (pour pondérer la part du direct)',
  part_direct             DECIMAL(5,4)           COMMENT 'nuitées directes / nuitées occupées'
) COMMENT 'Data product commercial : occupation, CA et canaux, une ligne par nuit, camping et catégorie';

CREATE TABLE IF NOT EXISTS gold.dp_taxe_sejour (
  commune               STRING        NOT NULL COMMENT 'Commune à qui la taxe est reversée',
  mois                  DATE          NOT NULL COMMENT 'Premier jour du mois',
  nuitees_adultes       INT           NOT NULL COMMENT 'Nuitées d''adultes (mineurs exonérés)',
  tarif_adulte_nuit     DECIMAL(5,2)  NOT NULL COMMENT 'Tarif de la taxe par adulte et par nuit',
  montant_a_reverser    DECIMAL(12,2) NOT NULL COMMENT 'nuitees_adultes x tarif'
) COMMENT 'Data product comptable : base de la taxe de séjour par commune et par mois';

CREATE TABLE IF NOT EXISTS gold.dp_conso_anomalies (
  emplacement_id     STRING        NOT NULL COMMENT 'Emplacement',
  heure              TIMESTAMP     NOT NULL COMMENT 'Heure pleine (grain : emplacement x heure)',
  kwh                DECIMAL(10,2)          COMMENT 'kWh consommés pendant l''heure',
  litres             DECIMAL(12,2)          COMMENT 'Litres consommés pendant l''heure',
  remise_a_zero      BOOLEAN       NOT NULL COMMENT 'Un compteur a redémarré pendant l''heure',
  fuite_probable     BOOLEAN       NOT NULL COMMENT '40 L ou plus chaque heure entre 0 h et 6 h',
  emplacement_occupe BOOLEAN       NOT NULL COMMENT 'Emplacement occupé cette nuit-là ; fuite sur emplacement vide = urgence'
) COMMENT 'Data product technique : consommation par emplacement et par heure, alertes de fuite';

CREATE TABLE IF NOT EXISTS gold.dp_profil_clientele (
  mois          DATE          NOT NULL COMMENT 'Mois d''arrivée du séjour',
  tranche_age   STRING        NOT NULL COMMENT '18-24, 25-34, 35-44, 45-54, 55-64, 65+',
  type_groupe   STRING        NOT NULL COMMENT 'solo, adultes ou famille (avec mineurs)',
  pays          STRING        NOT NULL COMMENT 'Pays de résidence',
  nb_clients    INT           NOT NULL,
  nb_sejours    INT           NOT NULL,
  nb_nuitees    INT           NOT NULL,
  chiffre_affaires DECIMAL(12,2) NOT NULL,
  CONSTRAINT pk_profil PRIMARY KEY (mois, tranche_age, type_groupe, pays)
) COMMENT 'Data product marketing : seulement les clients dont le dernier choix STATS est un accord';

-- ------------------------------ Clés composées (à ajouter à la main) --
ALTER TABLE silver.nuitee           ADD CONSTRAINT pk_nuitee PRIMARY KEY (sejour_id, date_nuit);
ALTER TABLE silver.releve_compteur  ADD CONSTRAINT pk_releve PRIMARY KEY (emplacement_id, horodatage);
ALTER TABLE silver.consentement     ADD CONSTRAINT pk_consentement PRIMARY KEY (client_ref, finalite, horodatage);
ALTER TABLE silver.emplacement_historique ADD CONSTRAINT pk_histo PRIMARY KEY (emplacement_id, date_debut_validite);
ALTER TABLE silver.conso_quart_heure ADD CONSTRAINT pk_conso_qh PRIMARY KEY (emplacement_id, horodatage);
ALTER TABLE gold.dp_occupation_yield ADD CONSTRAINT pk_occupation PRIMARY KEY (date_nuit, camping, categorie_code);
ALTER TABLE gold.dp_taxe_sejour     ADD CONSTRAINT pk_taxe PRIMARY KEY (commune, mois);
ALTER TABLE gold.dp_conso_anomalies ADD CONSTRAINT pk_conso PRIMARY KEY (emplacement_id, heure);

-- ------------------------------ Contraintes CHECK (appliquées) -------
ALTER TABLE silver.sejour ADD CONSTRAINT dates_coherentes CHECK (date_depart > date_arrivee);
ALTER TABLE silver.sejour ADD CONSTRAINT effectifs_valides CHECK (nb_adultes >= 0 AND nb_mineurs >= 0);
ALTER TABLE silver.emplacement_historique ADD CONSTRAINT validite_coherente CHECK (date_fin_validite IS NULL OR date_fin_validite >= date_debut_validite);
ALTER TABLE gold.dp_occupation_yield ADD CONSTRAINT taux_valide CHECK (taux_occupation BETWEEN 0 AND 1);
ALTER TABLE gold.dp_occupation_yield ADD CONSTRAINT occupes_valides CHECK (emplacements_occupes <= emplacements_disponibles);

-- ------------------------------ Protection (étape R3) -----------------
CREATE OR REPLACE FUNCTION silver.masque_coordonnees(valeur STRING)
RETURNS STRING
RETURN CASE WHEN is_account_group_member('service_client') THEN valeur ELSE '*** masqué ***' END;

ALTER TABLE silver.client_identite ALTER COLUMN email     SET MASK silver.masque_coordonnees;
ALTER TABLE silver.client_identite ALTER COLUMN telephone SET MASK silver.masque_coordonnees;
ALTER TABLE silver.client_identite ALTER COLUMN nom                SET TAGS ('dcp' = 'identite');
ALTER TABLE silver.client_identite ALTER COLUMN prenom             SET TAGS ('dcp' = 'identite');
ALTER TABLE silver.client_identite ALTER COLUMN date_naissance     SET TAGS ('dcp' = 'identite');
ALTER TABLE silver.client_identite ALTER COLUMN email              SET TAGS ('dcp' = 'coordonnees');
ALTER TABLE silver.client_identite ALTER COLUMN telephone          SET TAGS ('dcp' = 'coordonnees');
ALTER TABLE silver.client_identite ALTER COLUMN adresse            SET TAGS ('dcp' = 'coordonnees');
ALTER TABLE silver.client_identite ALTER COLUMN nationalite        SET TAGS ('dcp' = 'identite');
ALTER TABLE silver.client_identite ALTER COLUMN piece_identite_num SET TAGS ('dcp' = 'identite');
ALTER TABLE silver.client_identite ALTER COLUMN code_postal        SET TAGS ('dcp' = 'coordonnees');
ALTER TABLE silver.client_identite ALTER COLUMN ville              SET TAGS ('dcp' = 'coordonnees');
ALTER TABLE silver.client_identite ALTER COLUMN client_ref         SET TAGS ('dcp' = 'pseudonyme');
