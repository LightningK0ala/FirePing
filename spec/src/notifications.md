# Notifications

When a fire is detected within a user's location boundary, a notification is sent to the user.

In order to prevent multiple separate notifications for the same fire incident, we want to accumulate the number of fires detected in an incident cluster and send a single notification for the incident, citing the number of new fires detected.

We should group the number of fires by fire incident and run an oban worker / job (need a good name for this) who's task is to take the fires, related fire incident and an indication if the incident is new or updated, and query for locations with boundaries that match the fire locations. The aim is to deduplicate the fires by incident and dispatch the entire notifications batch (single notification per incident) to a Notification worker / oban job.

The same module I said we need a good name for will also handle incidents that have ended, which will be triggered by the IncidentDeletion worker.

I think the following functions will be affected:

- App.Fire.assign_to_incident/2
- App.Fire.process_unassigned_fires/1
- App.Workers.FireClustering.perform/1
