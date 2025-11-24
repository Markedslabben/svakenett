# Datamodell for Identifisering av Kunder med Svakt Nett i Norge

**Rapport utarbeidet:** 3. november 2025
**Formål:** Analysere gjennomførbarhet for automatisk identifisering av potensielle offgrid/svakt nett kunder basert på offentlige data
**Kontekst:** Norsk Solkraft AS - Business area: Offgrid (hytte, båt, telecom)

---

## EXECUTIVE SUMMARY

**Konklusjon:** Datamodellen er teknisk gjennomførbar, men med betydelige begrensninger i datakvalitet og personvern. En hybrid tilnærming med geografisk scoring kombinert med manuell validering anbefales.

**Nøkkelfunn:**
- ✅ Geografiske data er tilgjengelige og lovlige å bruke
- ⚠️ Detaljerte nettdata er begrenset av personvern og nettselskap-policy
- ✅ KILE-data gir gode indikatorer på nettproblemer
- ❌ Direkte identifisering av enkeltpersoner er ikke mulig uten samtykke
- ✅ MVP kan bygges med eksisterende Python-stack innen 2-4 uker

**Anbefalt tilnærming:**
1. **Fase 1:** Geografisk scoring av områder (sannsynlighet for svakt nett)
2. **Fase 2:** Lead generation gjennom målrettet markedsføring i identifiserte områder
3. **Fase 3:** CRM-integrasjon for å kvalifisere leads

---

## 1. KARTLEGGING AV DATAKILDER

### 1.1 NVE (Norges vassdrags- og energidirektorat)

#### Tilgjengelige datasett:

**A) KILE-data (Kvalitetsjusterte inntekter)**
- **URL:** https://www.nve.no/energi/energisystem/kraftmarkedet/kile/
- **Format:** Excel/CSV, nedlastbart årsvis
- **Innhold:**
  - Avbruddshyppighet per nettselskap
  - Gjennomsnittlig avbruddstid (SAIDI - System Average Interruption Duration Index)
  - Antall avbrudd per kunde (SAIFI - System Average Interruption Frequency Index)
  - Ikke-levert energi (kWh)
  - KILE-kompensasjon (NOK) per nettområde
- **Geografisk granularitet:** Nettselskap-nivå (ca. 120 nettselskap i Norge)
- **Oppdateringsfrekvens:** Årlig
- **Juridisk:** Offentlig data, fritt tilgjengelig
- **Vurdering:** ⭐⭐⭐⭐⭐ Meget verdifull for å identifisere problemområder

**B) Nettstatistikk**
- **URL:** https://www.nve.no/energi/energisystem/kraftsystemet/nettstatistikk/
- **Format:** Excel, årsrapporter
- **Innhold:**
  - Ledningslengde per spenningsnivå
  - Antall kunder per nettselskap
  - Nettap (indikator på ledningsavstand)
  - Investeringer i nettutbygging
- **Geografisk granularitet:** Nettselskap-nivå
- **Vurdering:** ⭐⭐⭐⭐ Nyttig for strukturell analyse

**C) Konsesjonsdatabase**
- **URL:** https://www.nve.no/konsesjon/konsesjonssaker/
- **Format:** Søkbar database, ingen bulk download
- **Innhold:**
  - Konsesjoner for kraftledninger
  - Geografiske koordinater
  - Spenningsnivå
  - Status (planlagt, under bygging, i drift)
- **Vurdering:** ⭐⭐⭐ Nyttig for å identifisere områder uten infrastruktur

**D) NVE Atlas (Kartdata)**
- **URL:** https://atlas.nve.no/
- **Format:** WMS (Web Map Service), GeoJSON
- **Innhold:**
  - Kraftledninger (visualisering)
  - Kraftstasjoner
  - Konsesjonssoner
- **API:** Ja, via WMS-standard
- **Vurdering:** ⭐⭐⭐⭐ Meget verdifull for geografisk analyse

### 1.2 Elhub

**Status:** Elhub er Norges sentrale datahub for måle- og forbruksdata.

**A) Offentlig API**
- **URL:** https://elhub.no/elhub-api/
- **Format:** REST API, OAuth 2.0
- **Innhold:**
  - Aggregerte forbruksdata (IKKE individuelle målinger)
  - Nettselskap per målepunkt (via organisasjonsnummer)
  - Nettnivå (høyspent, lavspent)
- **Tilgang:** Krever akkreditering og avtale
- **Juridisk:** Kun aggregerte data, GDPR-begrenset
- **Vurdering:** ⭐⭐ Begrenset verdi uten individuelle målinger

**B) Målepunktregister**
- **Status:** Ikke offentlig tilgjengelig på individnivå
- **Juridisk:** Personopplysninger, krever samtykke
- **Vurdering:** ❌ Ikke tilgjengelig

### 1.3 SSB (Statistisk Sentralbyrå)

**A) Befolkningsstatistikk**
- **URL:** https://data.ssb.no/
- **Format:** API (JSON), CSV
- **Innhold:**
  - Befolkningstetthet per grunnkrets
  - Husholdningsstørrelse
  - Boligtype
- **API:** Ja, SSB API v2
- **Vurdering:** ⭐⭐⭐⭐ Nyttig for å identifisere rurale områder

**B) Fritidsboliger (hytter)**
- **URL:** https://www.ssb.no/statbank/table/11823/
- **Format:** Statbank-tabell
- **Innhold:**
  - Antall hytter per kommune
  - Bruksareal
  - Byggeår
- **Geografisk granularitet:** Kommune-nivå
- **Vurdering:** ⭐⭐⭐⭐⭐ Kritisk for offgrid-segmentet

