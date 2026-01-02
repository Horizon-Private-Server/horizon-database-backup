set -e

docker build . -t horizon-database-backup

docker run --rm \
    -e SERVER_NAME=$HORIZON_DB_SERVER \
    -e DATABASE_NAME=$HORIZON_DB_NAME \
    -e SQLCMD_USER=$HORIZON_DB_USER \
    -e SQLCMD_PASSWORD=$HORIZON_MSSQL_SA_PASSWORD \
    -e BACKUP_PATH=/ \
    -e MODE=backup \
    horizon-database-backup

source /root/.bashrc && \
AWS_ACCESS_KEY_ID="$BACKUP_AWS_ACCESS_KEY_ID" \
AWS_SECRET_ACCESS_KEY="$BACKUP_AWS_SECRET_ACCESS_KEY" \
AWS_DEFAULT_REGION="$BACKUP_AWS_REGION" \
aws s3 sync "$DATABASE_BACKUP_LOC" "$DATABASE_BACKUP_S3_DEST" \
  --exact-timestamps \
  --no-progress
