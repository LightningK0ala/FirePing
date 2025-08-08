# NASA FIRMS Data Reference

## Overview

This document provides implementation guidance for ingesting and processing NASA FIRMS fire detection data based on NASA's official Python tutorial. This reference ensures our FirePing implementation follows NASA's best practices for data handling.

## Data Sources

### NASA FIRMS API Endpoints

**Data Availability Check**:
- **Purpose**: Check which dates have processed data available
- **All Sources**: `https://firms.modaps.eosdis.nasa.gov/api/data_availability/csv/{API_KEY}/ALL`
- **VIIRS S-NPP**: `https://firms.modaps.eosdis.nasa.gov/api/data_availability/csv/{API_KEY}/VIIRS_SNPP_NRT`
- **VIIRS NOAA-20**: `https://firms.modaps.eosdis.nasa.gov/api/data_availability/csv/{API_KEY}/VIIRS_NOAA20_NRT`
- **VIIRS NOAA-21**: `https://firms.modaps.eosdis.nasa.gov/api/data_availability/csv/{API_KEY}/VIIRS_NOAA21_NRT`
- **Returns**: CSV with date ranges and processing status for specified source(s)

**VIIRS Constellation (Modern Fire Detection)**:

**VIIRS S-NPP (Suomi National Polar-orbiting Partnership)**:
- **Resolution**: 375m
- **Orbit**: Sun-synchronous polar, 1:30 PM/AM equator crossing
- **Endpoint**: `https://firms.modaps.eosdis.nasa.gov/api/area/csv/{API_KEY}/VIIRS_SNPP_NRT/world/1`

**VIIRS NOAA-20 (Joint Polar Satellite System)**:
- **Resolution**: 375m  
- **Orbit**: Sun-synchronous polar, 1:30 PM/AM equator crossing (opposite S-NPP)
- **Endpoint**: `https://firms.modaps.eosdis.nasa.gov/api/area/csv/{API_KEY}/VIIRS_NOAA20_NRT/world/1`

**VIIRS NOAA-21 (Joint Polar Satellite System)**:
- **Resolution**: 375m
- **Orbit**: Sun-synchronous polar, 1:30 PM/AM equator crossing (50 min ahead of S-NPP)
- **Endpoint**: `https://firms.modaps.eosdis.nasa.gov/api/area/csv/{API_KEY}/VIIRS_NOAA21_NRT/world/1`

**MODIS (Legacy - Deprecated)**:
- **Status**: ⚠️ End of life - Terra (1999) and Aqua (2002) satellites aging
- **Resolution**: 1km (lower than VIIRS 375m)
- **Recommendation**: Migrate to VIIRS constellation for better coverage and resolution

### Data Versions and Processing Delays

- **NRT (Near Real Time)**: Standard processing, 3-6 hour delay
- **URT (Ultra Real Time)**: Rapid processing, 1-minute delay (US/Canada only)
- **RT (Real Time)**: Intermediate processing, 30-minute delay

### Data Availability Considerations

**Important**: NASA FIRMS data is not immediately available due to satellite processing delays. An empty API response can mean either:
1. **No fires detected** in the requested time period/area
2. **Data not yet processed** for the requested date

**Best Practice**: Check data availability before fetching fire data to distinguish between these scenarios and avoid unnecessary API calls.

## VIIRS Constellation Benefits

### Superior Coverage

**6 Daily Passes** over most locations:
- **3 daytime passes** (1:30 PM local time)
- **3 nighttime passes** (1:30 AM local time)
- **Coordinated timing**: NOAA-21 leads S-NPP by 50 minutes, NOAA-20 opposite S-NPP

**Orbital Configuration**:
```
S-NPP ←→ NOAA-20 (opposite orbits)
    ↕
 NOAA-21 (50 min ahead of S-NPP)
```

### Technical Advantages

**Higher Resolution**: 375m vs MODIS 1km
- Nearly **3x more precise** fire location data
- **Earlier detection** of smaller fires  
- **Better discrimination** between fires and hot surfaces

**Modern Satellites**:
- **S-NPP**: Launched 2011, proven reliability
- **NOAA-20**: Launched 2017, current generation
- **NOAA-21**: Launched 2022, newest technology

**Consistent Processing**:
- All satellites use identical **VIIRS instruments**
- Same **detection algorithms** across constellation
- **Standardized data formats** for easy integration

### FirePing Implementation Impact

**More Frequent Detection**: Up to 6 passes per day means fires detected ~4 hours sooner on average

**Better Accuracy**: 375m resolution means more precise location data for user alerts

**Reliability**: 3-satellite redundancy ensures continued service if one satellite fails

**Future-Proof**: JPSS program guarantees data continuity through 2030+

## CSV Data Format

### Column Structure (14 fields)

