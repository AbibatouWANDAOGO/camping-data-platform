# Camping Data Platform

Design and build of a data platform for a group of four campsites (950 pitches): a **Databricks lakehouse**
(bronze, silver, gold) that turns the booking system, the online agencies' exports and the connected water and
power meters into **four data products** published every morning, with data quality controls, **GDPR**
protections (pseudonymisation, consent, masking, purge) and a **French-speaking AI assistant (Genie)** that was
tested before being trusted.

Final-year engineering project (ESIEE Paris, Software Factory course, autumn 2026), planned for two students and
**done alone**: requirements, mapping of the existing information system, data model (Hackolade), SQL notebooks,
architecture (C4), AI evaluation, ethics and security, budget.

![The platform, layer by layer](docs/images/platform_map.svg)

## The problem

80 % of the group's revenue is made in nine summer weeks, but management reads its figures in spreadsheets at the
end of the season: too late to act. Three systems do not talk to each other: the booking system (PMS), one export
file a day per online agency, and meters whose readings go nowhere. The platform must answer four questions every
morning:

| Data product | Question | For |
| --- | --- | --- |
| `dp_occupation_yield` | How many pitches were occupied last night, at what price, through which channel? | Sales management |
| `dp_taxe_sejour` | How much tourist tax do I owe the town for August? | Accounting |
| `dp_conso_anomalies` | Is there a water leak somewhere this morning? | Technical team |
| `dp_profil_clientele` | Who are our customers? Only those who agreed to statistics. | Marketing |

## How I built it: four sprints

| Sprint | Goal | What I delivered |
| --- | --- | --- |
| 1. Existing system and needs | Understand before designing | Map of actors, applications and 11 flows (3 data silos found); 9 processes in 3 families; BPMN of "book and welcome a client" before and after; use-case model; 9 functional and 14 non-functional requirements, each with how it is verified; 17 user stories |
| 2. Tools and data | Model, create and load | Polyglot model and derived Databricks model in Hackolade (19 tables, composite keys, CHECK constraints, every column described); notebooks to create and load the tables; bronze/silver/gold rules for 27 tables; 4 data contracts (ODCS YAML) |
| 3. Target architecture and AI | Describe, decide, evaluate | C4 diagrams at levels 1, 2 and 3; gaps and a two-step roadmap; 2 architecture decision records; OpenAPI spec; Genie configured and evaluated on 13 questions, benchmarks, an experiment on column comments |
| 4. Ethics and security | Protect and prove | Personal data classified in 4 levels; legal basis checked for each of the 5 purposes; data protection impact assessment; AI impact assessment (EU AI Act level); purge notebook; 23 automatic controls |
| Beyond the brief | Decide | 17-week delivery plan, budget (94 days, €48.6k), go / no-go by increment; requirement-to-code traceability matrix |

## Results

Every value below comes from the platform run on Databricks Free Edition with the sample dataset, and was checked
against an independent calculation on the source files.

| Check | Result |
| --- | --- |
| Stays loaded / rejected | 15 valid, 1 rejected with its reason (departure before arrival), never corrected silently |
| Nights (`silver.nuitee`, the central table) | 62; a stay from 31 August to 1 September counts **one** night, in August |
| Agency bookings counted once | 3 of 3 matched to their PMS stay (same pitch, dates and channel: the IDs differ) |
| Occupancy, night of 31 August | 8 of 12 pitches = **66.7 %**, summed over categories (averaging the rates would give 69.4 %) |
| Share of direct sales | 35 of 62 nights = 56.5 %, weighted (the average of nightly shares would give 62.5 %) |
| Tourist tax | August: 92 adult nights × €0.60 = **€55.20**; children exempt |
| Leak detection | E07, 50 L every hour from midnight to 6 a.m., on an **empty** pitch: the most urgent alert |
| Meter reset | E03 restarts at 2 a.m.: consumption = new value, no negative reading, no false alarm |
| Customer profile | 8 clients, only those whose **last dated** choice is "yes"; refusals, withdrawals and an undated choice excluded |
| Automatic controls | 23 (13 business rules, 2 security, 8 sample values); the nightly job stops at the first failure |

### Genie: an AI assistant tested before being trusted

Genie writes and runs SQL from a question in French. It only sees the four gold tables (aggregates, no personal
data).