**C) Landbruksstatistikk**
- **URL:** https://www.ssb.no/jord-skog-jakt-og-fiskeri/jordbruk
- **Innhold:**
  - Gårdsbruk per kommune
  - Driftsform
  - Areal
- **Vurdering:** ⭐⭐⭐ Nyttig for å identifisere gårdsbruk

### 1.4 Kartverket

**A) N50 Kartdata**
- **URL:** https://kartkatalog.geonorge.no/
- **Format:** GeoJSON, SOSI
- **Innhold:**
  - Bygninger
  - Veier
  - Terreng
  - Bebyggelse
- **API:** Ja, via Geonorge WFS
- **Vurdering:** ⭐⭐⭐⭐ Nyttig for avstandsberegninger

**B) Høydedata (DTM)**
- **URL:** https://hoydedata.no/
- **Format:** GeoTIFF, LAS (LiDAR)
- **Innhold:**
  - Terrengmodell
  - Nyttig for å identifisere isolerte fjellområder
- **Vurdering:** ⭐⭐⭐ Supplerende data

### 1.5 Matrikkelen

**A) Eiendomsdata**
- **URL:** https://www.kartverket.no/api-og-data/matrikkelen
- **Format:** API (SOAP/REST)
- **Innhold:**
  - Eiendomsinformasjon (gårdsnummer, bruksnummer, festenummer)
  - Bygningstype
  - Bruksenhet
- **Tilgang:** Krever avtale med Kartverket
- **Juridisk:** Offentlig data, men med restriksoner på kommersiell bruk
- **Vurdering:** ⭐⭐⭐⭐ Verdifull, men krever juridisk avklaring

**B) GAB-register (Grunneiendom, Adresse, Bygning)**
- **Innhold:**
  - Bygningstype (fritidsbolig, våningshus, driftsbygning)
  - Byggeår
  - Bruksareal
- **Vurdering:** ⭐⭐⭐⭐⭐ Meget verdifull for segmentering

### 1.6 Andre relevante kilder

**A) Kommunale planer**
- **Kilde:** Kommunale nettsider, PlanData
- **Innhold:** Reguleringsplaner, utbyggingsområder
- **Vurdering:** ⭐⭐ Varierende kvalitet, manuelt arbeid

**B) Nettselskap sine nettkart**
- **Eksempel:** Agder Energi Nett, Glitre Energi
- **Format:** Web-kart, ingen API
- **Innhold:** Nettstruktur, transformatorer, ledninger
- **Vurdering:** ⭐⭐⭐ Nyttig, men manuelt arbeid per nettselskap

**C) Telecom infrastruktur**
- **Kilde:** Nasjonal kommunikasjonsmyndighet (Nkom)
- **Innhold:** Dekning for mobilnett, fiber
- **Vurdering:** ⭐⭐ Indirekte indikator på isolerte områder

---

## 2. DEFINISJON: "SVAKT NETT" - TEKNISKE INDIKATORER

### 2.1 Direkte tekniske parametere (ideelt, men ikke tilgjengelig på individnivå)

| Parameter | Sterk nett | Svakt nett | Datakilde (teoretisk) |
|-----------|------------|------------|------------------------|
| **Effekttilgang** | 3-fase, ≥32A | 1-fase, ≤16A | Nettselskap (ikke offentlig) |
| **Spenningsnivå** | 230V ±10% | >10% variasjon | Målinger (ikke offentlig) |
| **Avstand transformator** | <500m | >1000m | Nettkart (delvis tilgjengelig) |
| **Ledningstype** | Jordkabel, ACSR | Luftledning, gammel | Nettkart (delvis tilgjengelig) |
| **Spenningsfall** | <5% | >10% | Målinger (ikke tilgjengelig) |
| **Kunder per transformator** | <20 | >50 | Nettselskap (ikke offentlig) |

**Konklusjon:** Direkte tekniske parametere er IKKE tilgjengelige på individnivå grunnet personvern og nettselskap-policy.

### 2.2 Indirekte indikatorer (tilgjengelig via offentlige data)

| Indikator | Sterk korrelasjon med svakt nett | Datakilde | Geografisk nivå |
|-----------|----------------------------------|-----------|-----------------|
| **KILE-kompensasjon** | Ja - høy SAIDI/SAIFI = svakt nett | NVE KILE-data | Nettselskap |
| **Befolkningstetthet** | Ja - lav tetthet = lenger til nett | SSB | Grunnkrets |
| **Avstand til nærmeste vei** | Ja - isolerte områder | Kartverket | Bygning |
| **Bygningstype: Fritidsbolig** | Ja - hytter ofte offgrid-kandidater | Matrikkelen GAB | Bygning |
| **Nettap i området** | Ja - høyt tap = lange ledninger | NVE nettstatistikk | Nettselskap |
| **Antall naboer innen 500m** | Ja - få naboer = dyrere tilkobling | Kartverket N50 | Koordinat |
| **Avstand til nærmeste kraftledning** | Ja - lang avstand = kostbar tilkobling | NVE Atlas | Koordinat |
| **Telecom dekning** | Nei - dårlig mobil ≠ svakt nett | Nkom | Nettselskap/kommune |

### 2.3 Scoringssystem for "Svakt Nett-sannsynlighet"

Foreslått vektet scoring (0-100 poeng):

**Geografiske faktorer (40 poeng):**
- Avstand til kraftledning (15p): 0-500m=0p, 500-1000m=8p, >1000m=15p
- Befolkningstetthet (10p): >100/km²=0p, 10-100/km²=5p, <10/km²=10p
- Naboer innen 500m (10p): >20=0p, 10-20=5p, <10=10p
- Avstand til offentlig vei (5p): 0-100m=0p, 100-500m=3p, >500m=5p

