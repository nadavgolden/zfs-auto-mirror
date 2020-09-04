# zfs-auto-mirror
I wanted to be able to mirror my ZFS dataset to an off-site backup location so I started writing a script which would pull changes from the main server.
  
This script relies on having `zfs-auto-snapshot` installed on the main server.
