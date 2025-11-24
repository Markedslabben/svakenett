# Quick Start - Svakenett MVP

Get running in 5 minutes.

---

## 1. Start PostgreSQL

```bash
docker-compose up -d
```

Wait 10 seconds for health check to pass.

---

## 2. Install Dependencies

```bash
poetry install
poetry shell
```

---

## 3. Verify Setup

```bash
python scripts/setup_check.py
```

Expected: All 6 checks should pass ✅

---

## 4. Test Database Connection

```bash
python -c "from svakenett.db import test_connection; test_connection()"
```

Expected output:
```
✓ PostGIS connection successful: 3.4.0
✓ Connected to database: svakenett
```

---

## 5. Explore Database

```bash
# Connect via psql
docker exec -it svakenett-postgis psql -U postgres -d svakenett

# Inside psql:
\dt                  # List tables
\d cabins            # Describe cabins table
SELECT PostGIS_Version();  # Check PostGIS version
\q                   # Quit
```

---

## 6. Connect QGIS (Optional)

1. Open QGIS
2. Layer → Add PostGIS Layers → New
3. Connection details:
   - Host: `localhost`
   - Port: `5432`
   - Database: `svakenett`
   - User: `postgres`
   - Password: `weakgrid2024`
4. Test Connection → OK → Add `cabins` table

---

## Next: Data Acquisition

Download Kartverket N50 data:
- Visit: https://kartkatalog.geonorge.no/
- Search: "N50 Kartdata"
- Download: GeoJSON for Agder
- Save to: `data/raw/n50_buildings_agder.geojson`

See `SETUP_INSTRUCTIONS.md` for detailed guidance.

---

## Troubleshooting

**Docker not running?**
```bash
docker --version
docker ps
```

**Port 5432 in use?**
Change port in `docker-compose.yml` to `5433:5432`

**Python import errors?**
```bash
poetry install
poetry shell
```

---

**Status**: ✅ Infrastructure ready for development

**Timeline**: Day 1 complete, Day 2-7 data acquisition next