**Nettselskap faktorer (30 poeng):**
- KILE SAIDI (15p): <60min/år=0p, 60-180min=8p, >180min=15p
- KILE SAIFI (10p): <1.0/år=0p, 1.0-2.0=5p, >2.0=10p
- Nettap % (5p): <5%=0p, 5-10%=3p, >10%=5p

**Eiendomsfaktorer (30 poeng):**
- Bygningstype (20p): Bolig=0p, Driftsbygning=10p, Fritidsbolig=20p
- Byggeår (5p): >2000=0p, 1950-2000=3p, <1950=5p
- Bruksareal (5p): <50m²=0p, 50-150m²=3p, >150m²=5p

**Tolkningstabell:**
- **80-100 poeng:** Meget høy sannsynlighet (prioritert segment)
- **60-79 poeng:** Høy sannsynlighet (aktiv markedsføring)
- **40-59 poeng:** Middels sannsynlighet (passiv markedsføring)
- **0-39 poeng:** Lav sannsynlighet (ikke relevant)

---

## 3. METODIKK FOR DATAMODELL

### 3.1 Overordnet arkitektur

```
┌─────────────────────────────────────────────────────────┐
│  DATA SOURCES (Batch Import)                            │
├─────────────────────────────────────────────────────────┤
│  NVE KILE │ SSB │ Kartverket │ Matrikkelen │ NVE Atlas │
└────┬─────────────────────────────────────────────────┬──┘
     │                                                  │
     ▼                                                  ▼
┌─────────────────────┐                    ┌─────────────────────┐
│  DATA PROCESSING    │                    │  GEOSPATIAL ENGINE  │
│  (Python/Pandas)    │◄──────────────────►│  (GeoPandas/PostGIS)│
└──────────┬──────────┘                    └──────────┬──────────┘
           │                                           │
           ▼                                           ▼
     ┌──────────────────────────────────────────────────────┐
     │  SCORING ENGINE (Scikit-learn/Custom)                │
     │  - Geografisk scoring                                 │
     │  - Nettselskap scoring                                │
     │  - Eiendomsscoring                                    │
     └──────────────────┬───────────────────────────────────┘
                        │
                        ▼
     ┌──────────────────────────────────────────────────────┐
     │  OUTPUT & VISUALIZATION                               │
     │  - Lead lists (CSV/Excel)                             │
     │  - Interactive maps (Folium/Plotly)                   │
     │  - CRM integration (API)                              │
     └──────────────────────────────────────────────────────┘
```

### 3.2 Input data per eiendom

**Minimum viable input:**
```python
property_data = {
    "property_id": "1234-567-89-1",  # Gårdsnr-bruksnr-festenr-seksjonsnr
    "latitude": 59.1234,
    "longitude": 8.5678,
    "building_type": "fritidsbolig",
    "municipality": "4626",  # Kommune-ID
    "grid_company": "7080001234567",  # Org.nr nettselskap
    "building_year": 1985,
    "floor_area_m2": 75
}
```

### 3.3 Prosessering: Datapipeline

**Steg 1: Data Ingestion (Batch, månedlig/årlig)**
```python
import pandas as pd
import geopandas as gpd

# Last NVE KILE-data
kile_df = pd.read_excel("nve_kile_2024.xlsx")

# Last SSB hyttedata
ssb_cabins_df = pd.read_csv("ssb_cabins.csv")

# Last GAB bygningsdata (via API eller batch-fil)
gab_df = fetch_gab_data(api_key="...")

# Last kraftledninger fra NVE Atlas (WMS)
power_lines_gdf = gpd.read_file("nve_atlas_wms.geojson")
```

**Steg 2: Geospatial Joining**
```python
# Konverter bygninger til GeoDataFrame
buildings_gdf = gpd.GeoDataFrame(
    gab_df,
    geometry=gpd.points_from_xy(gab_df.longitude, gab_df.latitude),
    crs="EPSG:4326"
)

# Beregn avstand til nærmeste kraftledning
buildings_gdf['dist_to_power_line_m'] = buildings_gdf.geometry.apply(
    lambda point: power_lines_gdf.distance(point).min()
)

# Spatial join: Finn befolkningstetthet per grunnkrets
buildings_gdf = gpd.sjoin(
    buildings_gdf,
    population_density_gdf,
    how="left",
    predicate="within"
)
```

**Steg 3: Feature Engineering**
```python
def calculate_weak_grid_score(row):
    score = 0

    # Geografiske faktorer (40p)
    if row['dist_to_power_line_m'] > 1000:
        score += 15
    elif row['dist_to_power_line_m'] > 500:
        score += 8

    if row['population_density'] < 10:
        score += 10
    elif row['population_density'] < 100:
        score += 5

    # Nettselskap faktorer (30p)
    grid_company = kile_df[kile_df['org_nr'] == row['grid_company']]
    if not grid_company.empty:
        saidi = grid_company.iloc[0]['SAIDI_minutes']
        if saidi > 180:
            score += 15
        elif saidi > 60:
            score += 8

    # Eiendomsfaktorer (30p)
    if row['building_type'] == 'fritidsbolig':
        score += 20
    elif row['building_type'] == 'driftsbygning':
        score += 10

    return score

buildings_gdf['weak_grid_score'] = buildings_gdf.apply(
    calculate_weak_grid_score, axis=1
)
```

**Steg 4: Segmentering & Prioritering**
```python
# Filtrer til høy-prioritet leads
high_priority_leads = buildings_gdf[
    buildings_gdf['weak_grid_score'] >= 60
].sort_values('weak_grid_score', ascending=False)

# Eksporter til CRM-vennlig format
high_priority_leads[['property_id', 'latitude', 'longitude',
                     'building_type', 'weak_grid_score']].to_csv(
    "leads_high_priority.csv", index=False
)
```

