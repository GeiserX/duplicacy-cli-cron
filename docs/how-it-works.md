# How it works

Each server backs up to an **S3 endpoint**. When using [Garage](https://garagehq.deuxfleurs.fr/) with replication factor 2, data is automatically replicated across cluster nodes -- no secondary Duplicacy storage needed:

```
Server A ──backup──> Garage S3 cluster (RF=2)
Server B ──backup──>    ├─ Node 1
Server C ──backup──>    ├─ Node 2
                        └─ Node 3
```

The daily wrapper scripts are four lines each and source the shared `dual-executor.sh`, which handles locking, backup, prune, and notification logic.