| Column | Type | Description | Example | Notes |
|--------|------|-------------|---------|-------|
| `latitude` | float64 | Fire location latitude | `34.0522` | -90 to 90 degrees |
| `longitude` | float64 | Fire location longitude | `-118.2437` | -180 to 180 degrees |
| `bright_ti4` | float64 | Brightness temperature I-4 | `302.5` | Kelvin |
| `scan` | float64 | Scan pixel size | `1.2` | Kilometers |
| `track` | float64 | Track pixel size | `1.1` | Kilometers |
| `acq_date` | string | Acquisition date | `2023-07-12` | YYYY-MM-DD format |
| `acq_time` | int64 | Acquisition time | `1842` | HHMM format (GMT) |
| `satellite` | string | Satellite identifier | `Terra` | N, A, T |
| `instrument` | string | Instrument name | `VIIRS` | MODIS, VIIRS |
| `confidence` | string | Detection confidence | `n` | n=normal, h=high, l=low |
| `version` | string | Data version | `2.0NRT` | 2.0NRT, 2.0URT |
| `bright_ti5` | float64 | Brightness temperature I-5 | `289.1` | Kelvin |
| `frp` | float64 | Fire Radiative Power | `12.4` | MW (Megawatts) |
| `daynight` | string | Day/night flag | `D` | D=day, N=night |

## Data Quality Filtering

### Recommended Filters (from NASA tutorial)

```javascript
// Quality thresholds based on NASA recommendations
const QUALITY_FILTERS = {
  confidence: ['n', 'h'],           // Normal and high confidence only
  confidence_threshold: 70,         // For numeric confidence (MODIS)
  min_frp: 5,                      // Minimum Fire Radiative Power (MW)
  coordinate_bounds: {
    latitude: { min: -90, max: 90 },
    longitude: { min: -180, max: 180 }
  }
};

// Example filtering logic
function isHighQualityFire(fire) {
  return (
    fire.confidence >= 70 &&           // High confidence
    fire.latitude >= -90 && fire.latitude <= 90 &&
    fire.longitude >= -180 && fire.longitude <= 180 &&
    !isNaN(fire.latitude) && !isNaN(fire.longitude) &&
    fire.frp >= 5                     // Significant fire power
  );
}
```

## DateTime Processing

### NASA's Recommended Approach

```javascript
// Convert NASA date/time format to ISO datetime
function parseNASADateTime(acq_date, acq_time) {
  // acq_date: "2023-07-12" 
  // acq_time: 1842 (integer)
  
  // Pad time to 4 digits: 1842 -> "1842", 85 -> "0085"
  const timeStr = String(acq_time).padStart(4, '0');
  
  // Create ISO datetime string
  const dateTimeStr = `${acq_date}T${timeStr.slice(0, 2)}:${timeStr.slice(2, 4)}:00Z`;
  
  return new Date(dateTimeStr);
}

// Example usage
const detectionTime = parseNASADateTime("2023-07-12", 1842);
// Result: 2023-07-12T18:42:00Z
```

### Timezone Considerations

All NASA FIRMS data is provided in **GMT/UTC**. For user notifications, consider converting to local timezone:

```javascript
// Example timezone conversion (conceptual)
function convertToLocalTime(utcDateTime, userTimezone) {
  // Convert GMT to user's local timezone
  // Implementation depends on timezone library
  return convertTimezone(utcDateTime, 'GMT', userTimezone);
}
```

## Geographic Subsetting

### Regional Bounding Boxes (from NASA)

```javascript
// NASA's regional coordinate examples
const REGIONAL_BOUNDS = {
  canada: {
    west: -150, south: 40,
    east: -49, north: 79
  },
  usa_hawaii: {
    west: -160.5, south: 17.5,
    east: -63.8, north: 50
  },
  australia_nz: {
    west: 110, south: -55,
    east: 180, north: -10
  }
};

// Subsetting function
function filterByRegion(fires, bounds) {
  return fires.filter(fire => 
    fire.longitude >= bounds.west &&
    fire.longitude <= bounds.east &&
    fire.latitude >= bounds.south &&
    fire.latitude <= bounds.north
  );
}
```

## Data Deduplication Strategy

### NASA's Approach

Since MODIS and VIIRS may detect the same fire, deduplication is essential:

```javascript
function deduplicateFires(modisData, viirsData) {
  const allFires = [...modisData, ...viirsData];
  const uniqueFires = new Map();
  
  for (const fire of allFires) {
    // Create location-based key (~500m precision)
    const locationKey = `${Math.round(fire.latitude * 1000)}_${Math.round(fire.longitude * 1000)}`;
    
    // Keep highest confidence fire for each location
    const existing = uniqueFires.get(locationKey);
    if (!existing || fire.confidence > existing.confidence) {
      uniqueFires.set(locationKey, fire);
    }
  }
  
  return Array.from(uniqueFires.values());
}
```