### 3.4 Algoritmer & Modeller

**Fase 1: Regelbasert scoring (MVP)**
- Deterministisk scoring basert på vektede regler (se seksjon 2.3)
- Ingen maskinlæring, kun IF-THEN logikk
- Forventet nøyaktighet: 60-70% (estimat)

**Fase 2: Machine Learning (v2.0)**
- **Treningsdata:** Eksisterende kunder fra Norsk Solkraft (labeled data)
- **Features:** Alle tilgjengelige geografiske, nett- og eiendomsvariabler
- **Algoritme:** Random Forest Classifier eller Gradient Boosting
- **Target variable:** `is_weak_grid_customer` (binary: ja/nei)
- **Evaluering:** Cross-validation, precision/recall for "svakt nett"-klasse

```python
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

# Tren modell på eksisterende kunder
X = buildings_gdf[features]
y = buildings_gdf['is_weak_grid_customer']  # Må labeles manuelt først

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

rf_model = RandomForestClassifier(n_estimators=100, max_depth=10)
rf_model.fit(X_train, y_train)

# Prediker på nye eiendommer
buildings_gdf['weak_grid_probability'] = rf_model.predict_proba(X)[:, 1]
```

### 3.5 Output

**A) Lead lists (strukturerte data)**
```csv
property_id,latitude,longitude,municipality,building_type,weak_grid_score,contact_priority
1234-567-89-1,59.1234,8.5678,4626,fritidsbolig,87,HIGH
1235-568-90-2,59.2345,8.6789,4627,driftsbygning,72,HIGH
...
```

**B) Geografisk visualisering (interaktivt kart)**
```python
import folium
from folium.plugins import HeatMap

# Lag heatmap over "svakt nett"-sannsynlighet
m = folium.Map(location=[58.5, 8.5], zoom_start=8)

heat_data = [[row['latitude'], row['longitude'], row['weak_grid_score']]
             for idx, row in high_priority_leads.iterrows()]

HeatMap(heat_data).add_to(m)
m.save('weak_grid_heatmap.html')
```

**C) CRM-integrasjon**
- API-endpoint for å hente nye leads daglig/ukentlig
- Automatisk import til eksisterende CRM (SuperOffice, HubSpot, etc.)
- Integrasjon med markedsføringskampanjer (Facebook Ads geo-targeting)

---

## 4. JURIDISKE & ETISKE HENSYN

### 4.1 GDPR / Personvern

**Situasjon:** GDPR (Personvernforordningen) gjelder i Norge via Personopplysningsloven.

**Kritiske spørsmål:**

**Q1: Er eiendomsdata med koordinater personopplysninger?**
- **Svar:** Ja, hvis de kan knyttes til en identifiserbar person.
- **Matrikkelen:** Inneholder ikke navn/personnummer, men eiendomsidentifikator kan slås opp mot offentlige grunnbøker.
- **Konklusjon:** Indirekte personopplysninger, men offentlig tilgjengelige.

**Q2: Kan vi lagre og prosessere disse dataene?**
- **Hjemmel:** Artikkel 6(1)(f) - Berettiget interesse (legitimate interest)
- **Betingelser:**
  - Interesseavveining: Norsk Solkrafts legitime forretningsinteresse vs. personens rett til privatliv
  - Formålet må være proporsjonalt (markedsføring av relevante tjenester)
- **Risiko:** Middels - kan utfordres av Datatilsynet hvis ikke dokumentert

**Q3: Kan vi kontakte personer basert på disse dataene?**
- **Direkte markedsføring:** Krever samtykke (GDPR art. 6(1)(a)) ELLER legitim interesse + opt-out
- **Beste praksis:**
  - Generell markedsføring i identifiserte geografiske områder (ingen personopplysninger)
  - Ikke kontakt individuelle eiendomseiere uten samtykke
- **Løsning:** Geo-targeted ads på Facebook/Google til postnummer med høy score

**Q4: Må vi anonymisere dataene?**
- **Anonymisering:** Fjerner personopplysninger permanent (ikke reversibelt)
- **Pseudonymisering:** Fjerner direkte identifikatorer (fortsatt GDPR-pliktig)
- **Vår tilnærming:** Pseudonymisering - bruk `property_id` uten navn/adresse

### 4.2 NVE Data Policies

**Status:** NVE data er offentlige, men med vilkår.

**Vilkår for bruk (fra NVE.no):**
- Fri bruk til ikke-kommersiell forskning og statistikk
- **Kommersiell bruk:** Tillatt, men med kildehenvisning
- **Ingen restriksjon:** På bruk til markedsføring eller forretningsutvikling
- **Konklusjon:** ✅ Lovlig å bruke KILE-data og nettstatistikk

### 4.3 Matrikkelen / Kartverket Policies

**Status:** Offentlige data, men med lisensavtale.

**Lisensvilkår:**
- **Geonorge lisens:** Norge digitalt lisens (åpen lisens for offentlige data)
- **Kommersiell bruk:** Tillatt
- **Videreformidling:** Tillatt med kildehenvisning
- **API-tilgang:** Krever avtale med Kartverket for bulk-nedlasting
- **Konklusjon:** ✅ Lovlig, men krever formell avtale for API

### 4.4 Etiske prinsipper

**Transparens:**
- Kunder skal kunne forstå hvordan de ble identifisert som potensielle leads
- Markedsføring skal være ærlig om datakildene

**Nøyaktighet:**
- Modellen kan gi falske positiver - ikke anta at alle i listen faktisk har svakt nett
- Kvalifiser leads grundig før kontakt