| Evaluation | Result |
| --- | --- |
| 13 questions, some of them traps (averaged rates, unweighted shares, personal data, consent scope) | **10 / 13** correct without instructions, **11 / 13** with instructions and a SQL example |
| The two remaining answers (an unfounded seasonal explanation, a share generalised to all customers) | corrected by two targeted lines of instructions |
| Requests for a person's data (a stay, a client, names and e-mails) | **3 / 3 refused**: the gold layer holds no identifying data |
| Automatic benchmarks | 4 / 4 |
| Same table without column comments | same answers on 3 questions: column names carried the meaning; instructions mattered more than comments |

![Genie refuses personal data and reports the leak on an empty pitch](docs/images/genie_refus_et_fuite.png)

### Privacy by design

- The client is split in two: `silver.client` keeps a pseudonymised reference, the birth **year** and the country;
  `silver.client_identite` holds the identity, with e-mail and phone **masked** and a `dcp` tag on every personal
  column.
- Fields no data product needs (family status, partner's name) never enter silver.
- Consent is an append-only log (accept, refuse, withdraw; date, text version, channel): the last dated choice counts.
- The purge erases identities after 36 months and ID numbers 6 months after departure, in **silver and bronze**,
  logs what it erased without identifying anyone, checks the Delta history and runs `VACUUM`.
- The impact assessment found a re-identification risk (4 of 6 profile rows hold a single client): the profile is
  acceptable only with a minimum group size before any release.

## Architecture

![C4 level 2: containers](docs/images/c4_containers.png)

C4 diagrams (levels 1 to 3, editable in draw.io) are in [architecture/c4](architecture/c4), the BPMN of the key
process before and after in [architecture/bpmn](architecture/bpmn).

## Repository

```text
notebooks/
  00_orchestrer_bronze_et_lancer.sql    catalog, schemas, volume, bronze tables; runs 01 and 02; checks
  01_creer_tables_hackolade.sql         19 silver and gold tables, keys, CHECK constraints, masks, tags
  02_charger_silver_gold.sql            bronze -> silver -> gold (INSERT OVERWRITE, re-runnable)
  03_controler.sql                      23 controls; fails the job on a rule or security failure
  04_purger.sql                         GDPR purge in silver and bronze, purge log, VACUUM
  experience_genie_sans_commentaires.sql   copy of a data product without column comments
model/hackolade/       polyglot model, derived Databricks (Delta Lake) model, SQL used for the import
model/ddl_hackolade/   DDL generated by Hackolade (forward engineering)
contracts/             the four data contracts, ODCS YAML
api/                   OpenAPI 3.0.3 spec of dp_occupation_yield
architecture/          C4 (draw.io + PNG) and BPMN
```

**Running it** on Databricks Free Edition: upload the eight source files into the volume
`camping.bronze.depot` (one folder per source), then run notebooks 00 (it runs 01 and 02), 04, then 03.
The sample dataset (fictitious people, 12 pitches, 16 stays, 132 meter readings) was provided by the course and is
not redistributed here; its structure is described in the notebooks and the data contracts.

## Limits, stated honestly

- The information-system map was drawn and documented but not entered in MEGA HOPEX, the tool the course asked for.
- Bronze is loaded with `CREATE TABLE AS SELECT`; the Lakeflow pipeline, the scheduled nightly job and the dashboard
  are designed, not built. The control (03) and purge (04) notebooks are written and their logic was checked on
  the source files; their run on the platform is not yet documented with screenshots.
- Read rights per business team are written (`GRANT`) but not applied: the business groups they need may not be
  available on Free Edition.
- Reloading bronze from the source files brings purged rows back: in production, the PMS must stop sending them.
  The purge does not yet erase nationality nor expire statistics consents after 36 months.
- The executed table script was written to match the model; Hackolade's generated DDL orders the columns of
  `emplacement_historique` differently, so the two are not interchangeable as they stand.
- Genie was asked each question once; answers vary between runs.

## Credits

Subject, reference architecture and sample dataset: Software Factory course, ESIEE Paris (2026). Design, models,
notebooks, evaluation and documentation: Abibatou Wandaogo. An AI writing assistant was used for drafts; every
output was reviewed and every figure was checked against the data.
