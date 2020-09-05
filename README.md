# zfs-auto-mirror
The script compares the local and the remote snapshots, and tries to transfer incremental updates. 

## Install
```
# git clone 
# cd zfs-auto-mirror
# sudo make install
```

## Usage
```
Usage: zfs-auto-mirror target remote_dataset local_dataset

      target          user@host of server to mirror
      remote_dataset  Name of the dataset to mirror from
      local_dataset   Name of the dataset to mirror to
```

## Notes
Notes about the script:
- It runs **on the mirror** - it pulls changes from the main server.
- It does not remove snapshots which has been deleted on the main server. Currently it keeps them forever.