**Ikke-diskriminering:**
- Geografisk targeting må ikke ekskludere beskyttede grupper uforholdsmessig
- Pris og tilgjengelighet skal være lik for alle

**Dataminimering:**
- Lagre kun nødvendige data for formålet
- Slett data når de ikke lenger er relevante

### 4.5 Juridisk risikovurdering

| Aktivitet | Risiko | Mitigering |
|-----------|--------|------------|
| Lagring av eiendomsdata | 🟡 Middels | Dokumenter berettiget interesse, pseudonymiser |
| Bruk av offentlige data (NVE, SSB) | 🟢 Lav | Alltid kildehenvise, følg lisensvilkår |
| Geo-targeted markedsføring | 🟢 Lav | Ingen personopplysninger i annonsene |
| Direkte kontakt til eiendomseiere | 🔴 Høy | Kun med samtykke eller eksplisitt opt-out |
| Deling av data med tredjeparter | 🔴 Høy | IKKE del uten databehandleravtale |

**Anbefaling:**
1. Få juridisk rådgivning fra advokat med GDPR-kompetanse (budsjett: 50-100k NOK)
2. Utarbeid personvernerklæring og interesseavveining
3. Implementer opt-out mekanisme for markedsføring
4. Logg alle databehandlingsaktiviteter (audit trail)

---

## 5. IMPLEMENTERING: TEKNISK STACK & ROADMAP

### 5.1 Anbefalt teknologistack

**Data Processing & Analysis:**
- **Python 3.11+** (installert via conda)
- **pandas** - Dataframe manipulation
- **geopandas** - Geospatial data handling
- **shapely** - Geometrioperasjoner
- **pyproj** - Koordinattransformasjoner

**Geospatial:**
- **GDAL/OGR** - GIS format støtte (installert via conda)
- **Fiona** - File I/O for geopandas
- **Rasterio** - Raster data (høydedata)

**Visualization:**
- **folium** - Interaktive kart (Leaflet.js backend)
- **plotly** - Interaktive grafer
- **matplotlib/seaborn** - Statiske plots

**Machine Learning (v2.0):**
- **scikit-learn** - Classical ML (Random Forest, etc.)
- **xgboost/lightgbm** - Gradient boosting

**Database:**
- **PostgreSQL + PostGIS** - Geospatial database
- **SQLAlchemy** - ORM for Python

**Deployment:**
- **Docker** - Containerisering
- **Apache Airflow** - Workflow orchestration (for dataoppdateringer)
- **Flask/FastAPI** - Web API for CRM-integrasjon

### 5.2 Installasjon (via conda, per brukerens preferanse)

```bash
# Opprett miljø
conda create -n weak_grid_model python=3.11
conda activate weak_grid_model

# Installer pakker (prioriter conda-forge)
conda install -c conda-forge pandas geopandas shapely pyproj gdal fiona
conda install -c conda-forge folium plotly scikit-learn
conda install -c conda-forge psycopg2 sqlalchemy

# Hvis pakker ikke tilgjengelig i conda, bruk pip:
pip install openpyxl requests
```

### 5.3 Datakilder: API-integrasjoner

**A) NVE KILE-data (manuell nedlasting)**
```python
import pandas as pd

# Last ned fra NVE.no (manuelt, ingen API)
kile_url = "https://www.nve.no/Media/5678/KILE_2024.xlsx"
kile_df = pd.read_excel(kile_url, sheet_name="KILE per nettselskap")
```

**B) SSB API**
```python
import requests

# SSB API v2
ssb_api_url = "https://data.ssb.no/api/v0/no/table/11823"
params = {
    "query": [
        {"code": "Region", "selection": {"filter": "item", "values": ["4626", "4627"]}}
    ],
    "response": {"format": "json-stat2"}
}
response = requests.post(ssb_api_url, json=params)
data = response.json()
```

**C) Kartverket API (krever avtale)**
```python
from owslib.wfs import WebFeatureService

# WFS for Matrikkelen (eksempel - krever autentisering)
wfs = WebFeatureService(
    url="https://wfs.geonorge.no/skwms1/wfs.matrikkelenbygg",
    version="2.0.0",
    username="your_username",
    password="your_password"
)

# Hent bygninger i en bounding box
response = wfs.getfeature(
    typename="app:Bygning",
    bbox=(58.0, 7.0, 59.0, 9.0),  # lat/lon bounds
    outputFormat="json"
)
```

**D) NVE Atlas (WMS)**
```python
import geopandas as gpd

# Last kraftledninger via WMS (GeoJSON)
nve_wms_url = "https://gis3.nve.no/map/services/Kraftledninger/MapServer/WMSServer"
# Konverter til GeoJSON via QGIS eller direkte WFS-kall
power_lines_gdf = gpd.read_file("nve_kraftledninger.geojson")
```

### 5.4 Visualisering: Interaktivt kart

```python
import folium
from folium.plugins import MarkerCluster

# Opprett base map
m = folium.Map(location=[58.5, 8.0], zoom_start=8, tiles="OpenStreetMap")

# Lag MarkerCluster for å håndtere mange punkter
marker_cluster = MarkerCluster().add_to(m)

# Legg til leads som markers
for idx, row in high_priority_leads.iterrows():
    folium.Marker(
        location=[row['latitude'], row['longitude']],
        popup=f"Score: {row['weak_grid_score']}<br>Type: {row['building_type']}",
        icon=folium.Icon(color='red' if row['weak_grid_score'] > 80 else 'orange')
    ).add_to(marker_cluster)

# Lagre som HTML
m.save('weak_grid_leads_map.html')
```

### 5.5 CRM-integrasjon: API endpoint

