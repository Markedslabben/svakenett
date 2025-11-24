# E-post til NVE om datakvalitet i Nettanlegg4

---

**Til:** nve@nve.no
**Kopi:** (geodata@nve.no hvis det finnes)
**Emne:** Datakvalitet i Nettanlegg4 - Områdekonsesjonærer (MapServer Layer 6)

---

## E-post (norsk):

Hei,

Jeg jobber med et prosjekt som analyserer egnethet for nettfrie hytter i Norge, og benytter NVEs Nettanlegg4-datasett (ArcGIS REST Services) for å kartlegge nettselskaps områdekonsesjoner.

Ved bruk av dataene har jeg oppdaget betydelige datakvalitetsproblemer i Layer 6 (Områdekonsesjonærer) som jeg ønsker å rapportere:

### 1. Feil plassering av områdepolygon - Glitre Nett AS

**Nettselskap:** Glitre Nett AS (organisasjonsnummer: 982974011)

**Problem:**
Service area-polygonet for Glitre Nett AS er plassert i feil geografisk område.

**Forventet plassering (basert på faktiske områdekonsesjoner):**
- Agder fylke (sørlige deler)
- Kommuner: Lyngdal, Mandal, Farsund, m.fl.
- Omtrentlig breddegrad: 58.0 - 58.7
- Omtrentlig lengdegrad: 7.0 - 8.5

**Faktisk plassering i NVE-datasettet:**
- Breddegrad: 59.41 - 59.78 (nordøst for Oslo)
- Lengdegrad: 9.33 - 10.06 (østlige deler)
- **Avstand fra korrekt område: ~95 km**

Dette stemmer ikke overens med Glitre Netts faktiske områdekonsesjon.

### 2. Manglende dekningsområde - Sørlige Agder

**Problem:**
Det er et betydelig geografisk gap i service area-dekningsområdet for sørlige Agder.

**Detaljer:**
- Området mellom breddegrad 58.0 og 58.88 (sørlige kysten av Agder) mangler dekning
- Nærmeste service area-polygoner starter ved breddegrad 58.88+ (Telemark Nett AS m.fl.)
- Dette området omfatter kommuner som Lyngdal, Mandal, Farsund, og deler av Åseral
- Geografisk gap på 15-20 km mellom faktiske installasjoner og nærmeste kartlagte område

**Konsekvens:**
Ved bruk av PostGIS spatial join (`ST_Within`) for å matche geografiske punkter til nettselskaps områder, får vi 0% dekning for 37 170 hytter i Agder-regionen, selv om vi vet at disse har nettilknytning gjennom eksisterende nettselskap.

### 3. Bruk av dataene

**Vår bruk:**
- Datasett: `Nettanlegg4/MapServer/6/query`
- Filter: `EIERTYPE='EVERK'`
- Format: GeoJSON med EPSG:4326
- URL: https://nve.geodataonline.no/arcgis/rest/services/Nettanlegg4/MapServer/6

**Testing utført:**
- Nedlastet 88 områdepolygoner
- Lastet inn i PostgreSQL/PostGIS database
- Utført spatial join mot 37 170 hyttepunkter i Agder
- Resultat: 0 treff på grunn av geografisk gap

**Verifisering:**
```sql
-- Test av Glitre Nett polygon
SELECT
    ST_XMin(service_area_polygon) as min_lon,
    ST_XMax(service_area_polygon) as max_lon,
    ST_YMin(service_area_polygon) as min_lat,
    ST_YMax(service_area_polygon) as max_lat
FROM grid_companies
WHERE company_code = '982974011';

-- Resultat: lon 9.33-10.06, lat 59.41-59.78 (feil område)
```

### Forespørsel

Jeg ønsker å be om:

1. **Korrigering av Glitre Nett AS polygon** - Flytt til korrekt geografisk område (sørlige Agder)

2. **Oppdatering av dekningsområdet** - Sikre fullstendig dekning for områdekonsesjonærer i Agder fylke, spesielt for breddegrad 58.0-58.88

