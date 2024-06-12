set -e

docker build . -t horizon-database-backup

docker run --rm \
    -e SERVER_NAME=$HORIZON_DB_SERVER \
    -e DATABASE_NAME=$HORIZON_DB_NAME \
    -e SQLCMD_USER=$HORIZON_DB_USER \
    -e SQLCMD_PASSWORD=$HORIZON_MSSQL_SA_PASSWORD \
    -e RESTORE_FILE=/backup/horizon_db_20240611000617.bak \
    -e MODE=restore \
    horizon-database-backup
