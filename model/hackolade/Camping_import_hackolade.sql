-- =====================================================================
-- Camping_import_hackolade.sql
-- DDL au dialecte PostgreSQL, à importer dans Hackolade (Reverse-Engineering depuis un fichier DDL).
-- 19 tables : 15 dans le schéma silver, 4 dans le schéma gold. Les types sont génériques
-- (text, integer, numeric, date, timestamp, boolean) ; Hackolade les convertit ensuite en types Databricks.
-- Ce script décrit la structure : il n'est pas destiné à être exécuté sur Databricks (utiliser 01_creer_tables_hackolade.sql).
-- =====================================================================

CREATE SCHEMA silver;
CREATE SCHEMA gold;

CREATE TABLE silver.camping (
  camping text NOT NULL,
  commune text NOT NULL,
  classement_etoiles integer,
  tarif_taxe_adulte_nuit numeric(5,2),
  CONSTRAINT pk_camping PRIMARY KEY (camping)
);

CREATE TABLE silver.categorie (
  categorie_code text NOT NULL,
  libelle text NOT NULL,
  CONSTRAINT pk_categorie PRIMARY KEY (categorie_code)
);

CREATE TABLE silver.canal (
  canal_code text NOT NULL,
  libelle text,
  CONSTRAINT pk_canal PRIMARY KEY (canal_code)
);

CREATE TABLE silver.emplacement (
  emplacement_id text NOT NULL,
  camping text NOT NULL,
  categorie_code text NOT NULL,
  surface_m2 integer,
  CONSTRAINT pk_emplacement PRIMARY KEY (emplacement_id)
);

CREATE TABLE silver.client (
  client_ref text NOT NULL,
  annee_naissance integer,
  pays_residence text,
  CONSTRAINT pk_client PRIMARY KEY (client_ref)
);

CREATE TABLE silver.client_identite (
  client_ref text NOT NULL,
  nom text,
  prenom text,
  date_naissance date,
  email text,
  telephone text,
  adresse text,
  code_postal text,
  ville text,
  nationalite text,
  piece_identite_num text,
  date_creation date,
  date_derniere_activite date,
  CONSTRAINT pk_client_identite PRIMARY KEY (client_ref)
);

CREATE TABLE silver.finalite_traitement (
  finalite text NOT NULL,
  libelle text,
  base_legale text,
  duree_conservation_mois integer,
  point_de_depart text,
  CONSTRAINT pk_finalite_traitement PRIMARY KEY (finalite)
);

CREATE TABLE silver.consentement (
  client_ref text NOT NULL,
  finalite text NOT NULL,
  horodatage timestamp NOT NULL,
  statut text NOT NULL,
  canal text,
  version_texte text,
  CONSTRAINT pk_consentement PRIMARY KEY (client_ref, finalite, horodatage)
);

CREATE TABLE silver.sejour (
  sejour_id text NOT NULL,
  client_ref text NOT NULL,
  emplacement_id text NOT NULL,
  canal_code text NOT NULL,
  date_arrivee date NOT NULL,
  date_depart date NOT NULL,
  nb_adultes integer NOT NULL,
  nb_mineurs integer NOT NULL,
  montant_ttc numeric(10,2) NOT NULL,
  CONSTRAINT pk_sejour PRIMARY KEY (sejour_id),
  CONSTRAINT dates_coherentes CHECK (date_depart > date_arrivee),
  CONSTRAINT effectifs_valides CHECK (nb_adultes >= 0 AND nb_mineurs >= 0)
);

CREATE TABLE silver.sejour_rejete (
  sejour_id text NOT NULL,
  client_ref text,
  emplacement_id text,
  canal_code text,
  date_arrivee date,
  date_depart date,
  nb_adultes integer,
  nb_mineurs integer,
  montant_ttc numeric(10,2),
  motif text NOT NULL,
  rejete_le timestamp NOT NULL,
  CONSTRAINT pk_sejour_rejete PRIMARY KEY (sejour_id)
);

CREATE TABLE silver.reservation_ota (
  ota_ref text NOT NULL,
  canal_code text NOT NULL,
  emplacement_id text NOT NULL,
  date_arrivee date NOT NULL,
  date_depart date NOT NULL,
  nb_adultes integer,
  nb_mineurs integer,
  montant_ttc numeric(10,2),
  sejour_id text,
  CONSTRAINT pk_reservation_ota PRIMARY KEY (ota_ref)
);

