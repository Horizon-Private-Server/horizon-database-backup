set -e

docker build . -t horizon-database-backup

docker run --rm \
    -e SERVER_NAME=$HORIZON_DB_SERVER \
    -e DATABASE_NAME=$HORIZON_DB_NAME \
    -e SQLCMD_USER=$HORIZON_DB_USER \
    -e SQLCMD_PASSWORD=$HORIZON_MSSQL_SA_PASSWORD \
    -e BACKUP_PATH=/ \
    horizon-database-backup

source /root/.bashrc && aws s3 sync $DATABASE_BACKUP_LOC $DATABASE_BACKUP_S3_DEST --exact-timestamps --no-progress
