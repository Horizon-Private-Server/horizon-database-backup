#!/bin/bash

# Check if all required environment variables are set
if [ -z "$SERVER_NAME" ] || [ -z "$DATABASE_NAME" ] || [ -z "$SQLCMD_USER" ] || [ -z "$SQLCMD_PASSWORD" ] ; then
    echo "One or more required environment variables are not set:"
    echo "SERVER_NAME, DATABASE_NAME, SQLCMD_USER, SQLCMD_PASSWORD"
    exit 1
fi

# Get the current timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Generate the backup file path with the timestamp
BACKUP_FILE="/backup/horizon_db_${TIMESTAMP}.bak"

echo "Creating backup ..."

# Run the backup command
/opt/mssql-tools/bin/sqlcmd -S $SERVER_NAME -U $SQLCMD_USER -P $SQLCMD_PASSWORD -Q "BACKUP DATABASE [$DATABASE_NAME] TO DISK = N'$BACKUP_FILE' WITH NOFORMAT, NOINIT, NAME = '$DATABASE_NAME-Full Database Backup', SKIP, NOREWIND, NOUNLOAD, STATS = 10"

echo "Backup completed: $BACKUP_FILE"