CREATE TABLE silver.releve_compteur (
  emplacement_id text NOT NULL,
  horodatage timestamp NOT NULL,
  kwh_cumul numeric(12,2),
  litres_cumul numeric(14,2),
  CONSTRAINT pk_releve_compteur PRIMARY KEY (emplacement_id, horodatage)
);

CREATE TABLE silver.nuitee (
  sejour_id text NOT NULL,
  date_nuit date NOT NULL,
  emplacement_id text NOT NULL,
  nb_adultes integer NOT NULL,
  nb_mineurs integer NOT NULL,
  montant_nuit numeric(12,4) NOT NULL,
  CONSTRAINT pk_nuitee PRIMARY KEY (sejour_id, date_nuit)
);

CREATE TABLE silver.emplacement_historique (
  emplacement_id text NOT NULL,
  categorie_code text NOT NULL,
  date_debut_validite date NOT NULL,
  date_fin_validite date,
  CONSTRAINT pk_emplacement_historique PRIMARY KEY (emplacement_id, date_debut_validite),
  CONSTRAINT validite_coherente CHECK (date_fin_validite IS NULL OR date_fin_validite >= date_debut_validite)
);

CREATE TABLE silver.conso_quart_heure (
  emplacement_id text NOT NULL,
  horodatage timestamp NOT NULL,
  kwh numeric(10,2),
  litres numeric(12,2),
  remise_a_zero boolean NOT NULL,
  CONSTRAINT pk_conso_quart_heure PRIMARY KEY (emplacement_id, horodatage)
);

CREATE TABLE gold.dp_occupation_yield (
  date_nuit date NOT NULL,
  camping text NOT NULL,
  categorie_code text NOT NULL,
  emplacements_disponibles integer NOT NULL,
  emplacements_occupes integer NOT NULL,
  taux_occupation numeric(5,4) NOT NULL,
  chiffre_affaires numeric(12,2) NOT NULL,
  nuitees_directes integer NOT NULL,
  part_direct numeric(5,4),
  CONSTRAINT pk_dp_occupation_yield PRIMARY KEY (date_nuit, camping, categorie_code),
  CONSTRAINT taux_valide CHECK (taux_occupation BETWEEN 0 AND 1),
  CONSTRAINT occupes_valides CHECK (emplacements_occupes <= emplacements_disponibles)
);

CREATE TABLE gold.dp_taxe_sejour (
  commune text NOT NULL,
  mois date NOT NULL,
  nuitees_adultes integer NOT NULL,
  tarif_adulte_nuit numeric(5,2) NOT NULL,
  montant_a_reverser numeric(12,2) NOT NULL,
  CONSTRAINT pk_dp_taxe_sejour PRIMARY KEY (commune, mois)
);

CREATE TABLE gold.dp_conso_anomalies (
  emplacement_id text NOT NULL,
  heure timestamp NOT NULL,
  kwh numeric(10,2),
  litres numeric(12,2),
  remise_a_zero boolean NOT NULL,
  fuite_probable boolean NOT NULL,
  emplacement_occupe boolean NOT NULL,
  CONSTRAINT pk_dp_conso_anomalies PRIMARY KEY (emplacement_id, heure)
);

CREATE TABLE gold.dp_profil_clientele (
  mois date NOT NULL,
  tranche_age text NOT NULL,
  type_groupe text NOT NULL,
  pays text NOT NULL,
  nb_clients integer NOT NULL,
  nb_sejours integer NOT NULL,
  nb_nuitees integer NOT NULL,
  chiffre_affaires numeric(12,2) NOT NULL,
  CONSTRAINT pk_dp_profil_clientele PRIMARY KEY (mois, tranche_age, type_groupe, pays)
);