## Implementation Checklist for FirePing

### ✅ Data Ingestion
- [x] NASA FIRMS API integration
- [x] MODIS and VIIRS data fetching
- [x] CSV parsing and validation
- [x] Error handling for API failures

### ✅ Data Processing
- [x] DateTime conversion from NASA format
- [x] Quality filtering (confidence >= 70)
- [x] Geographic coordinate validation
- [x] Fire Radiative Power filtering

### ✅ Data Storage
- [x] Unique NASA ID generation for deduplication
- [x] Fire incident record creation
- [x] Duplicate prevention with database constraints

### ✅ Geospatial Processing
- [x] Haversine distance calculation
- [x] Location radius checking
- [x] Geographic bounds validation

### 🔄 Recommended Enhancements
- [ ] **Data availability checking** before fire data requests
- [ ] **Smart polling** - avoid requests when data isn't ready
- [ ] **Backfill mechanism** for missed data during processing delays
- [ ] Timezone conversion for user notifications
- [ ] Regional subsetting for performance
- [ ] Fire trend analysis
- [ ] Data retention policies

## NASA Data Quality Notes

### From Tutorial Observations

1. **Confidence Levels**: NASA recommends using 'normal' (n) and 'high' (h) confidence detections only
2. **Fire Power Threshold**: FRP >= 5 MW filters out low-intensity detections
3. **Version Differences**: URT and NRT may have slight detection differences due to processing algorithms
4. **Day/Night Variations**: Day detections (`daynight='D'`) generally more numerous than night (`daynight='N'`)

### Sample Data Insights (from NASA tutorial)

- **Total records**: 74,605 global detections in 24 hours
- **Version split**: 69,507 NRT + 5,098 URT records
- **Regional distribution**: 
  - Canada: 14,045 detections
  - Australia/NZ: 2,999 detections
  - USA/Hawaii: 900 detections

## API Rate Limiting and Best Practices

### NASA Recommendations

1. **Polling Frequency**: Every 10-15 minutes for NRT data
2. **User Agent**: Include descriptive User-Agent header
3. **Error Handling**: Implement exponential backoff for failures
4. **Data Freshness**: URT data available within 1 minute, NRT within 3-6 hours

### FirePing Implementation

```javascript
// Our implementation follows NASA guidelines
const NASA_API_CONFIG = {
  polling_interval: '*/10 * * * *',     // Every 10 minutes
  user_agent: 'FirePing/1.0 (https://fireping.net)',
  timeout: 30,                         // 30 second timeout
  retry_attempts: 3,                   // Retry failed requests
  quality_threshold: 70                // Confidence threshold
};
```

## Enhanced Fire Detection Strategy

### Current Implementation (V1)

**Simple approach** - our current system:
```javascript
// Every 10 minutes: fetch both MODIS and VIIRS data
// If empty response -> assume no fires
// If data present -> process and check against user locations
```

**Limitations**:
- Cannot distinguish "no fires" from "data not ready"
- Makes unnecessary API calls during processing delays
- May miss fires during data processing windows

### Recommended Enhancement (V2)

**Smart polling approach** for production:

```javascript
// Enhanced fire detection workflow
async function smartFireDetection() {
  // 1. Check data availability first
  const availability = await checkDataAvailability();
  
  // 2. Determine if fresh data is available
  const freshData = getLatestAvailableDate(availability);
  
  // 3. Only fetch if new data since last check
  if (freshData > lastProcessedDate) {
    const fires = await fetchFireData(freshData);
    processAndAlert(fires);
    lastProcessedDate = freshData;
  } else {
    logger.info("No new data available, skipping fetch");
  }
}
```

### Data Availability API Integration

**Optimized Approach**: Check each sensor individually for better performance:

**MODIS Availability**: `GET /api/data_availability/csv/{API_KEY}/MODIS_NRT`
**VIIRS Availability**: `GET /api/data_availability/csv/{API_KEY}/VIIRS_SNPP_NRT`

**Actual Response Format**:
```csv
data_id,min_date,max_date
MODIS_NRT,2025-05-01,2025-08-04
VIIRS_SNPP_NRT,2025-04-01,2025-08-04
VIIRS_NOAA20_NRT,2025-03-01,2025-08-04
```

**Note**: NASA's availability API only provides dates, not timestamps. This limits our ability to detect intraday data updates.

