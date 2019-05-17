# Disaster Recovery Volume
## What is Disaster Recovery Volume?
To increase the resiliency of the volume, Longhorn supports disaster recovery volume.
 
The disaster recovery volume is designed for the backup cluster in the case of the whole main cluster goes down. 
A disaster recovery volume is normally in standby mode. User would need to activate it before using it as a normal volume.
A disaster recovery volume can be created from a volume's backup in the backup store. And Longhorn will monitor its 
original backup volume and incrementally restore from the latest backup. Once the original volume in the main cluster goes
down and users decide to activate the disaster recovery volume in the backup cluster, the disaster recovery volume can be
activated immediately in the most condition, so it will greatly reduced the time needed to restore the data from the
backup store to the volume in the backup cluster.

## How to create Disaster Recovery Volume?
1. In the cluster A, make sure the original volume X has backup created or recurring backup scheduling.
2. Set backup target in cluster B to be same as cluster A's.
3. In backup page of cluster B, choose the backup volume X then create disaster recovery volume Y. It's highly recommended
to use backup volume name as disaster volume name.
4. Attach the disaster recovery volume Y to any node. Then Longhorn will automatically polling for the last backup of the
volume X, and incrementally restore it to the volume Y.
5. If volume X is down, users can activate volume Y immediately. Once activated, volume Y will become a 
normal Longhorn volume.
    5.1. Notice that deactivate a normal volume is not allowed.

## About Activating Disaster Recovery Volume
1. A disaster recovery volume doesn't support creating/deleting/reverting snapshot, creating backup, creating
PV/PVC. Users cannot update `Backup Target` in Settings if any disaster recovery volumes exist.

2. When users try to activate a disaster recovery volume, Longhorn will check the last backup of the original volume. If
it hasn't been restored, the restoration will be started, and the activate action will fail. Users need to wait for 
the restoration to complete before retrying.

3. For disaster recovery volume, `Last Backup` indicates the most recent backup of its original backup volume. If the icon 
representing disaster volume is gray, it means the volume is restoring `Last Backup` and users cannot activate this 
volume right now; if the icon is blue, it means the volume has restored the `Last Backup`. 

## RPO and RTO
Typically incremental restoration is triggered by the periodic backup store update. Users can set backup store update 
interval in `Setting - General - Backupstore Poll Interval`. Notice that this interval can potentially impact 
Recovery Time Objective(RTO). If it is too long, there may be a large amount of data for the disaster recovery volume to 
restore, which will take a long time. As for Recovery Point Objective(RPO), it is determined by recurring backup 
scheduling of the backup volume. You can check [here](snapshot-backup.md) to see how to set recurring backup in Longhorn.

e.g.:

If recurring backup scheduling for normal volume A is creating backup every hour, then RPO is 1 hour.

Assuming the volume creates backup every hour, and incrementally restoring data of one backup takes 5 minutes.  

If `Backupstore Poll Interval` is 30 minutes, then there will be at most one backup worth of data since last restoration.
The time for restoring one backup is 5 minute, so RTO is 5 minutes.

If `Backupstore Poll Interval` is 12 hours, then there will be at most 12 backups worth of data since last restoration.
The time for restoring the backups is 5 * 12 = 60 minutes, so RTO is 60 minutes.