-- ---- Clés étrangères : relations des tables silver (les relations gold sont des foreign master, à dessiner dans Hackolade)
ALTER TABLE silver.emplacement ADD CONSTRAINT fk_emplacement_camping FOREIGN KEY (camping) REFERENCES silver.camping (camping);
ALTER TABLE silver.emplacement ADD CONSTRAINT fk_emplacement_categorie_code FOREIGN KEY (categorie_code) REFERENCES silver.categorie (categorie_code);
ALTER TABLE silver.client_identite ADD CONSTRAINT fk_client_identite_client_ref FOREIGN KEY (client_ref) REFERENCES silver.client (client_ref);
ALTER TABLE silver.consentement ADD CONSTRAINT fk_consentement_client_ref FOREIGN KEY (client_ref) REFERENCES silver.client (client_ref);
ALTER TABLE silver.consentement ADD CONSTRAINT fk_consentement_finalite FOREIGN KEY (finalite) REFERENCES silver.finalite_traitement (finalite);
ALTER TABLE silver.sejour ADD CONSTRAINT fk_sejour_client_ref FOREIGN KEY (client_ref) REFERENCES silver.client (client_ref);
ALTER TABLE silver.sejour ADD CONSTRAINT fk_sejour_emplacement_id FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id);
ALTER TABLE silver.sejour ADD CONSTRAINT fk_sejour_canal_code FOREIGN KEY (canal_code) REFERENCES silver.canal (canal_code);
ALTER TABLE silver.reservation_ota ADD CONSTRAINT fk_reservation_ota_sejour_id FOREIGN KEY (sejour_id) REFERENCES silver.sejour (sejour_id);
ALTER TABLE silver.releve_compteur ADD CONSTRAINT fk_releve_compteur_emplacement_id FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id);
ALTER TABLE silver.nuitee ADD CONSTRAINT fk_nuitee_sejour_id FOREIGN KEY (sejour_id) REFERENCES silver.sejour (sejour_id);
ALTER TABLE silver.nuitee ADD CONSTRAINT fk_nuitee_emplacement_id FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id);
ALTER TABLE silver.emplacement_historique ADD CONSTRAINT fk_emplacement_historique_emplacement_id FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id);
ALTER TABLE silver.emplacement_historique ADD CONSTRAINT fk_emplacement_historique_categorie_code FOREIGN KEY (categorie_code) REFERENCES silver.categorie (categorie_code);
ALTER TABLE silver.conso_quart_heure ADD CONSTRAINT fk_conso_quart_heure_emplacement_id FOREIGN KEY (emplacement_id) REFERENCES silver.emplacement (emplacement_id);

