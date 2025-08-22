## Fire Incidents

Data from the FIRMS satellites are recorded as a "fire" record.
Alongside this, we also store "fire_incident" records which track the lifecyle of a fire, based on the detection of fires made.

If a detection cannot be matched to an existing incident, a new incident record is created. Otherwise, the existing incident record is updated to reflect the number of fire detections made, the last detection made and to update its status based some state transition policy.

Incident state:

- :active
- :ended

An incident is created with an :active state, eventually, when no fire detections within that incident's cluster are detected after 24 hours, the incident is moved to the ended state.

Once ended, the incident will no longer be included in incident queries when trying to cluster a detection into an incident. All "fires" associated with that incident are purged from the database. We may decide to keep some metrics about the incident such as min / max / average / mean fire intensity in MW, an array of the coordinates of all the detections made which can be used to reconstruct a heat map estimate of the total area affected and other pertinent data. But the purpose of the purge is to prevent runaway data storage requirements.

After @incident_delete_threshold (1 year?) we delete the incidents, unless the number of incidents stored per year is reasonable. This data might become use for data analysis such as to create annual global, country and regional fire reports.

A periodic (hourly?) oban cron job is used to check if ongoing active incidents have passed the 24 hours to perform the state transition and trigger a notification to users in affected location boundaries.

## Notification triggers

User notifications are triggered according to notification preferences for incidents within location boundaries when:

- New incident is created with # of fire points detected in cluster.
- New fire(s) detected during scheduled FIRMS fetch in incident cluster (include count of all new detected fire points).
- Incident transitions to :end state.

The frequency of the above will be dictated by user location / notification preferences in the future, including ignoring fires with an intensity below specified thresholds.

Notification deliveries should be tracked in a database table to enable control over the frequency of notifications, as well as provide telemetry and status on the delivery.

## Fire-Free Area Determination Strategy

Based on NASA FIRMS satellite flyover frequency, we implement a tiered confidence system for determining when an area should be considered fire-free. This leverages the fact that the VIIRS constellation provides 6 daily passes (3 daytime, 3 nighttime) over most locations.

### Flyover Frequency

- **VIIRS Constellation**: 6 passes per day (approximately every 4 hours)
  - 3 daytime passes (around 1:30 PM local time)
  - 3 nighttime passes (around 1:30 AM local time)
- **Satellites**: VIIRS S-NPP, NOAA-20, and NOAA-21 in coordinated orbits
- **Processing Delays**: NRT data has 3-6 hour delay, RT has 30-minute delay, URT has 1-minute delay

### Confidence-Based Implementation

```javascript
// Tiered confidence system for fire-free determination
const FIRE_FREE_CONFIDENCE = {
  HIGH: 48,    // 48+ hours without detection = high confidence fire-free
  MEDIUM: 24,  // 24-48 hours without detection = medium confidence  
  LOW: 12,     // 12-24 hours without detection = low confidence
  UNCERTAIN: 6 // < 12 hours since last check = uncertain/too recent
};

// Default threshold for incident state transition
const DEFAULT_INCIDENT_END_THRESHOLD = FIRE_FREE_CONFIDENCE.MEDIUM; // 24 hours

// Implementation example
function determineFireStatus(incident, lastDetectionTimestamp) {
  const hoursSinceLastDetection = calculateHoursBetween(new Date(), lastDetectionTimestamp);
  
  if (hoursSinceLastDetection >= FIRE_FREE_CONFIDENCE.HIGH) {
    return { status: 'FIRE_FREE', confidence: 'HIGH' };
  } else if (hoursSinceLastDetection >= FIRE_FREE_CONFIDENCE.MEDIUM) {
    return { status: 'FIRE_FREE', confidence: 'MEDIUM' };
  } else if (hoursSinceLastDetection >= FIRE_FREE_CONFIDENCE.LOW) {
    return { status: 'FIRE_FREE', confidence: 'LOW' };
  } else {
    return { status: 'UNCERTAIN', confidence: 'VERY_LOW' };
  }
}
```

### Rationale for Thresholds

- **48 hours (High Confidence)**: Covers 12 complete satellite passes, accounting for potential cloud cover or satellite issues
- **24 hours (Medium Confidence)**: Covers 6 complete passes, our default threshold for incident state transition
- **12 hours (Low Confidence)**: Covers 3 passes, minimum recommended threshold
- **< 12 hours (Uncertain)**: Too few passes to make a reliable determination

### Future Enhancements

- **Regional Adjustments**: Modify thresholds based on historical satellite coverage quality in different regions
- **Weather-Aware Confidence**: Incorporate cloud cover data to adjust confidence levels
- **User-Configurable Thresholds**: Allow users to select their preferred confidence level for notifications
- **Satellite-Specific Tracking**: Track detection status per satellite to improve confidence calculation