3. **Tidsestimat** - Når kan vi forvente oppdatert datasett i Nettanlegg4 MapServer?

4. **Alternativ datakilde** - Finnes det et alternativt/oppdatert datasett for nettselskaps områdekonsesjoner vi kan benytte i mellomtiden?

### Kontaktinformasjon

[DITT NAVN]
[DIN E-POST]
[DIN ORGANISASJON/PROSJEKT]
[TELEFONNUMMER]

### Vedlegg

Jeg kan på forespørsel levere:
- Detaljert geografisk analyse med kart
- SQL-spørringer som dokumenterer problemet
- Liste over berørte kommuner og nettselskap
- GeoJSON-eksport av testdata

Takk for oppmerksomheten, og jeg ser frem til tilbakemelding.

Med vennlig hilsen,
[DITT NAVN]

---

## English Translation (for reference):

**Subject:** Data Quality Issues in Nettanlegg4 - Area Concession Holders (MapServer Layer 6)

Hello,

I'm working on a project analyzing suitability for off-grid cabins in Norway, using NVE's Nettanlegg4 dataset (ArcGIS REST Services) to map grid company area concessions.

While using the data, I've discovered significant data quality issues in Layer 6 (Area Concession Holders) that I wish to report:

### 1. Incorrect Placement - Glitre Nett AS

**Grid Company:** Glitre Nett AS (organization number: 982974011)

**Problem:**
The service area polygon for Glitre Nett AS is placed in the wrong geographic area.

**Expected Location (based on actual area concessions):**
- Agder county (southern parts)
- Municipalities: Lyngdal, Mandal, Farsund, etc.
- Approximate latitude: 58.0 - 58.7
- Approximate longitude: 7.0 - 8.5

**Actual Location in NVE Dataset:**
- Latitude: 59.41 - 59.78 (northeast of Oslo)
- Longitude: 9.33 - 10.06 (eastern parts)
- **Distance from correct area: ~95 km**

This doesn't match Glitre Nett's actual area concession.

### 2. Missing Coverage Area - Southern Agder

**Problem:**
There's a significant geographic gap in service area coverage for southern Agder.

**Details:**
- Area between latitude 58.0 and 58.88 (southern Agder coast) lacks coverage
- Nearest service area polygons start at latitude 58.88+ (Telemark Nett AS, etc.)
- This area includes municipalities like Lyngdal, Mandal, Farsund, and parts of Åseral
- Geographic gap of 15-20 km between actual installations and nearest mapped area

**Consequence:**
Using PostGIS spatial join (`ST_Within`) to match geographic points to grid company areas, we get 0% coverage for 37,170 cabins in the Agder region, even though we know these have grid connections through existing grid companies.

### Request

I would like to request:

1. **Correction of Glitre Nett AS polygon** - Move to correct geographic area (southern Agder)

2. **Update of coverage area** - Ensure complete coverage for area concession holders in Agder county, especially for latitude 58.0-58.88

3. **Timeline estimate** - When can we expect an updated dataset in Nettanlegg4 MapServer?

4. **Alternative data source** - Is there an alternative/updated dataset for grid company area concessions we can use in the meantime?

---

## Instructions for Sending:

1. **Fill in your contact information** in the Norwegian version
2. **Add any specific project details** if relevant
3. **Consider adding screenshots/maps** showing the gap visually
4. **Send to:** nve@nve.no (main contact)
5. **CC if possible:** geodata contact if you can find it on nve.no/kontakt

## Follow-up Actions:

- Wait 5-7 business days for initial response
- Be prepared to provide technical documentation if requested
- Consider reaching out to Glitre Nett directly for their official service area boundaries
- In parallel, develop municipality-based fallback for more accurate assignment

---

**Created:** 2025-11-22
**Project:** Svakenett (Weak Grid) Analysis
**Data Source:** NVE Nettanlegg4 MapServer Layer 6
