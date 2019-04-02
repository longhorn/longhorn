# Volume operations

### Changing replica count of the volumes

The default replica count can be changed in the setting.

Also, when a volume is attached, the user can change the replica count for the volume in the UI.

Longhorn will always try to maintain at least given number of healthy replicas for each volume. If the current healthy 
replica count is less than specified replica count, Longhorn will start rebuilding new replicas. If the current healthy 
replica count is more than specified replica count, Longhorn will do nothing. In the later situation, if user delete one 
or more healthy replicas, or there are healthy replicas failed, as long as the total healthy replica count doesn't dip 
below the specified replica count, Longhorn won't start rebuilding new replicas.