```python
from flask import Flask, jsonify
import pandas as pd

app = Flask(__name__)

@app.route('/api/leads', methods=['GET'])
def get_leads():
    # Hent leads fra database/CSV
    leads_df = pd.read_csv('leads_high_priority.csv')

    # Konverter til JSON
    leads_json = leads_df.to_dict(orient='records')

    return jsonify(leads_json)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

### 5.6 Dataoppdatering: Apache Airflow DAG

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

def update_kile_data():
    # Last ned ny KILE-data fra NVE
    pass

def recalculate_scores():
    # Kjør scoring-pipeline på nytt
    pass

def export_leads():
    # Eksporter nye leads til CRM
    pass

default_args = {
    'owner': 'norsk_solkraft',
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'weak_grid_model_update',
    default_args=default_args,
    description='Monthly update of weak grid leads',
    schedule_interval='0 0 1 * *',  # 1st of every month
    start_date=datetime(2025, 1, 1),
    catchup=False,
)

t1 = PythonOperator(task_id='update_kile_data', python_callable=update_kile_data, dag=dag)
t2 = PythonOperator(task_id='recalculate_scores', python_callable=recalculate_scores, dag=dag)
t3 = PythonOperator(task_id='export_leads', python_callable=export_leads, dag=dag)

t1 >> t2 >> t3
```

---

## 6. CASE: PROOF OF CONCEPT - AGDER REGION

### 6.1 Geografisk scope

**Fokusområde:** Agder fylke (Vest-Agder + Aust-Agder)
- **Kommuner:** 25 (inkl. Kristiansand, Arendal, Grimstad, Flekkefjord, etc.)
- **Befolkning:** ~307,000
- **Hytter:** ~15,000 (estimat fra SSB)
- **Nettselskap:** Agder Energi Nett, Linea, andre mindre

**Rasjonale for valg:**
- Norsk Solkrafts hjemmebase (eksisterende markedskunnskap)
- Godt dokumentert nettinfrastruktur via Agder Energi
- Høy hyttetetthet i innlandet (Setesdal, Sirdal)

### 6.2 Tilgjengelige data AKKURAT NÅ

**✅ Tilgjengelig uten avtaler:**
1. **NVE KILE 2023** (siste publiserte år)
   - URL: https://www.nve.no/Media/17896/kile-2023-nettselskap.xlsx
   - Agder Energi Nett: SAIDI 82 min, SAIFI 1.2

2. **SSB Hytter 2024**
   - URL: https://www.ssb.no/statbank/table/11823/
   - Agder: 14,876 hytter (per kommune)

3. **Kartverket N50 Kartdata** (via Geonorge)
   - URL: https://kartkatalog.geonorge.no/metadata/n50-kartdata/ea192681-d039-42ec-b1bc-f3ce04c189ac
   - Format: GML, gratis nedlasting

**⚠️ Krever avtale (kan ikke startes umiddelbart):**
4. **Matrikkelen GAB** - Kartverket API
5. **Elhub** - Målerpunktdata (begrenset verdi uansett)

**🔴 Ikke tilgjengelig (må estimeres):**
6. Effekttilgang per eiendom
7. Transformatordata (noen nettselskap publiserer nettkart)

### 6.3 Minimal Viable Product (MVP) - Scope

**Mål:** Identifiser topp 500 hytter i Agder med høyest sannsynlighet for svakt nett.

**Input data:**
- NVE KILE-data (Agder Energi Nett)
- SSB hyttedata (antall per kommune)
- Kartverket bygningsdata (via manuell prosessering av N50)
- Manuelt digitaliserte kraftledninger (fra offentlige nettkart)

**Prosess:**
1. Last ned og prosesser NVE KILE (1 dag)
2. Last ned SSB hyttedata (1 dag)
3. Last ned Kartverket N50 for Agder (1 dag)
4. Digitaliser kraftledninger manuelt fra Agder Energis nettkart (3-5 dager)
5. Beregn geografiske distanser (1 dag)
6. Implementer scoringssystem (2 dager)
7. Visualiser på kart (1 dag)
8. Valider med eksisterende kunder (2 dager)

**Total estimert tid:** 12-15 arbeidsdager (2-3 uker for én person)

### 6.4 MVP Leveranser

**A) Datasett:**
- `agder_cabins_scored.csv` - 14,876 hytter med weak_grid_score
- `agder_top500_leads.csv` - Topp 500 prioriterte leads

**B) Visualisering:**
- `agder_weak_grid_heatmap.html` - Interaktivt kart med heatmap
- `agder_leads_map.html` - Kart med markers for topp 500

**C) Rapport:**
- Validering mot eksisterende Norsk Solkraft-kunder (precision/recall)
- Anbefaling for fase 2 (ML-modell)

### 6.5 Validering: Suksesskriterier

**Test mot eksisterende kunder:**
- Hent liste over Norsk Solkrafts offgrid-kunder i Agder (historiske)
- Sjekk hvor mange som ville blitt fanget opp av modellen (recall)
- Sjekk hvor mange av topp 500 som faktisk har svakt nett (precision - krever manuell validering)

**Mål:**
- **Recall ≥70%:** Modellen fanger opp minst 70% av faktiske "svakt nett"-kunder
- **Precision ≥40%:** Minst 40% av topp 500 leads er faktisk relevante (estimat, må valideres)

**Hvis MVP viser lovende resultater:** Gå videre til fase 2 med ML og full nasjonal dekning.

### 6.6 Estimert kostnad (intern tid + data)