-- ---- Commentaires (descriptions des tables et des colonnes)
COMMENT ON TABLE silver.camping IS 'Les campings du groupe';
COMMENT ON COLUMN silver.camping.camping IS 'Nom du camping (clé)';
COMMENT ON COLUMN silver.camping.commune IS 'Commune de rattachement : sert à reverser la taxe de séjour';
COMMENT ON COLUMN silver.camping.classement_etoiles IS 'Classement en étoiles';
COMMENT ON COLUMN silver.camping.tarif_taxe_adulte_nuit IS 'Tarif de la taxe de séjour par adulte et par nuit, en euros';
COMMENT ON TABLE silver.categorie IS 'Catégories d''emplacement';
COMMENT ON COLUMN silver.categorie.categorie_code IS 'NU nu, MH mobil-home, PR premium';
COMMENT ON COLUMN silver.categorie.libelle IS 'Libellé de la catégorie';
COMMENT ON TABLE silver.canal IS 'Canaux de vente';
COMMENT ON COLUMN silver.canal.canal_code IS 'DIRECT, BOOKING, CAMPINGS...';
COMMENT ON COLUMN silver.canal.libelle IS 'Libellé du canal de vente';
COMMENT ON TABLE silver.emplacement IS 'Emplacements (parcelles) des campings';
COMMENT ON COLUMN silver.emplacement.emplacement_id IS 'Identifiant de la parcelle louée';
COMMENT ON COLUMN silver.emplacement.camping IS 'Camping de l''emplacement';
COMMENT ON COLUMN silver.emplacement.categorie_code IS 'Catégorie actuelle de l''emplacement';
COMMENT ON COLUMN silver.emplacement.surface_m2 IS 'Surface de l''emplacement en m² (PMS ; absente du jeu d''exemple)';
COMMENT ON TABLE silver.client IS 'Client pseudonymisé : aucune donnée identifiante';
COMMENT ON COLUMN silver.client.client_ref IS 'Référence pseudonymisée du client (clé du PMS)';
COMMENT ON COLUMN silver.client.annee_naissance IS 'Année de naissance seulement (statistiques)';
COMMENT ON COLUMN silver.client.pays_residence IS 'Pays de résidence';
COMMENT ON TABLE silver.client_identite IS 'Identité du client, à part et protégée. Masque sur email et telephone ; étiquette dcp sur chaque colonne [DCP]';
COMMENT ON COLUMN silver.client_identite.client_ref IS '[DCP] Référence du client';
COMMENT ON COLUMN silver.client_identite.nom IS '[DCP] Nom';
COMMENT ON COLUMN silver.client_identite.prenom IS '[DCP] Prénom';
COMMENT ON COLUMN silver.client_identite.date_naissance IS '[DCP] Date de naissance complète';
COMMENT ON COLUMN silver.client_identite.email IS '[DCP] E-mail (masqué)';
COMMENT ON COLUMN silver.client_identite.telephone IS '[DCP] Téléphone (masqué)';
COMMENT ON COLUMN silver.client_identite.adresse IS '[DCP] Adresse postale (facturation)';
COMMENT ON COLUMN silver.client_identite.code_postal IS '[DCP] Code postal';
COMMENT ON COLUMN silver.client_identite.ville IS '[DCP] Ville';
COMMENT ON COLUMN silver.client_identite.nationalite IS '[DCP] Nationalité (fiche de police)';
COMMENT ON COLUMN silver.client_identite.piece_identite_num IS '[DCP] Numéro de pièce d''identité, clients étrangers, effacé 6 mois après le départ';
COMMENT ON COLUMN silver.client_identite.date_creation IS 'Création de la fiche';
COMMENT ON COLUMN silver.client_identite.date_derniere_activite IS 'Point de départ de la durée de conservation CONTRAT';
COMMENT ON TABLE silver.finalite_traitement IS 'Finalités, base légale et durée de conservation';
COMMENT ON COLUMN silver.finalite_traitement.finalite IS 'CONTRAT, COMPTA, POLICE, STATS, MARKETING';
COMMENT ON COLUMN silver.finalite_traitement.libelle IS 'Pour quoi faire';
COMMENT ON COLUMN silver.finalite_traitement.base_legale IS 'Base légale à vérifier (RGPD, article 6)';
COMMENT ON COLUMN silver.finalite_traitement.duree_conservation_mois IS 'Durée de conservation en mois';
COMMENT ON COLUMN silver.finalite_traitement.point_de_depart IS 'Événement qui déclenche la durée';
COMMENT ON TABLE silver.consentement IS 'Journal des consentements : un événement par ligne, le dernier choix compte';
COMMENT ON COLUMN silver.consentement.client_ref IS 'Le client';
COMMENT ON COLUMN silver.consentement.finalite IS 'STATS ou MARKETING';
COMMENT ON COLUMN silver.consentement.horodatage IS 'Date et heure du choix (preuve)';
COMMENT ON COLUMN silver.consentement.statut IS 'ACCORDE, REFUSE ou RETIRE';
COMMENT ON COLUMN silver.consentement.canal IS 'WEB ou ACCUEIL';
COMMENT ON COLUMN silver.consentement.version_texte IS 'Version du texte d''information montré au client';
COMMENT ON TABLE silver.sejour IS 'Séjours valides : la contrainte dates_coherentes refuse les autres';
COMMENT ON COLUMN silver.sejour.sejour_id IS 'Identifiant du séjour dans le PMS';
COMMENT ON COLUMN silver.sejour.client_ref IS 'Client';
COMMENT ON COLUMN silver.sejour.emplacement_id IS 'Emplacement';
COMMENT ON COLUMN silver.sejour.canal_code IS 'Canal de vente';
COMMENT ON COLUMN silver.sejour.date_arrivee IS 'Date d''arrivée';
COMMENT ON COLUMN silver.sejour.date_depart IS 'Date de départ : la nuit du départ n''est pas comptée';
COMMENT ON COLUMN silver.sejour.nb_adultes IS 'Nombre d''adultes';
COMMENT ON COLUMN silver.sejour.nb_mineurs IS 'Nombre de mineurs (exonérés de taxe)';
COMMENT ON COLUMN silver.sejour.montant_ttc IS 'Montant TTC du séjour';
COMMENT ON TABLE silver.sejour_rejete IS 'Séjours écartés, signalés et non corrigés en silence';
COMMENT ON COLUMN silver.sejour_rejete.sejour_id IS 'Identifiant du séjour écarté';
COMMENT ON COLUMN silver.sejour_rejete.client_ref IS 'Client';
COMMENT ON COLUMN silver.sejour_rejete.emplacement_id IS 'Emplacement';
COMMENT ON COLUMN silver.sejour_rejete.canal_code IS 'Canal de vente';
COMMENT ON COLUMN silver.sejour_rejete.date_arrivee IS 'Date d''arrivée';
COMMENT ON COLUMN silver.sejour_rejete.date_depart IS 'Date de départ';
COMMENT ON COLUMN silver.sejour_rejete.nb_adultes IS 'Nombre d''adultes';
COMMENT ON COLUMN silver.sejour_rejete.nb_mineurs IS 'Nombre de mineurs';
COMMENT ON COLUMN silver.sejour_rejete.montant_ttc IS 'Montant TTC';
COMMENT ON COLUMN silver.sejour_rejete.motif IS 'Pourquoi le séjour est rejeté';
COMMENT ON COLUMN silver.sejour_rejete.rejete_le IS 'Date du rejet';
COMMENT ON TABLE silver.reservation_ota IS 'Réservations OTA rapprochées du séjour PMS pour ne les compter qu''une fois';
COMMENT ON COLUMN silver.reservation_ota.ota_ref IS 'Identifiant chez l''agence en ligne (différent de sejour_id)';
COMMENT ON COLUMN silver.reservation_ota.canal_code IS 'BOOKING, CAMPINGS...';
COMMENT ON COLUMN silver.reservation_ota.emplacement_id IS 'Emplacement attribué';
COMMENT ON COLUMN silver.reservation_ota.date_arrivee IS 'Date d''arrivée';
COMMENT ON COLUMN silver.reservation_ota.date_depart IS 'Date de départ';
COMMENT ON COLUMN silver.reservation_ota.nb_adultes IS 'Nombre d''adultes';
COMMENT ON COLUMN silver.reservation_ota.nb_mineurs IS 'Nombre de mineurs';
COMMENT ON COLUMN silver.reservation_ota.montant_ttc IS 'Montant TTC payé';
COMMENT ON COLUMN silver.reservation_ota.sejour_id IS 'Séjour PMS rapproché (doublon) ; vide si aucun';
COMMENT ON TABLE silver.releve_compteur IS 'Relevés des compteurs, typés (un relevé toutes les 15 minutes)';
COMMENT ON COLUMN silver.releve_compteur.emplacement_id IS 'Emplacement équipé';
COMMENT ON COLUMN silver.releve_compteur.horodatage IS 'Date et heure du relevé';
COMMENT ON COLUMN silver.releve_compteur.kwh_cumul IS 'Index électrique en kWh (repart à zéro après une coupure)';
COMMENT ON COLUMN silver.releve_compteur.litres_cumul IS 'Index d''eau en litres';
COMMENT ON TABLE silver.nuitee IS 'Une ligne par séjour et par nuit : table centrale';
COMMENT ON COLUMN silver.nuitee.sejour_id IS 'Séjour';
COMMENT ON COLUMN silver.nuitee.date_nuit IS 'La nuit (la nuit du départ n''existe pas)';
COMMENT ON COLUMN silver.nuitee.emplacement_id IS 'Emplacement occupé cette nuit-là';
COMMENT ON COLUMN silver.nuitee.nb_adultes IS 'Adultes (base de la taxe)';
COMMENT ON COLUMN silver.nuitee.nb_mineurs IS 'Mineurs (exonérés)';
COMMENT ON COLUMN silver.nuitee.montant_nuit IS 'Montant du séjour réparti à parts égales sur ses nuits';
COMMENT ON TABLE silver.emplacement_historique IS 'Versions de catégorie d''un emplacement, avec dates de validité : les chiffres d''une saison passée gardent l''ancienne catégorie';
COMMENT ON COLUMN silver.emplacement_historique.emplacement_id IS 'Emplacement';
COMMENT ON COLUMN silver.emplacement_historique.categorie_code IS 'Catégorie valable pendant cette version';
COMMENT ON COLUMN silver.emplacement_historique.date_debut_validite IS 'Premier jour de validité de cette catégorie';
COMMENT ON COLUMN silver.emplacement_historique.date_fin_validite IS 'Dernier jour de validité ; vide pour la version en cours';
COMMENT ON TABLE silver.conso_quart_heure IS 'Consommation de chaque quart d''heure, calculée à partir des index des compteurs';
COMMENT ON COLUMN silver.conso_quart_heure.emplacement_id IS 'Emplacement équipé';
COMMENT ON COLUMN silver.conso_quart_heure.horodatage IS 'Date et heure du relevé qui clôt le quart d''heure';
COMMENT ON COLUMN silver.conso_quart_heure.kwh IS 'kWh consommés pendant le quart d''heure (nouvelle valeur après une remise à zéro)';
COMMENT ON COLUMN silver.conso_quart_heure.litres IS 'Litres consommés pendant le quart d''heure';
COMMENT ON COLUMN silver.conso_quart_heure.remise_a_zero IS 'Un compteur a redémarré pendant ce quart d''heure';
COMMENT ON TABLE gold.dp_occupation_yield IS 'Data product commercial : occupation, CA et canaux. Grain : une nuit x un camping x une catégorie';
COMMENT ON COLUMN gold.dp_occupation_yield.date_nuit IS 'La nuit';
COMMENT ON COLUMN gold.dp_occupation_yield.camping IS 'Camping';
COMMENT ON COLUMN gold.dp_occupation_yield.categorie_code IS 'NU, MH ou PR';
COMMENT ON COLUMN gold.dp_occupation_yield.emplacements_disponibles IS 'Emplacements de cette catégorie dans ce camping';
COMMENT ON COLUMN gold.dp_occupation_yield.emplacements_occupes IS 'Emplacements occupés cette nuit-là';
COMMENT ON COLUMN gold.dp_occupation_yield.taux_occupation IS 'occupés / disponibles. Le taux global se recalcule avec les sommes, jamais par moyenne des taux';
COMMENT ON COLUMN gold.dp_occupation_yield.chiffre_affaires IS 'Chiffre d''affaires TTC de la nuit';
COMMENT ON COLUMN gold.dp_occupation_yield.nuitees_directes IS 'Nuitées vendues en direct (pour pondérer la part du direct)';
COMMENT ON COLUMN gold.dp_occupation_yield.part_direct IS 'nuitées directes / nuitées occupées';
COMMENT ON TABLE gold.dp_taxe_sejour IS 'Data product comptable : base de la taxe de séjour. Grain : une commune x un mois';
COMMENT ON COLUMN gold.dp_taxe_sejour.commune IS 'Commune à qui la taxe est reversée';
COMMENT ON COLUMN gold.dp_taxe_sejour.mois IS 'Premier jour du mois';
COMMENT ON COLUMN gold.dp_taxe_sejour.nuitees_adultes IS 'Nuitées d''adultes (mineurs exonérés)';
COMMENT ON COLUMN gold.dp_taxe_sejour.tarif_adulte_nuit IS 'Tarif de la taxe par adulte et par nuit';
COMMENT ON COLUMN gold.dp_taxe_sejour.montant_a_reverser IS 'nuitees_adultes x tarif';
COMMENT ON TABLE gold.dp_conso_anomalies IS 'Data product technique : consommation et alertes de fuite. Grain : un emplacement x une heure';
COMMENT ON COLUMN gold.dp_conso_anomalies.emplacement_id IS 'Emplacement';
COMMENT ON COLUMN gold.dp_conso_anomalies.heure IS 'Heure pleine';
COMMENT ON COLUMN gold.dp_conso_anomalies.kwh IS 'kWh consommés pendant l''heure';
COMMENT ON COLUMN gold.dp_conso_anomalies.litres IS 'Litres consommés pendant l''heure';
COMMENT ON COLUMN gold.dp_conso_anomalies.remise_a_zero IS 'Un compteur a redémarré pendant l''heure';
COMMENT ON COLUMN gold.dp_conso_anomalies.fuite_probable IS '40 L ou plus chaque heure entre 0 h et 6 h';
COMMENT ON COLUMN gold.dp_conso_anomalies.emplacement_occupe IS 'Emplacement occupé cette nuit-là ; fuite sur emplacement vide = urgence';
COMMENT ON TABLE gold.dp_profil_clientele IS 'Data product marketing : seulement les clients dont le dernier choix STATS est un accord. Grain : un mois x une tranche d''âge x un type de groupe x un pays';
COMMENT ON COLUMN gold.dp_profil_clientele.mois IS 'Mois d''arrivée du séjour';
COMMENT ON COLUMN gold.dp_profil_clientele.tranche_age IS '18-24, 25-34, 35-44, 45-54, 55-64, 65+';
COMMENT ON COLUMN gold.dp_profil_clientele.type_groupe IS 'solo, adultes ou famille (avec mineurs)';
COMMENT ON COLUMN gold.dp_profil_clientele.pays IS 'Pays de résidence';
COMMENT ON COLUMN gold.dp_profil_clientele.nb_clients IS 'Nombre de clients';
COMMENT ON COLUMN gold.dp_profil_clientele.nb_sejours IS 'Nombre de séjours';
COMMENT ON COLUMN gold.dp_profil_clientele.nb_nuitees IS 'Nombre de nuitées';
COMMENT ON COLUMN gold.dp_profil_clientele.chiffre_affaires IS 'Chiffre d''affaires TTC';
