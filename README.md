# zfs-auto-mirror
The script compares the local and the remote snapshots, and tries to transfer incremental updates. Can be used as a companion app to [`zfs-auto-snapshot`](https://github.com/zfsonlinux/zfs-auto-snapshot).

## Install
```
# git clone https://github.com/nadavgolden/zfs-auto-mirror.git
# cd zfs-auto-mirror
# sudo make install
```

\* **Note**: for the `--progress` option to work, `pv` should be installed, e.g.:
```
# sudo apt install pv
```

## Usage
```
Usage: zfs-auto-mirror [options] target remote_dataset local_dataset
  options:
    -f             Force full sync if conflict is detected between local and remote snapshots
    -d N           Print N-th log level (1=DEBUG, 2=INFO, 3=WARNING, 4=ERROR)

    -h, --help           Print this usage message
    -l, --label          Filter this label from snapshots (default: daily)
    -p, --progress       Display data transfer information. 'pv' installation required
    -D, --destroy=DAYS   Destroy snapshots taken up to DAYS days ago
  
  positional:
    target          user@remote, used for SSH
    local_dataset   The dataset to mirror into
    remote_dataset  The dataset to mirror from
```

## Prerequisites
1. ZFS installed (duh).
2. User on remote should be allowed to:
    ```
    # zfs allow <user> send,hold <dataset>
    ```
3. User on mirror (local machine) should be allowed to:
    ```
    # zfs allow <user> create,destroy,mount,receive <dataset>
    ```
4. SSH to remote with public key authentication so that SSH would not prompt for password.

## Notes
Notes about the script:
- It runs **on the mirror** - it pulls changes from the main server. This is by design.
- It does not remove snapshots which has been deleted on the main server.