| Aktivitet | Timer | Timepris (estimat) | Kostnad |
|-----------|-------|-------------------|---------|
| Data sourcing | 40 | 1,200 NOK | 48,000 NOK |
| Python development | 60 | 1,200 NOK | 72,000 NOK |
| Testing & validation | 20 | 1,200 NOK | 24,000 NOK |
| **Total intern tid** | **120** | | **144,000 NOK** |
| Kartverket API-avtale | - | - | 10,000 NOK (engangsavtale) |
| Juridisk rådgivning (GDPR) | - | - | 50,000 NOK |
| **Total MVP kostnad** | | | **~204,000 NOK** |

**Breakeven-analyse:**
- Hvis modellen genererer 50 nye offgrid-kunder
- Gjennomsnittlig ordrestørrelse: 50,000 NOK
- Margin: 30% = 15,000 NOK per kunde
- Total margin: 750,000 NOK
- **ROI:** 267% (750k / 204k)

---

## 7. ANBEFALING & NESTE STEG

### 7.1 Konklusjon: Er dette gjennomførbart?

**✅ JA** - men med følgende forbehold:

**Sterke sider:**
- Offentlige data er tilstrekkelige for geografisk og nettselskap-basert scoring
- Python-stack er moden og veldokumentert
- MVP kan leveres på 2-4 uker med intern ressurs
- Juridisk risiko er håndterbar med riktig tilnærming (geo-targeting, ikke direkte kontakt)

**Svake sider:**
- Mangler detaljerte nett-tekniske data på individnivå
- GDPR krever forsiktig håndtering (berettiget interesse må dokumenteres)
- Nøyaktighet vil være begrenset (estimert 60-70% precision) uten ML
- Krever kontinuerlig vedlikehold (dataoppdateringer)

### 7.2 Anbefalt tilnærming (faseinndelt)

**Fase 1: MVP (2-4 uker, ~200k NOK)**
- Bygg regelbasert scoringssystem for Agder
- Valider mot eksisterende kunder
- Lever topp 500 leads til salgsavdelingen
- **Beslutningspunkt:** Hvis recall >70%, gå til fase 2

**Fase 2: Nasjonal skalering (2-3 måneder, ~500k NOK)**
- Utvid til hele Norge (alle fylker)
- Inngå avtale med Kartverket for bulk API-tilgang
- Implementer ML-modell (Random Forest) trent på faktiske konverteringer
- Integrer med CRM (SuperOffice/HubSpot)
- **Beslutningspunkt:** Hvis conversion rate >10%, gå til fase 3

**Fase 3: Operasjonalisering (løpende)**
- Automatiser dataoppdateringer (Apache Airflow)
- Implementer feedback-loop (konverteringer → modelltrening)
- Utvid til andre segmenter (gårdsbruk, telekom-master)
- Integrer med markedsføringsautomatisering (geo-targeted ads)

### 7.3 Kritiske suksessfaktorer

1. **Få juridisk avklaring tidlig:** GDPR-rådgivning MÅ gjøres før oppstart
2. **Samarbeid med salgsavdelingen:** Validering av leads krever domenekunnskap
3. **Datakvalitet > Datakantitet:** Fokuser på nøyaktige indikatorer framfor mange upålitelige
4. **Iterativ utvikling:** Start enkelt, forbedre basert på faktiske resultater

### 7.4 Neste konkrete steg (neste 2 uker)

**Uke 1:**
- [ ] Få juridisk avklaring fra advokat (GDPR + Kartverket-lisens) - **Kritisk**
- [ ] Last ned NVE KILE 2023 for alle nettselskap
- [ ] Last ned SSB hyttedata for Agder
- [ ] Last ned Kartverket N50 for Agder (bygninger)
- [ ] Oppsett av Python-miljø (conda + geopandas)

**Uke 2:**
- [ ] Implementer geografisk distanseberegning (kraftledninger)
- [ ] Implementer scoringssystem (versjon 1.0)
- [ ] Generer topp 500 leads for Agder
- [ ] Lag interaktivt kart (Folium)
- [ ] Valider mot 20-30 eksisterende kunder (manuelt)

**Beslutningspunkt:** Hvis validering viser >60% recall, godkjenn budsjett for fase 2.

### 7.5 Risikoreduserende tiltak

| Risiko | Sannsynlighet | Konsekvens | Mitigering |
|--------|--------------|------------|------------|
| GDPR-klage til Datatilsynet | Lav | Høy | Juridisk rådgivning + dokumentert interesseavveining |
| Lav modellnøyaktighet (<50%) | Middels | Middels | Start med MVP-validering før full investering |
| Datatilgang blokkert (API) | Lav | Middels | Bruk offentlige bulk-filer som backup |
| Teknisk kompleksitet overskrides | Lav | Lav | Start med enkel regelbasert modell |

---

## 8. OPPSUMMERING: EXECUTIVE SUMMARY

**Spørsmål:** Kan vi bygge en datamodell som identifiserer kunder med svakt nett i Norge?

**Svar:** **JA, men start med geografisk targeting, ikke individkontakt.**

**Anbefalinger:**
1. **Bygg MVP i Agder (2-4 uker, ~200k NOK)** med regelbasert scoring
2. **Bruk geografisk markedsføring** (Facebook/Google ads til postnummer) - ikke direkte kontakt
3. **Få juridisk avklaring** før oppstart (GDPR + Kartverket-lisens)
4. **Valider tidlig** mot eksisterende kunder før nasjonal skalering
5. **Iterer basert på faktiske resultater** - ikke bygg alt på én gang

**Forventet ROI:** 250-300% hvis modellen genererer 50+ nye kunder i år 1.

**Tidslinje til første leads:** 4 uker fra oppstart.

**Kritisk suksessfaktor:** Juridisk avklaring MÅ være på plass før datainnsamling starter.

---

## VEDLEGG A: Python-script for MVP (pseudo-kode)

