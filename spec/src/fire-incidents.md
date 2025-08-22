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