**Implementation Logic** (VIIRS Constellation):
```javascript
async function checkDataAvailability() {
  // Check all three VIIRS satellites individually
  const [snppAvail, noaa20Avail, noaa21Avail] = await Promise.all([
    fetch(`${NASA_BASE_URL}/data_availability/csv/${API_KEY}/VIIRS_SNPP_NRT`),
    fetch(`${NASA_BASE_URL}/data_availability/csv/${API_KEY}/VIIRS_NOAA20_NRT`),
    fetch(`${NASA_BASE_URL}/data_availability/csv/${API_KEY}/VIIRS_NOAA21_NRT`)
  ]);
  
  return {
    snpp: parseAvailabilityCSV(await snppAvail.text()),
    noaa20: parseAvailabilityCSV(await noaa20Avail.text()),
    noaa21: parseAvailabilityCSV(await noaa21Avail.text())
  };
}

function parseAvailabilityCSV(csvText) {
  const lines = csvText.trim().split('\n');
  const [header, ...rows] = lines;
  const data = rows[0].split(',');
  
  return {
    data_id: data[0],
    min_date: data[1],
    max_date: data[2]  // Latest date with available data
  };
}

function shouldFetchData(availability, lastProcessedDate) {
  // Since we only have dates (not timestamps), compare dates
  // Only fetch if max_date is newer than our last processed date
  return {
    fetchSNPP: availability.snpp.max_date > lastProcessedDate.snpp,
    fetchNOAA20: availability.noaa20.max_date > lastProcessedDate.noaa20,
    fetchNOAA21: availability.noaa21.max_date > lastProcessedDate.noaa21
  };
}
```

**Limitation**: Without timestamps, we can only detect new data at the day level, not hour level. This means:
- We might miss multiple updates within the same day
- We can't optimize for intraday processing schedules
- We must rely on date-based change detection
### Revised Strategy Given API Limitations

**What works well**:
- **Daily-level optimization**: Skip entire days when no new data
- **Sensor independence**: Check MODIS and VIIRS separately
- **Reduced calls**: Avoid fetching when `max_date` hasn't changed

**What doesn't work**:
- **Intraday optimization**: Can't detect multiple updates within same day
- **Time-based polling**: No timestamp means can't schedule around processing windows

**Practical approach** (VIIRS Constellation):
```javascript
// Hybrid strategy: Use availability for daily-level decisions
// Poll all three VIIRS satellites for comprehensive coverage
async function hybridFireDetection() {
  const availability = await checkDataAvailability();
  const today = new Date().toISOString().split('T')[0];
  
  // Check each VIIRS satellite independently
  const satellitesToFetch = [];
  
  if (availability.snpp.max_date >= today && !processedToday.snpp) {
    satellitesToFetch.push('VIIRS_SNPP_NRT');
  }
  if (availability.noaa20.max_date >= today && !processedToday.noaa20) {
    satellitesToFetch.push('VIIRS_NOAA20_NRT');
  }
  if (availability.noaa21.max_date >= today && !processedToday.noaa21) {
    satellitesToFetch.push('VIIRS_NOAA21_NRT');
  }
  
  // Fetch and process data from available satellites
  if (satellitesToFetch.length > 0) {
    await fetchAndProcessFires(satellitesToFetch);
    // Mark satellites as processed for today
    satellitesToFetch.forEach(sat => {
      processedToday[sat.toLowerCase().replace('viirs_', '').replace('_nrt', '')] = true;
    });
  }
  
  // Reset daily flags at midnight
  if (isNewDay()) {
    processedToday = { snpp: false, noaa20: false, noaa21: false };
  }
}
```

### Benefits of Enhanced Approach

1. **Reduced API Calls**: Skip requests when data isn't ready
2. **Sensor-Specific Optimization**: Check MODIS and VIIRS availability independently
3. **Better User Experience**: Explain data delays in UI
4. **Reliable Alerting**: Don't miss fires during processing windows
5. **Granular Control**: Fetch only sensors with fresh data available
6. **Cost Efficiency**: Lower API quota usage
7. **System Intelligence**: Understand NASA's data pipeline status per sensor

### Implementation Phases

**Phase 1 (Current)**: Simple polling - works but inefficient
**Phase 2 (Recommended)**: Smart polling with availability checks
**Phase 3 (Advanced)**: Predictive polling based on satellite schedules

### Backward Compatibility

The enhanced approach maintains full compatibility with current system:
- Same fire detection logic
- Same user notification flow  
- Same data storage format
- Only polling strategy changes

## Related NASA Resources

- **FIRMS Website**: https://firms.modaps.eosdis.nasa.gov/
- **API Documentation**: https://firms.modaps.eosdis.nasa.gov/api/
- **Data Availability Endpoint**: `/api/data_availability/csv/{API_KEY}/ALL`
- **Data Format Details**: https://www.earthdata.nasa.gov/learn/find-data/near-real-time/firms/
- **Regional Coordinates**: Available on FIRMS website
- **Python Tutorial**: https://firms.modaps.eosdis.nasa.gov/content/notebooks/

This reference ensures FirePing follows NASA's proven methodologies for FIRMS data processing and maintains compatibility with official NASA recommendations.