```python
"""
Minimal Viable Product: Weak Grid Lead Generator for Agder
"""

import pandas as pd
import geopandas as gpd
from shapely.geometry import Point
import folium
from folium.plugins import HeatMap

# --- STEG 1: LAST DATA ---

# NVE KILE-data
kile_df = pd.read_excel("nve_kile_2023.xlsx")
agder_energi_kile = kile_df[kile_df['Nettselskap'] == 'Agder Energi Nett AS'].iloc[0]

# SSB hyttedata (manuelt lastet ned fra Statbank)
ssb_cabins_df = pd.read_csv("ssb_cabins_agder.csv")  # Kolonner: kommune, antall_hytter

# Kartverket bygninger (prosessert N50 data)
# Anta vi har en CSV med: latitude, longitude, building_type
buildings_df = pd.read_csv("kartverket_bygninger_agder.csv")

# Kraftledninger (manuelt digitalisert fra Agder Energis nettkart)
power_lines_gdf = gpd.read_file("agder_energi_kraftledninger.geojson")

# --- STEG 2: KONVERTER TIL GEODATAFRAME ---

buildings_gdf = gpd.GeoDataFrame(
    buildings_df,
    geometry=gpd.points_from_xy(buildings_df.longitude, buildings_df.latitude),
    crs="EPSG:4326"
)

# Filtrer til kun fritidsboliger
cabins_gdf = buildings_gdf[buildings_gdf['building_type'] == 'fritidsbolig'].copy()

# --- STEG 3: BEREGN GEOGRAFISKE INDIKATORER ---

# Avstand til nærmeste kraftledning
cabins_gdf['dist_to_power_line_m'] = cabins_gdf.geometry.apply(
    lambda point: power_lines_gdf.distance(point).min() * 111320  # Grader til meter (approx)
)

# Antall naboer innen 500m
def count_neighbors(point, gdf, radius_m=500):
    buffer = point.buffer(radius_m / 111320)  # Meter til grader
    return len(gdf[gdf.geometry.within(buffer)]) - 1  # Ekskluder seg selv

cabins_gdf['neighbors_500m'] = cabins_gdf.geometry.apply(
    lambda p: count_neighbors(p, cabins_gdf, radius_m=500)
)

# --- STEG 4: SCORINGSSYSTEM ---

def calculate_weak_grid_score(row, kile_saidi):
    score = 0

    # Geografiske faktorer (40p)
    if row['dist_to_power_line_m'] > 1000:
        score += 15
    elif row['dist_to_power_line_m'] > 500:
        score += 8

    if row['neighbors_500m'] < 5:
        score += 10
    elif row['neighbors_500m'] < 20:
        score += 5

    # Nettselskap faktorer (30p) - samme for alle i Agder Energi
    if kile_saidi > 180:
        score += 15
    elif kile_saidi > 60:
        score += 8

    # Eiendomsfaktorer (30p) - alle er fritidsboliger i dette datasettet
    score += 20  # Fritidsbolig = automatisk 20p

    return score

cabins_gdf['weak_grid_score'] = cabins_gdf.apply(
    lambda row: calculate_weak_grid_score(row, agder_energi_kile['SAIDI_minutes']),
    axis=1
)

# --- STEG 5: PRIORITERING ---

top_500_leads = cabins_gdf.nlargest(500, 'weak_grid_score')

# Eksporter til CSV
top_500_leads[['latitude', 'longitude', 'weak_grid_score', 'dist_to_power_line_m']].to_csv(
    'agder_top500_leads.csv', index=False
)

# --- STEG 6: VISUALISERING ---

# Interaktivt kart med Folium
m = folium.Map(location=[58.5, 7.5], zoom_start=9)

# HeatMap over alle hytter
heat_data = [[row.geometry.y, row.geometry.x, row['weak_grid_score']]
             for idx, row in cabins_gdf.iterrows()]
HeatMap(heat_data).add_to(m)

# Markers for topp 100
for idx, row in top_500_leads.head(100).iterrows():
    folium.Marker(
        location=[row.geometry.y, row.geometry.x],
        popup=f"Score: {row['weak_grid_score']}<br>Dist: {row['dist_to_power_line_m']:.0f}m",
        icon=folium.Icon(color='red' if row['weak_grid_score'] > 80 else 'orange')
    ).add_to(m)

m.save('agder_weak_grid_leads_map.html')

print(f"✅ Generert {len(top_500_leads)} leads med gjennomsnittlig score {top_500_leads['weak_grid_score'].mean():.1f}")
```

---

## VEDLEGG B: Relevante lenker & ressurser

**Offentlige datakilder:**
- NVE KILE-data: https://www.nve.no/energi/energisystem/kraftmarkedet/kile/
- NVE Atlas (kartdata): https://atlas.nve.no/
- SSB Statbank: https://www.ssb.no/statbank/
- Kartverket Geonorge: https://kartkatalog.geonorge.no/
- Elhub: https://elhub.no/elhub-api/

**Python-biblioteker:**
- Geopandas: https://geopandas.org/
- Folium: https://python-visualization.github.io/folium/
- Scikit-learn: https://scikit-learn.org/

**GDPR & Personvern:**
- Datatilsynet: https://www.datatilsynet.no/
- GDPR artikkel 6 (lovlige grunnlag): https://gdpr-info.eu/art-6-gdpr/

**Kontaktpersoner (foreslått):**
- Juridisk rådgiver: GDPR-spesialist advokat
- Kartverket: API-tilgang for Matrikkelen
- Datatilsynet: Veiledning om berettiget interesse

---

**Rapport utarbeidet av:** Claude (Anthropic AI)
**Dato:** 3. november 2025
**Versjon:** 1.0
**Status:** Klar for beslutning om MVP-oppstart
