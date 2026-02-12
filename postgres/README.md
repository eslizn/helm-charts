# PostgreSQL Helm Chart

This Helm chart deploys a PostgreSQL database as a StatefulSet with persistent storage.

## Features

- **StatefulSet Deployment**: Ensures stable network identities and persistent storage
- **Automatic Password Generation**: Random passwords generated on installation
- **Post-Install Hook**: Displays connection information after installation
- **Persistent Storage**: Data persistence with configurable storage options

## Configuration

### Basic Configuration

```yaml
# values.yaml
replicaCount: 1

image:
  repository: postgres
  tag: "latest"

service:
  type: ClusterIP
  port: 5432
```

### Password Configuration

Enable automatic password generation:

```yaml
config:
  enabled: true
  database: "postgres"
  username: "postgres"
  password:
    generate: true
    length: 16
    includeSpecialChars: true
    includeNumbers: true
    includeUppercase: true
    includeLowercase: true
```

### Storage Configuration

```yaml
persistence:
  enabled: true
  storageClass: ""
  accessModes:
    - ReadWriteOnce
  size: 10Gi
  mountPath: /var/lib/postgresql/data
```

## Installation

```bash
helm install my-postgres ./postgres
```

## Password Output

After installation, a post-install hook will run and display the connection information including the randomly generated password:

```
==================================================
PostgreSQL Installation Complete
==================================================
Database Name: mydatabase
Username: postgres
Password: [randomly-generated-password]
Service: my-postgres
Port: 5432

Connection String:
postgresql://postgres:[password]@my-postgres:5432/mydatabase
==================================================
```

## Custom Password

If you prefer to use a custom password instead of auto-generated one:

```yaml
config:
  password:
    generate: false

# Create a secret manually with your password
# kubectl create secret generic my-postgres-password --from-literal=postgres-password=your-password
```

## Upgrades

When upgrading the chart, the existing password will be preserved unless you manually delete the secret.

## Troubleshooting

- If the post-install hook fails, you can view the password by:
  ```bash
  kubectl get secret my-postgres-password -o jsonpath='{.data.postgres-password}' | base64 -d
  ```

- To reset the password, delete the secret and upgrade the chart:
  ```bash
  kubectl delete secret my-postgres-password
  helm upgrade my-postgres ./postgres
  ```