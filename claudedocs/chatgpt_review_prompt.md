# ChatGPT-4 Review Request: Weak Grid Analytics MVP

**Instructions for use**: Copy this entire prompt and paste it into ChatGPT-4 (use GPT-4 model, not GPT-3.5, for best results).

---

I need a critical technical and business review of an analytics MVP design. Please be thorough and identify potential problems - validation is less useful than constructive criticism.

## PROJECT CONTEXT

**Company**: Norsk Solkraft (Norwegian solar installation company)
**Goal**: Identify potential customers for hybrid solar + battery systems in areas with weak electrical grids
**MVP Scope**: Agder region (15,000 cabin properties), then scale nationally (90,000+ properties)
**Timeline**: 2-4 weeks for MVP, Phase 2 in 2-3 months, Phase 3 at month 12+
**Budget**: 200k NOK MVP, 455k NOK Phase 2

---

## KEY DESIGN DECISIONS

### 1. Database Architecture
**Decision**: SQLite + SpatiaLite (not PostgreSQL/PostGIS)

**Rationale**:
- MVP has only 15k records (small scale)
- Simpler setup, no server infrastructure needed
- Migrate to PostgreSQL when scaling past 40k properties in Phase 2

**Question**: Is this a sound choice or are we creating technical debt?

---

### 2. GDPR/Legal Strategy
**Decision**: Aggregate scoring by postal code area (not individual property targeting)

**Rationale**:
- Individual property scoring + direct marketing = insufficient legitimate interest under GDPR
- Must use geo-targeted digital ads instead of personalized outreach
- Public data (building locations, grid statistics) OK for aggregation, not for individual profiling

**Question**: Is this interpretation conservative enough? Legal risks we're missing?

---

### 3. Scoring Model
**Formula**: `weak_grid_score = 0.4×KILE + 0.3×distance_to_town + 0.2×terrain + 0.1×municipality_rank`

**Components**:
- **40% KILE**: Grid outage hours/year per municipality (from NVE - Norwegian grid authority)
- **30% distance to nearest town center**: Proxy for power line distance (actual power line data unavailable)
- **20% terrain elevation**: Mountains = harder grid access, more remote distribution lines
- **10% municipality historical trends**: Grid quality improvement/degradation over time

**Question**: Are these weights reasonable? Is "distance to town" a valid proxy for actual power line distance?

---

### 4. Data Sources

**Using**:
- **Kartverket N50**: Building locations, terrain elevation
- **NVE KILE**: Grid outage statistics by municipality (official government data)
- **SSB**: Validation data (Norwegian statistics bureau)

**Skipping for MVP**:
- **Matrikkelen** (property registry with owner data) - requires 2-4 week data agreement, deferred to Phase 2
- **Actual power line mapping** - data incomplete/requires grid company cooperation, may never be available

**Proxy Strategy**: Distance to town center as substitute for actual power line distance

**Question**: Are we over-relying on proxies? How to validate this doesn't break the model?

---

### 5. Machine Learning vs. Rules
**Decision**: Rule-based scoring for MVP, defer ML to Phase 2

**Rationale**:
- No historical conversion data to train supervised ML (no labels for "weak grid" vs "strong grid")
- Need sales cycle data (conversions, rejections) before building Random Forest model
- Simple weighted scoring easier to explain to sales team and debug
- Can tune weights based on Phase 1 feedback before investing in ML

**Question**: Should we use unsupervised ML (clustering) even without labels? When to introduce ML?

---

### 6. Phasing Strategy

**MVP (Phase 1)**: 2-4 weeks, 200k NOK
- Agder region only (15k properties)
- CSV export (no CRM integration)
- Rule-based scoring
- SQLite database
- Manual sales workflow

**Phase 2**: 2-3 months, 455k NOK
- National scaling (90k properties)
- PostgreSQL migration
- Still CSV export (defer CRM API integration)
- Improved scoring with Phase 1 learnings
- Possible ML introduction if conversion data sufficient

**Phase 3**: Month 12+
- CRM API integration (HubSpot or similar)
- Random Forest ML model (trained on conversion data)
- Apache Airflow automation for monthly updates
- Real-time grid data integration

**Question**: Is this "prove value first" phasing logical or are we deferring critical features?

---

## VALIDATION STRATEGY

**Target Metrics**:
- **Recall ≥70%**: Find 70%+ of actual weak grid properties
- **Precision ≥40%**: 40%+ of high-scored properties actually have weak grids

**Validation Approach**:
1. Manual spot-checking (Google Maps satellite view, local knowledge)
2. Cross-reference with SSB demographics (cabin density correlates with weak grids)
3. A/B test marketing campaigns (high-score postal codes vs. random control)
4. Sales team feedback after 3 months (conversion rates, rejection reasons)

---

## SPECIFIC QUESTIONS FOR REVIEW

### Technical Architecture
1. Is SQLite sufficient for 15k geospatial records or does this create scaling problems?
2. GeoPandas performance concerns for distance calculations at this scale?
3. Better tech stack alternatives (Python + GeoPandas + SQLite/SpatiaLite)?

### Scoring Model
4. Are the scoring weights (40/30/20/10) informed by domain knowledge or arbitrary?
5. Will "distance to town" correlate enough with actual weak grid reality?
6. What critical features are we missing?

### Risk Assessment
7. What could go catastrophically wrong that we haven't considered?
8. **Regional bias**: Model designed for Agder (southern coastal), applied to Finnmark (Arctic, very different grid infrastructure)?
9. **False positive scenarios**: High score but strong grid (e.g., mountain cabin near hydropower plant)?
10. **False negative scenarios**: Weak grid but low score (e.g., coastal island with ferry access)?

### Validation
11. Are target metrics (70% recall, 40% precision) realistic or optimistic?
12. How to validate the model BEFORE deploying to sales team?
13. If underperforming, what are quick fixes vs. full redesign?

### Norwegian Context
14. Anything culturally/legally specific to Norway we're underestimating?
15. GDPR legitimate interest for marketing - too cautious or not cautious enough?

---

## REQUESTED OUTPUT

Please provide:

### 1. STRENGTHS (2-3 points)
- What's well-designed?
- Smart trade-offs identified?

### 2. RISKS (3-5 points)
- Technical risks (architecture, scalability, data quality)
- Business risks (scoring accuracy, market fit, sales adoption)
- Legal risks (GDPR, data usage)

### 3. BLIND SPOTS (2-3 points)
- What haven't we thought about?
- Edge cases that could break the model?
- Assumptions that might be wrong?

### 4. RECOMMENDATIONS (3-5 actionable items)
- **Quick wins**: Add to MVP, <1 day effort
- **Phase 2 must-haves**: Critical for scaling
- **Alternative approaches**: Worth considering

### 5. OVERALL ASSESSMENT
- **Confidence score** (0-100%) this MVP will succeed
- **Biggest single risk factor** (1-2 sentences)
- **Go/no-go recommendation** with rationale

---

## STYLE GUIDANCE

Please be critical and specific. Generic advice like "test thoroughly" is less useful than "your distance-to-town proxy will fail for coastal grids because distribution lines follow fjords, not straight lines - consider coastal distance as separate factor."

Focus on actionable insights that will improve the design or prevent failure.
