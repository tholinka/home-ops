# MongoDBCommunity

MongoDBCommunity requires the DB to be in the same namespace as the operator 😓

Creates a database with the specified user as the `dbOwner`.

URL will have the format `mongodb://${MONGO_USER}:${MONGO_PASSWORD}@mongo-${APP}-0.mongo-${APP}-svc.database.svc.cluster.local/${MONGO_DB}`.

### Variables to set:

```yaml
  postBuild:
    substitute:
      MONGO_APP: *app # required
      # renovate: datasource=docker depName=mongodb/mongodb-community-server
      MONGO_VERSION: 8.0.5 # required
      # this HAS to be upgraded before going to the next major version (e.g. can go from 7->8 with this set to 7, but can't go from 8->9 without changing this to 8)
      MONGO_VERSION_COMPATIBILITY: '8.0' # default's to match MONGO_VERSION
      MONGO_SECRET_FROM: *app # required, entry external-secret uses
      MONGO_DB: *app # required
      MONGO_USER: *app # required
      MONGO_REPLICAS: '1' # default - if this is anything but 1, the volsync pvcs for the other replicas will need to be manually created before changing this!
      MONGO_REQUESTS_CPU: 500m # default
      MONGO_REQUESTS_MEMORY: 400M # default
      MONGO_LIMITS_CPU: '1' # default
      MONGO_LIMITS_MEMORY: 500M # default
      MONGO_PVC_SIZE: 5Gi # default -> if using volsync this is ignored
      MONGO_PVC_LOG_SIZE: 2Gi # default
      MONGO_PVC_STORAGE_CLASS: ceph-block # default
```

### Secrets

Create a secret named the same as the `MONGO_SECRET_FROM` variable. It needs to have the following items:

```yaml
MONGO_PASSWORD: random password # database user password
MONGO_PROM_PASSWORD: random different password # prometheus service monitor password
```

### Volsync

If `replicas: 1`, the volsync component works. Otherwise, manually create the volsync items

```yaml
  postBuild:
    substitute:
      MONGO_APP: mongo-example-name
      APP: data-volume-mongo-example-name-0 # set APP so that the volsync component creates the correct pvc
      VOLSYNC_CAPACITY: 5Gi # -> this is used instead of MONGO_PVC_SIZE
```

### Healthecks

```yaml
  healthChecks:
    - apiVersion: &apiVersion mongodbcommunity.mongodb.com/v1
      kind: &kind MongoDBCommunity
      name: *app
      namespace: *namespace
  healthCheckExprs:
    - apiVersion: *apiVersion
      kind: *kind
      failed: status.phase == 'Failed'
      current: status.phase == 'Running'
```


### Dump / Restore

Can use `mongodump` and `mongorestore` to dump and restore the db. This is required for instance if you rename the dbs

```yaml
kubectl exec -n database mongo-APP-0 -- mongodump mongodb://username:password@localhost:27017 --authenticationDatabase=db-name --archive /data/archive
kubectl cp mongo-APP-0:/data/archive archive

kubectl cp archive mongo-APP-0:/data/archive
kubectl exec -ng database mongo-APP-0 -- mongorestore mongodb://username:password@localhost:27017 --authenticationDatabase=db-name --archive /data/archive
```
